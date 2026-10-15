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
 -- Like Supabase, new objects in public start with ALL granted to the API roles; the migrations must narrow it.
 alter default privileges in schema public grant all on tables to anon,authenticated;
 alter default privileges in schema public grant all on functions to anon,authenticated;
 alter default privileges in schema public grant all on sequences to anon,authenticated;
`);
const migrations=new URL('../migrations/',import.meta.url);
for(const file of (await fs.readdir(migrations)).filter(f=>f.endsWith('.sql')).sort()) await db.exec(await fs.readFile(new URL(file,migrations),'utf8'));
const a='11111111-1111-4111-8111-111111111111', b='22222222-2222-4222-8222-222222222222';
const c='33333333-3333-4333-8333-333333333333', d='44444444-4444-4444-8444-444444444444';
await db.query('insert into auth.users values ($1),($2),($3),($4)',[a,b,c,d]);
async function user(id){await db.exec('reset role; set role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);}
async function q(sql,args=[]){return (await db.query(sql,args)).rows;}
async function denied(sql,args=[],why){await assert.rejects(()=>db.query(sql,args),why);}
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
// Review fixes: deletions unlink health records, column allowlist, invite edge cases, leftover Supabase privileges.
await user(a);
const vaccine=(await q("insert into public.health_events(household_id,baby_id,title,event_type,event_date) values($1,$2,'Vacina','vaccine',current_date) returning id",[h,baby]))[0].id;
const cost=(await q('select public.record_health_cost($1,9000,current_date) as id',[vaccine]))[0].id;
await denied('update public.health_events set expense_entry_id=null where id=$1',[vaccine],/permission denied/);
await q("update public.entries set title='Vacina da farmácia' where id=$1",[cost]);
const second=(await q("select public.create_household('Família A2') as id"))[0].id;
const loose=(await q("insert into public.entries(household_id,title,kind,amount_cents,start_date) values($1,'Avulsa','expense',100,current_date) returning id",[h]))[0].id;
await denied('update public.entries set household_id=$1 where id=$2',[second,loose],/permission denied/);
await denied("insert into public.entries(id,household_id,title,kind,amount_cents,start_date) values(gen_random_uuid(),$1,'Id próprio','expense',100,current_date)",[h],/permission denied/);
await q('delete from public.entries where id=$1',[cost]);
assert.equal((await q('select expense_entry_id from public.health_events where id=$1',[vaccine]))[0].expense_entry_id,null);
await q('delete from public.babies where id=$1',[baby]);
assert.equal((await q('select baby_id from public.health_events where id=$1',[vaccine]))[0].baby_id,null);
const invite=(await q('select public.create_invite($1) as token',[h]))[0].token;
await denied('select public.accept_invite($1)',[invite],/Already a member/);
await user(c);
for(let i=1;i<=5;i++) await q('select public.create_household($1)',['Família C'+i]);
await denied('select public.accept_invite($1)',[invite],/Family limit reached/);
await user(d);
assert.equal((await q('select public.accept_invite($1) as id',[invite]))[0].id,h);
await denied('truncate public.debts',[],/permission denied/);
await db.exec('reset role');
const leftovers=await q(`select c.relname as name from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'
 and (select bool_or(has_table_privilege(r,c.oid,p)) from unnest('{anon,authenticated}'::name[]) r,unnest('{truncate,references,trigger}'::text[]) p)
 union all select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('anon',p.oid,'execute')`);
assert.deepEqual(leftovers,[]);
await q('delete from public.households where id=$1',[h]);
assert.equal((await q('select count(*)::int as n from public.health_events where household_id=$1',[h]))[0].n,0);
const tables=await q("select relname,relrowsecurity from pg_class join pg_namespace on pg_namespace.oid=relnamespace where nspname='public' and relkind='r'");
assert.ok(tables.length>=10);assert.ok(tables.every(t=>t.relrowsecurity));
await db.close();
console.log('PASS: schema, tenant isolation, composite foreign keys, protected fields and columns, invitation lifecycle and limits, recurring settlement boundaries, atomic purchases, health-cost deduplication, unlinking on delete, Supabase default privileges.');
