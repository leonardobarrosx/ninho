-- Plus bought through Mercado Pago. The API opens a Checkout Pro payment for the signed-in account, then learns
-- what happened to it from Mercado Pago's webhook and from the page the buyer returns to. Either way the API reads
-- the payment back from Mercado Pago with its own token before recording it here, so a forged notice cannot grant
-- Plus. An approved payment grants Plus to the account; a refund or a chargeback of that payment takes it back.
begin;

-- Every payment Mercado Pago reported for Plus, kept when the account is deleted for the money records.
create table public.plus_payments (
 id text primary key check(id ~ '^[0-9]{1,30}$'),
 user_id uuid references auth.users(id) on delete set null,
 status text not null check(char_length(status) between 1 and 40),
 amount_cents bigint not null check(amount_cents between 0 and 100000000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index plus_payments_user_idx on public.plus_payments(user_id);
alter table public.plus_payments enable row level security;
revoke all on public.plus_payments from anon,authenticated;

-- Records the state of a payment and grants or takes back Plus. p_paid is whether the API found the payment
-- approved for the full price. Returns whether the account has Plus now. Called by the API with the secret key.
create function public.record_plus_payment(p_payment_id text,p_user_id uuid,p_status text,p_amount_cents bigint,
 p_paid boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare owner uuid;src text:='mercadopago:'||p_payment_id;begin
 if not exists(select 1 from auth.users where id=p_user_id) then p_user_id:=null;end if;
 select user_id into owner from public.plus_payments where id=p_payment_id for update;
 if found and owner is distinct from p_user_id and owner is not null then raise exception 'Payment mismatch';end if;
 insert into public.plus_payments(id,user_id,status,amount_cents) values(p_payment_id,p_user_id,p_status,p_amount_cents)
  on conflict(id) do update set user_id=excluded.user_id,status=excluded.status,amount_cents=excluded.amount_cents,
  updated_at=now();
 if p_user_id is null then return false;end if;
 if p_paid then
  insert into public.plus_accounts(user_id,source) values(p_user_id,src) on conflict(user_id) do nothing;
 elsif p_status in ('refunded','charged_back','cancelled','rejected') then
  delete from public.plus_accounts where user_id=p_user_id and source=src;
 end if;
 return exists(select 1 from public.plus_accounts where user_id=p_user_id);
end $$;
revoke all on function public.record_plus_payment(text,uuid,text,bigint,boolean) from public,anon,authenticated;
commit;
