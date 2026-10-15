-- Fixes from the 2026-10-14 review. The initial migration may already be applied, so it stays unchanged.
begin;

-- Deleting the linked expense or the baby unlinks the health record instead of failing.
alter table public.health_events
 drop constraint health_events_expense_entry_id_household_id_fkey,
 add constraint health_events_expense_entry_id_household_id_fkey foreign key(expense_entry_id,household_id)
  references public.entries(id,household_id) on delete set null(expense_entry_id),
 drop constraint health_events_baby_id_household_id_fkey,
 add constraint health_events_baby_id_household_id_fkey foreign key(baby_id,household_id)
  references public.babies(id,household_id) on delete set null(baby_id);

-- Using an invite for a family you already belong to no longer burns it, and the five-family limit applies here too.
create or replace function public.accept_invite(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare invite public.household_invites;begin
 if auth.uid() is null or length(p_token)<>64 then raise exception 'Invalid invite';end if;
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 select * into invite from public.household_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and used_at is null and expires_at>now() for update;
 if not found then raise exception 'Invalid invite';end if;
 if exists(select 1 from public.household_members where household_id=invite.household_id and user_id=auth.uid()) then raise exception 'Already a member';end if;
 if (select count(*) from public.household_members where user_id=auth.uid())>=5 then raise exception 'Family limit reached';end if;
 perform 1 from public.households where id=invite.household_id for update;
 if (select count(*) from public.household_members where household_id=invite.household_id)>=4 then raise exception 'Family is full';end if;
 insert into public.household_members(household_id,user_id,role) values(invite.household_id,auth.uid(),'parent');
 update public.household_invites set used_at=now() where id=invite.id;
 return invite.household_id;
end $$;

-- Clients can call the Data API directly with the publishable key, so the column allowlist must live in the database.
-- Keep it in sync with `fields` in backend/internal/api/server.go. household_id is insert-only: records never move between families.
revoke insert,update on public.babies,public.entries,public.debts,public.goals,public.measurements,public.health_events from authenticated;
grant insert(household_id,name,due_date,birth_date,notes),update(name,due_date,birth_date,notes) on public.babies to authenticated;
grant insert(household_id,title,kind,category,amount_cents,start_date,end_date,recurrence,notes),
 update(title,kind,category,amount_cents,start_date,end_date,recurrence,notes) on public.entries to authenticated;
grant insert(household_id,title,creditor,balance_cents,installment_cents,due_day,notes),
 update(title,creditor,balance_cents,installment_cents,due_day,notes) on public.debts to authenticated;
grant insert(household_id,title,priority,target_cents,saved_cents,quantity,acquired,target_date,notes),
 update(title,priority,target_cents,saved_cents,quantity,acquired,target_date,notes) on public.goals to authenticated;
grant insert(household_id,baby_id,measured_at,weight_grams,length_mm,notes),update(baby_id,measured_at,weight_grams,length_mm,notes) on public.measurements to authenticated;
-- expense_entry_id is written only by record_health_cost, which is what keeps a cost from being recorded twice.
grant insert(household_id,baby_id,title,event_type,event_date,provider,notes,completed),
 update(baby_id,title,event_type,event_date,provider,notes,completed) on public.health_events to authenticated;

-- Supabase default privileges grant ALL on new public objects to anon and authenticated. TRUNCATE bypasses RLS,
-- and the initial "revoke ... from public" left anon's explicit EXECUTE on the functions in place.
revoke truncate,references,trigger on all tables in schema public from anon,authenticated;
revoke execute on all functions in schema public from anon;
alter default privileges in schema public revoke truncate,references,trigger on tables from anon,authenticated;
alter default privileges in schema public revoke execute on functions from anon;
commit;
