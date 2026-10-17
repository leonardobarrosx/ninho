-- Account deletion. The API deletes the user with the Auth admin API (DELETE /v1/account); this trigger decides,
-- in the same transaction, what happens to the families the user created. households.owner_id keeps its
-- default NO ACTION: if this trigger is missing, deleting an owner fails instead of erasing a shared family.
begin;
create function private.before_user_deleted() returns trigger language plpgsql security definer set search_path='' as $$
declare h uuid;heir uuid;begin
 for h in select id from public.households where owner_id=old.id for update loop
  select m.user_id into heir from public.household_members m
   where m.household_id=h and m.user_id<>old.id order by m.joined_at,m.user_id limit 1;
  if heir is null then
   -- Nobody else is in the family: it goes, with everything recorded in it.
   delete from public.households where id=h;
  else
   -- The family stays with its people, and whoever joined first takes it over. Codes the old owner
   -- handed out stop working, as when a member is removed.
   update public.households set owner_id=heir where id=h;
   update public.household_members set role='owner' where household_id=h and user_id=heir;
   delete from public.household_invites where household_id=h and used_at is null;
  end if;
 end loop;
 -- The user's memberships go with the auth.users row (on delete cascade).
 return old;
end $$;
revoke all on function private.before_user_deleted() from public,anon,authenticated;
create trigger before_user_deleted before delete on auth.users for each row execute function private.before_user_deleted();
commit;
