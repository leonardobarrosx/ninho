-- Layette (enxoval) options: each goal can hold up to five product options (title, link, image, store, price),
-- one of them chosen as the main one. The chosen option's price sets the goal's budget, prices are kept in a
-- history whenever they change, and the API checks the links once a day with the secret key.
begin;

alter table public.goals
 add column category text not null default '' check(char_length(category)<=40),
 add column sort_order integer not null default 0 check(sort_order between 0 and 100000),
 add column chosen_option_id uuid,
 add constraint goals_id_household_key unique(id,household_id);

create table public.goal_options (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 goal_id uuid not null,
 title text not null check(char_length(trim(title)) between 1 and 160),
 url text not null default '' check(char_length(url)<=2000 and (url='' or url ~* '^https?://[^[:space:]]+$')),
 -- Only HTTPS images: the web app shows them inside an HTTPS page.
 image_url text not null default '' check(char_length(image_url)<=2000 and (image_url='' or image_url ~* '^https://[^[:space:]]+$')),
 description text not null default '' check(char_length(description)<=600),
 store text not null default '' check(char_length(store)<=80),
 price_cents bigint check(price_cents between 0 and 99999999999),
 -- The price before the discount, when the store shows one.
 list_price_cents bigint check(list_price_cents between 0 and 99999999999),
 notes text not null default '' check(char_length(notes)<=2000),
 -- Written only by the triggers below and by the daily check (secret key), never by clients.
 previous_price_cents bigint,
 previous_list_price_cents bigint,
 price_changed_at timestamptz,
 checked_at timestamptz,
 check_failed boolean not null default false,
 created_at timestamptz not null default now(),
 foreign key(goal_id,household_id) references public.goals(id,household_id) on delete cascade,
 unique(id,goal_id),
 unique(id,household_id)
);
create index goal_options_household_idx on public.goal_options(household_id,id);
create index goal_options_goal_idx on public.goal_options(goal_id);

-- The chosen option must belong to the same goal. Deleting it only clears the choice.
alter table public.goals add constraint goals_chosen_option_fkey foreign key(chosen_option_id,id)
 references public.goal_options(id,goal_id) on delete set null(chosen_option_id);

create table public.goal_option_prices (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null,
 option_id uuid not null,
 recorded_at timestamptz not null default now(),
 price_cents bigint not null check(price_cents between 0 and 99999999999),
 list_price_cents bigint check(list_price_cents between 0 and 99999999999),
 foreign key(option_id,household_id) references public.goal_options(id,household_id) on delete cascade
);
create index goal_option_prices_option_idx on public.goal_option_prices(option_id,recorded_at);
create index goal_option_prices_household_idx on public.goal_option_prices(household_id,id);

-- Before writing an option: at most five per goal, and a price change keeps the old values and the time.
create function private.goal_option_before() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  perform 1 from public.goals where id=new.goal_id for update;
  if (select count(*) from public.goal_options where goal_id=new.goal_id)>=5 then raise exception 'Too many options';end if;
 elsif old.price_cents is not null and new.price_cents is not null
  and (new.price_cents<>old.price_cents or new.list_price_cents is distinct from old.list_price_cents) then
  new.previous_price_cents:=old.price_cents;
  new.previous_list_price_cents:=old.list_price_cents;
  new.price_changed_at:=now();
 end if;
 return new;
end $$;
create trigger goal_option_before before insert or update on public.goal_options
 for each row execute function private.goal_option_before();

-- After writing an option: record the price in the history when it is new or changed, make the first option
-- of a goal its main one, and refresh the budget of the goal whose main option this is.
create function private.goal_option_after() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.price_cents is not null and (tg_op='INSERT' or new.price_cents is distinct from old.price_cents
  or new.list_price_cents is distinct from old.list_price_cents) then
  insert into public.goal_option_prices(household_id,option_id,price_cents,list_price_cents)
   values(new.household_id,new.id,new.price_cents,new.list_price_cents);
  -- A year of changes is plenty for a layette item.
  delete from public.goal_option_prices where option_id=new.id and id not in
   (select id from public.goal_option_prices where option_id=new.id order by recorded_at desc limit 365);
 end if;
 if tg_op='INSERT' then
  update public.goals set chosen_option_id=new.id where id=new.goal_id and chosen_option_id is null;
 end if;
 update public.goals set target_cents=target_cents where chosen_option_id=new.id;
 return null;
end $$;
create trigger goal_option_after after insert or update on public.goal_options
 for each row execute function private.goal_option_after();

-- After deleting the main option, the cheapest remaining one takes its place.
create function private.goal_option_deleted() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.goals set chosen_option_id=(select o.id from public.goal_options o where o.goal_id=old.goal_id
  order by o.price_cents nulls last,o.created_at,o.id limit 1)
  where id=old.goal_id and chosen_option_id is null;
 return null;
end $$;
create trigger goal_option_deleted after delete on public.goal_options
 for each row execute function private.goal_option_deleted();

-- A goal with a priced main option budgets that price for the whole quantity.
create function private.goal_budget() returns trigger language plpgsql security definer set search_path='' as $$
declare price bigint;begin
 if new.chosen_option_id is not null then
  select o.price_cents into price from public.goal_options o where o.id=new.chosen_option_id;
  if price is not null then new.target_cents:=least(price*new.quantity,99999999999);end if;
 end if;
 return new;
end $$;
create trigger goal_budget before insert or update on public.goals
 for each row execute function private.goal_budget();

revoke all on function private.goal_option_before(),private.goal_option_after(),private.goal_option_deleted(),private.goal_budget()
 from public,anon,authenticated;

alter table public.goal_options enable row level security;
alter table public.goal_option_prices enable row level security;
create policy tenant_access on public.goal_options for all to authenticated
 using(private.is_member(household_id)) with check(private.is_member(household_id));
create policy history_read on public.goal_option_prices for select to authenticated using(private.is_member(household_id));

-- Column allowlists. Keep them in sync with `fields` in backend/internal/api/server.go.
revoke all on public.goal_options,public.goal_option_prices from anon,authenticated;
grant select,delete on public.goal_options to authenticated;
grant insert(household_id,goal_id,title,url,image_url,description,store,price_cents,list_price_cents,notes),
 update(title,url,image_url,description,store,price_cents,list_price_cents,notes) on public.goal_options to authenticated;
grant select on public.goal_option_prices to authenticated;
grant insert(category,sort_order),update(category,sort_order,chosen_option_id) on public.goals to authenticated;
commit;
