-- Plus bought in the Android app with Google Play Billing. The app sends the purchase token to the API, which reads
-- the purchase from the Google Play Developer API with a service account before recording it here, so the app's
-- word alone never grants Plus. A purchase grants Plus to the account that made it; a refund or a cancellation of
-- that purchase, found in Google's voided purchases once a day, takes it back. Plus is per account, so the web app
-- shows it too.
begin;

-- Every Plus purchase Google Play reported, kept without the account when it is deleted, for the money records.
create table public.plus_purchases (
 purchase_token text primary key check(purchase_token ~ '^[A-Za-z0-9._-]+$' and char_length(purchase_token) between 10 and 1000),
 order_id text not null default '' check(char_length(order_id)<=200),
 product_id text not null check(char_length(product_id) between 1 and 200),
 user_id uuid references auth.users(id) on delete set null,
 state text not null check(state in ('purchased','pending','canceled','voided')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index plus_purchases_user_idx on public.plus_purchases(user_id);
alter table public.plus_purchases enable row level security;
revoke all on public.plus_purchases from anon,authenticated;

-- Records the state of a purchase and grants or takes back Plus. A null p_user_id keeps the purchase's account,
-- as for a voided purchase, and does nothing for a purchase never recorded. Returns whether that account has Plus
-- now. Called by the API with the secret key.
create function public.record_plus_purchase(p_token text,p_order_id text,p_product_id text,p_user_id uuid,
 p_state text) returns boolean language plpgsql security definer set search_path='' as $$
declare owner uuid;src text:='google_play:'||md5(p_token);begin
 if p_user_id is not null and not exists(select 1 from auth.users where id=p_user_id) then
  raise exception 'Unknown account';end if;
 select user_id into owner from public.plus_purchases where purchase_token=p_token for update;
 if not found then
  if p_user_id is null then return false;end if;
  insert into public.plus_purchases(purchase_token,order_id,product_id,user_id,state)
   values(p_token,coalesce(p_order_id,''),p_product_id,p_user_id,p_state);
 else
  if p_user_id is not null and owner is distinct from p_user_id then raise exception 'Purchase mismatch';end if;
  p_user_id:=owner;
  update public.plus_purchases set state=p_state,order_id=coalesce(nullif(p_order_id,''),order_id),updated_at=now()
   where purchase_token=p_token;
 end if;
 if p_user_id is null then return false;end if;
 if p_state='purchased' then
  insert into public.plus_accounts(user_id,source) values(p_user_id,src) on conflict(user_id) do nothing;
 elsif p_state in ('canceled','voided') then
  delete from public.plus_accounts where user_id=p_user_id and source=src;
 end if;
 return exists(select 1 from public.plus_accounts where user_id=p_user_id);
end $$;
revoke all on function public.record_plus_purchase(text,text,text,uuid,text) from public,anon,authenticated;
commit;
