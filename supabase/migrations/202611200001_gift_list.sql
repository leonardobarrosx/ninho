-- Gift list (Plus): a family shares a page of its layette where friends and family choose items, or part of an
-- item, and pay the couple directly by Pix. Ninho takes no payment: a contribution records what the visitor says
-- they sent, and the family confirms it when the money arrives. Plus is bought once per account, and a family
-- has it when one of its people bought it.
begin;

-- Accounts with Plus. Written only by the server, with the secret key, once a purchase is confirmed.
create table public.plus_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 granted_at timestamptz not null default now(),
 source text not null default '' check(char_length(source)<=200)
);
alter table public.plus_accounts enable row level security;
create policy own_plus on public.plus_accounts for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.plus_accounts from anon,authenticated;
grant select on public.plus_accounts to authenticated;

create function private.household_plus(h uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.household_members m join public.plus_accounts p on p.user_id=m.user_id
  where m.household_id=h);
$$;
revoke all on function private.household_plus(uuid) from public,anon,authenticated;

-- Whether a family of the caller has Plus, for the app.
create function public.household_has_plus(p_household_id uuid) returns boolean language sql stable security definer
 set search_path='' as $$
 select private.is_member(p_household_id) and private.household_plus(p_household_id);
$$;
revoke all on function public.household_has_plus(uuid) from public,anon;
grant execute on function public.household_has_plus(uuid) to authenticated;

-- Items the family keeps off the list, such as what they already have in mind to buy themselves.
alter table public.goals add column gift boolean not null default true;

