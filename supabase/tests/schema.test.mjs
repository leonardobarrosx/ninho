import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

// Disposable PostgreSQL/WASM database. No connection to a real Supabase project.
const db = new PGlite({ extensions: { pgcrypto } });
await db.exec(`
 create role anon; create role authenticated;
 create schema auth;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as
 $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema public,auth to authenticated,anon;
 grant execute on function auth.uid() to authenticated,anon;
`);
await db.exec(await fs.readFile(new URL('../migrations/202610140001_initial.sql',import.meta.url),'utf8'));
const a='11111111-1111-4111-8111-111111111111', b='22222222-2222-4222-8222-222222222222';
await db.query('insert into auth.users values ($1),($2)',[a,b]);
async function user(id){await db.exec('reset role; set role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);}
async function q(sql,args=[]){return (await db.query(sql,args)).rows;}
async function denied(sql,args=[]){await assert.rejects(()=>db.query(sql,args));}
await user(a);
const h=(await q("select public.create_household('Família A') as id"))[0].id;
const baby=(await q("insert into public.babies(household_id,name) values($1,'Bebê A') returning id",[h]))[0].id;
const entry=(await q("insert into public.entries(household_id,title,kind,amount_cents,start_date,recurrence) values($1,'Conta','expense',12345,'2026-10-31','monthly') returning id",[h]))[0].id;
await denied("update public.households set plan='plus' where id=$1",[h]);
await denied("insert into public.household_members(household_id,user_id,role) values($1,$2,'owner')",[h,b]);
await user(b);
assert.equal((await q('select * from public.entries')).length,0);
assert.equal((await q('select * from public.households')).length,0);
await denied("insert into public.goals(household_id,title) values($1,'Inválido')",[h]);
await denied('select public.settle_entry($1,$2,true)',[entry,'2026-10-31']);
const other=(await q("select public.create_household('Família B') as id"))[0].id;
await denied("insert into public.measurements(household_id,baby_id,measured_at,weight_grams) values($1,$2,current_date,3000)",[other,baby]);
await user(a);
await denied('select public.settle_entry($1,$2,true)',[entry,'2027-02-27']);
await q('select public.settle_entry($1,$2,true)',[entry,'2027-02-28']);
await q('select public.settle_entry($1,$2,true)',[entry,'2027-02-28']);
assert.equal((await q('select * from public.settlements')).length,1);
await denied('update public.entries set amount_cents=9000 where id=$1',[entry]);
await denied("update public.entries set end_date='2026-12-31' where id=$1",[entry]);
await q('select public.settle_entry($1,$2,false)',[entry,'2027-02-28']);
assert.equal((await q('select * from public.settlements')).length,0);
const goal=(await q("insert into public.goals(household_id,title,quantity,saved_cents,target_cents) values($1,'Berço',1,50000,80000) returning id",[h]))[0].id;
await q('select public.buy_goal($1,1,80000,current_date)',[goal]);
let goals=await q('select * from public.goals where id=$1',[goal]);
assert.equal(goals[0].acquired,1);assert.equal(Number(goals[0].saved_cents),0);
assert.equal((await q("select * from public.entries where category='Enxoval'")).length,1);
await denied('select public.buy_goal($1,1,80000,current_date)',[goal]);
assert.equal((await q("select * from public.entries where category='Enxoval'")).length,1);
const health=(await q("insert into public.health_events(household_id,title,event_type,event_date) values($1,'Exame','exam',current_date) returning id",[h]))[0].id;
await q('select public.record_health_cost($1,25000,current_date)',[health]);
await denied('select public.record_health_cost($1,25000,current_date)',[health]);
assert.equal((await q("select * from public.entries where category='Saúde'")).length,1);
await denied("insert into public.entries(household_id,title,kind,amount_cents,start_date) values($1,'Zero','expense',0,current_date)",[h]);
const token=(await q('select public.create_invite($1) as token',[h]))[0].token;
await user(b);
await q('select public.accept_invite($1)',[token]);
assert.ok((await q('select * from public.entries')).length>0);
await denied('select public.accept_invite($1)',[token]);
await denied('select public.create_invite($1)',[h]);
await db.exec('reset role');
const tables=await q("select relname,relrowsecurity from pg_class join pg_namespace on pg_namespace.oid=relnamespace where nspname='public' and relkind='r'");
assert.ok(tables.length>=10);assert.ok(tables.every(t=>t.relrowsecurity));
await db.close();
console.log('PASS: schema, tenant isolation, composite foreign keys, protected fields, invitation lifecycle, recurring settlement boundaries, atomic purchases, health-cost deduplication.');
