begin;
create schema if not exists extensions;
create schema if not exists private;
grant usage on schema private to authenticated;
create extension if not exists pgcrypto with schema extensions;

create table public.households (
 id uuid primary key default gen_random_uuid(),
 name text not null check(char_length(trim(name)) between 1 and 80),
 owner_id uuid not null default auth.uid() references auth.users(id),
 plan text not null default 'starter' check(plan in ('starter','plus')),
 created_at timestamptz not null default now()
);
create table public.household_members (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in ('owner','parent')),
 joined_at timestamptz not null default now(),unique(household_id,user_id)
);
create index members_user_idx on public.household_members(user_id,household_id);

create function private.is_member(h uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.household_members m where m.household_id=h and m.user_id=(select auth.uid()));
$$;
revoke all on function private.is_member(uuid) from public;
grant execute on function private.is_member(uuid) to authenticated;

create table public.household_invites (
 id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,
 token_hash text not null unique,expires_at timestamptz not null,used_at timestamptz
);
create table public.babies (
 id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 1 and 80),due_date date,birth_date date,
 notes text not null default '' check(char_length(notes)<=2000),created_at timestamptz not null default now(),unique(id,household_id)
);
create table public.entries (
 id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 120),
 kind text not null check(kind in ('income','expense')),
 category text not null default 'Outros' check(char_length(category) between 1 and 60),
 amount_cents bigint not null check(amount_cents between 1 and 99999999999),
 start_date date not null,end_date date,
 recurrence text not null default 'once' check(recurrence in ('once','monthly')),
 notes text not null default '' check(char_length(notes)<=2000),created_at timestamptz not null default now(),
 check(end_date is null or end_date>=start_date),unique(id,household_id)
);
create table public.settlements (
 id uuid primary key default gen_random_uuid(),household_id uuid not null,
 entry_id uuid not null,occurrence date not null,amount_cents bigint not null check(amount_cents>0),
 paid_at timestamptz not null default now(),
 foreign key(entry_id,household_id) references public.entries(id,household_id) on delete cascade,
 unique(entry_id,occurrence)
);
create table public.debts (
 id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 120),creditor text not null default '' check(char_length(creditor)<=120),
 balance_cents bigint not null check(balance_cents between 0 and 99999999999),
 installment_cents bigint not null default 0 check(installment_cents between 0 and 99999999999),
 due_day integer not null default 1 check(due_day between 1 and 31),
 notes text not null default '' check(char_length(notes)<=2000),created_at timestamptz not null default now()
);
create table public.goals (
 id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 120),
 priority text not null default 'essential' check(priority in ('essential','comfort','optional')),
 target_cents bigint not null default 0 check(target_cents between 0 and 99999999999),
 saved_cents bigint not null default 0 check(saved_cents between 0 and 99999999999),
 quantity integer not null default 1 check(quantity between 1 and 10000),
 acquired integer not null default 0 check(acquired>=0 and acquired<=quantity),
 target_date date,notes text not null default '' check(char_length(notes)<=2000),created_at timestamptz not null default now()
);
create table public.measurements (
 id uuid primary key default gen_random_uuid(),household_id uuid not null,baby_id uuid not null,
 measured_at date not null,weight_grams integer check(weight_grams between 1 and 200000),
 length_mm integer check(length_mm between 1 and 2500),notes text not null default '' check(char_length(notes)<=2000),
 created_at timestamptz not null default now(),foreign key(baby_id,household_id) references public.babies(id,household_id) on delete cascade,
 check(weight_grams is not null or length_mm is not null)
);
create table public.health_events (
 id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,baby_id uuid,
 title text not null check(char_length(trim(title)) between 1 and 120),
 event_type text not null check(event_type in ('appointment','exam','medicine','vaccine','other')),
 event_date date not null,provider text not null default '' check(char_length(provider)<=120),
 notes text not null default '' check(char_length(notes)<=2000),completed boolean not null default false,
 expense_entry_id uuid,created_at timestamptz not null default now(),
 foreign key(baby_id,household_id) references public.babies(id,household_id),
 foreign key(expense_entry_id,household_id) references public.entries(id,household_id)
);

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
create policy household_read on public.households for select to authenticated using(private.is_member(id));
create policy household_update on public.households for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy members_read on public.household_members for select to authenticated using(private.is_member(household_id));
-- No client mutation grants/policies on memberships, invites or settlement snapshots.
do $$ declare t text;begin
 foreach t in array array['babies','entries','debts','goals','measurements','health_events'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy tenant_access on public.%I for all to authenticated using(private.is_member(household_id)) with check(private.is_member(household_id))',t);
  execute format('create index %I on public.%I(household_id,id)',t||'_household_idx',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;
alter table public.settlements enable row level security;
create policy settlement_read on public.settlements for select to authenticated using(private.is_member(household_id));
revoke all on public.households from authenticated;
grant select on public.households,public.household_members,public.settlements to authenticated;
grant update(name) on public.households to authenticated;
revoke all on public.household_invites from anon,authenticated;
revoke all on public.household_members,public.settlements from anon;
revoke insert,update,delete on public.household_members,public.settlements from authenticated;
revoke all on public.households,public.babies,public.entries,public.debts,public.goals,public.measurements,public.health_events from anon;

create function public.create_household(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare h uuid;begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 if (select count(*) from public.household_members where user_id=auth.uid())>=5 then raise exception 'Family limit reached';end if;
 insert into public.households(name,owner_id) values(trim(p_name),auth.uid()) returning id into h;
 insert into public.household_members(household_id,user_id,role) values(h,auth.uid(),'owner');
 return h;
end $$;
create function public.create_invite(p_household_id uuid) returns text language plpgsql security definer set search_path='' as $$
declare token text;begin
 if not exists(select 1 from public.households where id=p_household_id and owner_id=auth.uid()) then raise exception 'Owner required';end if;
 delete from public.household_invites where household_id=p_household_id;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.household_invites(household_id,token_hash,expires_at) values(p_household_id,encode(extensions.digest(token,'sha256'),'hex'),now()+interval '72 hours');
 return token;
end $$;
create function public.accept_invite(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare invite public.household_invites;begin
 if auth.uid() is null or length(p_token)<>64 then raise exception 'Invalid invite';end if;
 select * into invite from public.household_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and used_at is null and expires_at>now() for update;
 if not found then raise exception 'Invalid invite';end if;
 perform 1 from public.households where id=invite.household_id for update;
 if (select count(*) from public.household_members where household_id=invite.household_id)>=4 then raise exception 'Family is full';end if;
 insert into public.household_members(household_id,user_id,role) values(invite.household_id,auth.uid(),'parent') on conflict do nothing;
 update public.household_invites set used_at=now() where id=invite.id;
 return invite.household_id;
end $$;
create function public.settle_entry(p_entry_id uuid,p_occurrence date,p_paid boolean) returns void language plpgsql security definer set search_path='' as $$
declare e public.entries;expected date;begin
 select * into e from public.entries where id=p_entry_id for update;
 if not found or not private.is_member(e.household_id) then raise exception 'Entry unavailable';end if;
 if e.recurrence='once' then expected:=e.start_date;else
  expected:=date_trunc('month',p_occurrence)::date+(least(extract(day from e.start_date)::integer,extract(day from (date_trunc('month',p_occurrence)+interval '1 month - 1 day'))::integer)-1);
 end if;
 if p_occurrence is null or p_occurrence<>expected or p_occurrence<e.start_date or (e.end_date is not null and p_occurrence>e.end_date) then raise exception 'Invalid occurrence';end if;
 if p_paid then
  insert into public.settlements(household_id,entry_id,occurrence,amount_cents) values(e.household_id,e.id,p_occurrence,e.amount_cents) on conflict(entry_id,occurrence) do nothing;
 else delete from public.settlements where entry_id=e.id and occurrence=p_occurrence;end if;
end $$;
create function public.buy_goal(p_goal_id uuid,p_quantity integer,p_cost_cents bigint,p_date date) returns uuid language plpgsql security definer set search_path='' as $$
declare g public.goals;entry uuid;begin
 select * into g from public.goals where id=p_goal_id for update;
 if not found or not private.is_member(g.household_id) then raise exception 'Goal unavailable';end if;
 if p_quantity is null or p_quantity<1 or p_quantity+g.acquired>g.quantity or p_cost_cents is null or p_cost_cents<0 or p_date is null then raise exception 'Invalid purchase';end if;
 if p_cost_cents>0 then
  insert into public.entries(household_id,title,kind,category,amount_cents,start_date) values(g.household_id,g.title,'expense','Enxoval',p_cost_cents,p_date) returning id into entry;
  insert into public.settlements(household_id,entry_id,occurrence,amount_cents) values(g.household_id,entry,p_date,p_cost_cents);
 end if;
 update public.goals set acquired=acquired+p_quantity,saved_cents=greatest(0,saved_cents-p_cost_cents) where id=g.id;
 return entry;
end $$;
create function public.record_health_cost(p_event_id uuid,p_amount_cents bigint,p_date date) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.health_events;entry uuid;begin
 select * into e from public.health_events where id=p_event_id for update;
 if not found or not private.is_member(e.household_id) then raise exception 'Event unavailable';end if;
 if e.expense_entry_id is not null then raise exception 'Expense already recorded';end if;
 if p_date is null then raise exception 'Date required';end if;
 insert into public.entries(household_id,title,kind,category,amount_cents,start_date) values(e.household_id,e.title,'expense','Saúde',p_amount_cents,p_date) returning id into entry;
 insert into public.settlements(household_id,entry_id,occurrence,amount_cents) values(e.household_id,entry,p_date,p_amount_cents);
 update public.health_events set expense_entry_id=entry where id=e.id;return entry;
end $$;
revoke all on function public.create_household(text),public.create_invite(uuid),public.accept_invite(text),public.settle_entry(uuid,date,boolean),public.buy_goal(uuid,integer,bigint,date),public.record_health_cost(uuid,bigint,date) from public;
grant execute on function public.create_household(text),public.create_invite(uuid),public.accept_invite(text),public.settle_entry(uuid,date,boolean),public.buy_goal(uuid,integer,bigint,date),public.record_health_cost(uuid,bigint,date) to authenticated;

-- Preserve paid history when an editable recurring rule is changed.
create function public.preserve_paid_history() returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.settlements where entry_id=old.id) then
  if new.start_date<>old.start_date or new.recurrence<>old.recurrence or new.kind<>old.kind or new.amount_cents<>old.amount_cents then
   raise exception 'Close this schedule and create a new entry to preserve paid history';
  end if;
  if new.end_date is not null and exists(select 1 from public.settlements where entry_id=old.id and occurrence>new.end_date) then
   raise exception 'End date cannot remove paid occurrences';
  end if;
 end if;
 return new;
end $$;
revoke all on function public.preserve_paid_history() from public;
create trigger preserve_paid_history before update on public.entries for each row execute function public.preserve_paid_history();
commit;
