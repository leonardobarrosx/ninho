-- More with Plus: a family with Plus takes up to eight people instead of four, and each layette item up to ten
-- options instead of five. The gift list page gains the date of the baby shower, for a countdown, and three
-- palettes. Nothing a family without Plus has today goes away.
begin;

-- How many people and how many options per item a family gets.
create function private.family_limit(h uuid) returns integer language sql stable security definer set search_path='' as $$
 select case when private.household_plus(h) then 8 else 4 end;
$$;
create function private.option_limit(h uuid) returns integer language sql stable security definer set search_path='' as $$
 select case when private.household_plus(h) then 10 else 5 end;
$$;
revoke all on function private.family_limit(uuid),private.option_limit(uuid) from public,anon,authenticated;

create or replace function public.accept_invite(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare invite public.household_invites;begin
 if auth.uid() is null or length(p_token)<>64 then raise exception 'Invalid invite';end if;
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 select * into invite from public.household_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and used_at is null and expires_at>now() for update;
 if not found then raise exception 'Invalid invite';end if;
 if exists(select 1 from public.household_members where household_id=invite.household_id and user_id=auth.uid()) then raise exception 'Already a member';end if;
 if (select count(*) from public.household_members where user_id=auth.uid())>=5 then raise exception 'Family limit reached';end if;
 perform 1 from public.households where id=invite.household_id for update;
 if (select count(*) from public.household_members where household_id=invite.household_id)>=private.family_limit(invite.household_id) then
  raise exception 'Family is full';end if;
 insert into public.household_members(household_id,user_id,role) values(invite.household_id,auth.uid(),'parent');
 update public.household_invites set used_at=now() where id=invite.id;
 return invite.household_id;
end $$;

create or replace function private.goal_option_before() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  perform 1 from public.goals where id=new.goal_id for update;
  if (select count(*) from public.goal_options where goal_id=new.goal_id)>=private.option_limit(new.household_id) then
   raise exception 'Too many options';end if;
 elsif old.price_cents is not null and new.price_cents is not null
  and (new.price_cents<>old.price_cents or new.list_price_cents is distinct from old.list_price_cents) then
  new.previous_price_cents:=old.price_cents;
  new.previous_list_price_cents:=old.list_price_cents;
  new.price_changed_at:=now();
 end if;
 return new;
end $$;

-- The baby shower, for the countdown on the page, and three more palettes.
alter table public.gift_lists add column event_date date;
alter table public.gift_lists drop constraint gift_lists_palette_check;
alter table public.gift_lists add constraint gift_lists_palette_check
 check(palette in ('pessego','menta','ceu','lavanda','areia','rosa','oliva','mar'));
grant insert(event_date),update(event_date) on public.gift_lists to authenticated;

create or replace function public.gift_page(p_slug text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare l public.gift_lists;begin
 select * into l from public.gift_lists where slug=lower(p_slug) and published;
 if not found or not private.household_plus(l.household_id) then return null;end if;
 return jsonb_build_object(
  'title',l.title,'message',l.message,'template',l.template,'palette',l.palette,'event_date',l.event_date,
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
commit;
