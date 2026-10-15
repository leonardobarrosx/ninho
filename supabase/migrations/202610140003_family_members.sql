-- Family members: members see who else is in the family, the owner removes people and the others can leave.
begin;
create function public.list_members(p_household_id uuid) returns table(user_id uuid,email text,role text,joined_at timestamptz)
language sql stable security definer set search_path='' as $$
 select m.user_id,u.email::text,m.role,m.joined_at from public.household_members m join auth.users u on u.id=m.user_id
 where m.household_id=p_household_id and private.is_member(p_household_id) order by m.joined_at,m.user_id;
$$;
create function public.remove_member(p_household_id uuid,p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.households where id=p_household_id and owner_id=auth.uid() for update;
 if not found then raise exception 'Only the owner can remove members';end if;
 if p_user_id=auth.uid() then raise exception 'Owner cannot leave';end if;
 delete from public.household_members where household_id=p_household_id and user_id=p_user_id;
 if not found then raise exception 'Not a member';end if;
 -- A leaked code could bring the removed person back, so pending invites stop working.
 delete from public.household_invites where household_id=p_household_id and used_at is null;
end $$;
create function public.leave_household(p_household_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.households where id=p_household_id for update;
 if exists(select 1 from public.households where id=p_household_id and owner_id=auth.uid()) then raise exception 'Owner cannot leave';end if;
 delete from public.household_members where household_id=p_household_id and user_id=auth.uid();
 if not found then raise exception 'Not a member';end if;
end $$;
revoke all on function public.list_members(uuid),public.remove_member(uuid,uuid),public.leave_household(uuid) from public,anon;
grant execute on function public.list_members(uuid),public.remove_member(uuid,uuid),public.leave_household(uuid) to authenticated;
commit;