create table public.gift_lists (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null unique references public.households(id) on delete cascade,
 -- The link: /lista/<slug>.
 slug text not null unique check(slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' and slug !~ '--'),
 published boolean not null default false,
 template text not null default 'cards' check(template in ('cards','polaroid','lista','minimal')),
 palette text not null default 'pessego' check(palette in ('pessego','menta','ceu','lavanda','areia')),
 title text not null check(char_length(trim(title)) between 1 and 80),
 message text not null default '' check(char_length(message)<=600),
 show_prices boolean not null default true,
 allow_partial boolean not null default true,
 -- The receiver of the Pix, as the BR Code carries it: key, name (25 characters) and city (15).
 pix_key text not null default '' check(char_length(pix_key)<=77),
 pix_name text not null default '' check(char_length(pix_name)<=25),
 pix_city text not null default '' check(char_length(pix_city)<=15),
 created_at timestamptz not null default now(),
 unique(id,household_id)
);

-- A list goes public only with Plus and a Pix receiver.
create function private.gift_list_check() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.published then
  if not private.household_plus(new.household_id) then raise exception 'Plus required';end if;
  if trim(new.pix_key)='' or trim(new.pix_name)='' or trim(new.pix_city)='' then raise exception 'Pix required';end if;
 end if;
 return new;
end $$;
create trigger gift_list_check before insert or update on public.gift_lists
 for each row execute function private.gift_list_check();

create table public.gift_contributions (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null,
 list_id uuid not null,
 name text not null check(char_length(trim(name)) between 1 and 80),
 message text not null default '' check(char_length(message)<=600),
 amount_cents bigint not null check(amount_cents between 100 and 5000000),
 status text not null default 'pending' check(status in ('pending','confirmed','declined')),
 created_at timestamptz not null default now(),
 decided_at timestamptz,
 foreign key(list_id,household_id) references public.gift_lists(id,household_id) on delete cascade,
 unique(id,household_id)
);
create index gift_contributions_household_idx on public.gift_contributions(household_id,id);

-- What a contribution pays for. The title is kept for when the item is deleted.
create table public.gift_contribution_items (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null,
 contribution_id uuid not null,
 goal_id uuid,
 title text not null check(char_length(title) between 1 and 120),
 amount_cents bigint not null check(amount_cents between 1 and 5000000),
 foreign key(contribution_id,household_id) references public.gift_contributions(id,household_id) on delete cascade,
 foreign key(goal_id,household_id) references public.goals(id,household_id) on delete set null(goal_id)
);
create index gift_contribution_items_household_idx on public.gift_contribution_items(household_id,id);
create index gift_contribution_items_goal_idx on public.gift_contribution_items(goal_id);

-- What an item still needs: its budget for the units not acquired, minus gifts not declined.
create function private.gift_needed(g public.goals) returns bigint language sql stable security definer set search_path='' as $$
 select greatest(0,g.target_cents*(g.quantity-g.acquired)/g.quantity-coalesce((select sum(i.amount_cents)
  from public.gift_contribution_items i join public.gift_contributions c on c.id=i.contribution_id
  where i.goal_id=g.id and c.status<>'declined'),0))::bigint;
$$;
revoke all on function private.gift_needed(public.goals) from public,anon,authenticated;

-- The public page of a list, or null. Called by the API with the secret key.
create function public.gift_page(p_slug text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare l public.gift_lists;begin
 select * into l from public.gift_lists where slug=lower(p_slug) and published;
 if not found or not private.household_plus(l.household_id) then return null;end if;
 return jsonb_build_object(
  'title',l.title,'message',l.message,'template',l.template,'palette',l.palette,
  'show_prices',l.show_prices,'allow_partial',l.allow_partial,
  'pix_key',l.pix_key,'pix_name',l.pix_name,'pix_city',l.pix_city,
  'babies',coalesce((select jsonb_agg(b.name order by b.created_at) from public.babies b where b.household_id=l.household_id),'[]'),
  'items',coalesce((select jsonb_agg(jsonb_build_object(
    'id',g.id,'title',g.title,'category',g.category,'priority',g.priority,
    'quantity',g.quantity-g.acquired,
    'image_url',coalesce(o.image_url,''),
    'total_cents',g.target_cents*(g.quantity-g.acquired)/g.quantity,
    'needed_cents',private.gift_needed(g)) order by g.sort_order,g.created_at,g.id)
   from public.goals g left join public.goal_options o on o.id=g.chosen_option_id
   where g.household_id=l.household_id and g.gift and g.acquired<g.quantity and g.target_cents>0),'[]'));
end $$;
revoke all on function public.gift_page(text) from public,anon,authenticated;

-- Records a contribution from the public page: items with amounts, and any free amount. Called by the API with
-- the secret key. Returns its id.
create function public.record_gift(p_slug text,p_name text,p_message text,p_items jsonb,p_free_cents bigint)
 returns uuid language plpgsql security definer set search_path='' as $$
declare l public.gift_lists;g public.goals;item jsonb;amount bigint;total bigint:=coalesce(p_free_cents,0);
 contribution uuid;needed bigint;begin
 select * into l from public.gift_lists where slug=lower(p_slug) and published for update;
 if not found or not private.household_plus(l.household_id) then raise exception 'List unavailable';end if;
 if jsonb_typeof(coalesce(p_items,'[]'))<>'array' or jsonb_array_length(coalesce(p_items,'[]'))>50 then
  raise exception 'Invalid gift';end if;
 if total<0 then raise exception 'Invalid gift';end if;
 insert into public.gift_contributions(household_id,list_id,name,message,amount_cents)
  values(l.household_id,l.id,trim(p_name),coalesce(p_message,''),greatest(total,100)) returning id into contribution;
 for item in select * from jsonb_array_elements(coalesce(p_items,'[]')) loop
  select * into g from public.goals where id=(item->>'goal_id')::uuid and household_id=l.household_id
   and gift and acquired<quantity and target_cents>0 for update;
  if not found then raise exception 'Item unavailable';end if;
  amount:=(item->>'amount_cents')::bigint;
  needed:=private.gift_needed(g);
  if amount is null or amount<1 or amount>needed or (not l.allow_partial and amount<>needed) then
   raise exception 'Invalid amount';end if;
  if exists(select 1 from public.gift_contribution_items where contribution_id=contribution and goal_id=g.id) then
   raise exception 'Invalid gift';end if;
  insert into public.gift_contribution_items(household_id,contribution_id,goal_id,title,amount_cents)
   values(l.household_id,contribution,g.id,g.title,amount);
  total:=total+amount;
 end loop;
 if total<100 then raise exception 'Invalid amount';end if;
 update public.gift_contributions set amount_cents=total where id=contribution;
 return contribution;
end $$;
revoke all on function public.record_gift(text,text,text,jsonb,bigint) from public,anon,authenticated;

-- The family confirms that a Pix arrived, or declines one that did not. A confirmed gift goes into the money
-- reserved for its items; undoing it takes it back out.
create function public.decide_gift(p_id uuid,p_status text) returns void language plpgsql security definer
 set search_path='' as $$
declare c public.gift_contributions;sign integer;begin
 select * into c from public.gift_contributions where id=p_id for update;
 if not found or not private.is_member(c.household_id) then raise exception 'Gift unavailable';end if;
 if p_status not in ('pending','confirmed','declined') then raise exception 'Invalid status';end if;
 if c.status=p_status then return;end if;
 sign:=case when p_status='confirmed' then 1 when c.status='confirmed' then -1 else 0 end;
 if sign<>0 then
  update public.goals g set saved_cents=least(99999999999,greatest(0,g.saved_cents+sign*i.amount_cents))
   from public.gift_contribution_items i where i.contribution_id=c.id and i.goal_id=g.id;
 end if;
 update public.gift_contributions set status=p_status,decided_at=case when p_status='pending' then null else now() end
  where id=c.id;
end $$;
revoke all on function public.decide_gift(uuid,text) from public,anon;
grant execute on function public.decide_gift(uuid,text) to authenticated;

revoke all on function private.gift_list_check() from public,anon,authenticated;

alter table public.gift_lists enable row level security;
alter table public.gift_contributions enable row level security;
alter table public.gift_contribution_items enable row level security;
create policy tenant_access on public.gift_lists for all to authenticated
 using(private.is_member(household_id)) with check(private.is_member(household_id));
create policy gifts_read on public.gift_contributions for select to authenticated using(private.is_member(household_id));
create policy gift_items_read on public.gift_contribution_items for select to authenticated
 using(private.is_member(household_id));

-- Column allowlists. Keep them in sync with `fields` in backend/internal/api/server.go.
revoke all on public.gift_lists,public.gift_contributions,public.gift_contribution_items from anon,authenticated;
grant select,delete on public.gift_lists to authenticated;
grant insert(household_id,slug,published,template,palette,title,message,show_prices,allow_partial,pix_key,pix_name,pix_city),
 update(slug,published,template,palette,title,message,show_prices,allow_partial,pix_key,pix_name,pix_city)
 on public.gift_lists to authenticated;
grant select on public.gift_contributions,public.gift_contribution_items to authenticated;
grant insert(gift),update(gift) on public.goals to authenticated;
commit;
