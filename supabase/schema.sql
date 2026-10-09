-- Financed v3. Se puede ejecutar en un proyecto nuevo o con la versión anterior.
-- No elimina las tablas anteriores. No almacena imágenes ni documentos.
begin;
create schema if not exists financed_private;
revoke all on schema financed_private from public,anon,authenticated;
create table if not exists financed_private.profiles(
 id uuid primary key references auth.users(id), username text unique not null check(username ~ '^[a-z0-9_]{3,20}$'),
 name text not null, balance bigint not null default 0 check(balance between 0 and 9000000000000),
 created_at timestamptz not null default now()
);
alter table financed_private.profiles alter column balance set default 0;
alter table financed_private.profiles add column if not exists bank_review_requested_at timestamptz;
create table if not exists financed_private.contacts(
 owner_id uuid not null references financed_private.profiles(id), contact_id uuid not null references financed_private.profiles(id),
 created_at timestamptz not null default now(),primary key(owner_id,contact_id),check(owner_id<>contact_id)
);
create table if not exists financed_private.bank_destinations(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references financed_private.profiles(id),
 bank text not null check(length(bank) between 1 and 40),account_type text not null check(length(account_type) between 1 and 40),
 account_number text not null check(account_number ~ '^[0-9]{4,20}$'),created_at timestamptz not null default now(),
 unique(owner_id,bank,account_type,account_number)
);
create table if not exists financed_private.ledger(
 id uuid primary key,from_id uuid not null references financed_private.profiles(id),to_id uuid references financed_private.profiles(id),
 amount bigint not null check(amount between 1 and 100000000),concept text not null check(length(concept) between 1 and 80),
 from_name text not null,to_name text not null,bank_destination uuid references financed_private.bank_destinations(id),
 created_at timestamptz not null default now(),check(from_id is distinct from to_id)
);
create index if not exists financed_ledger_sender on financed_private.ledger(from_id,created_at desc);
create index if not exists financed_ledger_recipient on financed_private.ledger(to_id,created_at desc);
alter table financed_private.profiles enable row level security;
alter table financed_private.contacts enable row level security;
alter table financed_private.bank_destinations enable row level security;
alter table financed_private.ledger enable row level security;
revoke all on all tables in schema financed_private from public,anon,authenticated;
create or replace function financed_private.require_user() returns uuid language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Inicia sesión en Financed'; end if;
 return auth.uid();
end $$;
revoke all on function financed_private.require_user() from public,anon,authenticated;
create or replace function public.fn_open(p_username text) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();uname text;full_name text;
begin
 if exists(select 1 from financed_private.profiles where id=uid) then return uid; end if;
 uname:=lower(trim(p_username));
 if uname is null or uname !~ '^[a-z0-9_]{3,20}$' then raise exception 'Elige un usuario de 3–20 letras, números o guion bajo'; end if;
 select coalesce(nullif(trim(raw_user_meta_data->>'full_name'),''),'Usuario') into full_name from auth.users where id=uid;
 -- Todas las cuentas nuevas comienzan en cero, incluidos los usuarios de versiones anteriores.
 insert into financed_private.profiles(id,username,name,balance) values(uid,uname,left(full_name,80),0);
 return uid;
exception when unique_violation then
 if exists(select 1 from financed_private.profiles where id=uid) then return uid; end if;
 raise exception 'Ese nombre de usuario ya está ocupado';
end $$;
create or replace function public.fn_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();
begin
 return jsonb_build_object(
 'account',(select to_jsonb(p) from financed_private.profiles p where id=uid),
 'contacts',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'name',p.name) order by p.username) from financed_private.contacts c join financed_private.profiles p on p.id=c.contact_id where c.owner_id=uid),'[]'::jsonb),
 'destinations',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from financed_private.bank_destinations d where owner_id=uid),'[]'::jsonb),
 'transactions',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (select * from financed_private.ledger where from_id=uid or to_id=uid order by created_at desc limit 200) t),'[]'::jsonb));
end $$;
create or replace function public.fn_search(p_username text) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();u text:=lower(trim(p_username));
begin
 if not exists(select 1 from financed_private.profiles where id=uid) then raise exception 'Completa tu perfil'; end if;
 if u is null or u !~ '^[a-z0-9_]{3,20}$' then raise exception 'Nombre de usuario inválido'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'username',username,'name',name)) from financed_private.profiles where username=u and id<>uid),'[]'::jsonb);
end $$;
create or replace function public.fn_add_contact(p_contact uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();
begin
 if uid=p_contact or not exists(select 1 from financed_private.profiles where id=p_contact) then raise exception 'Contacto inválido'; end if;
 if not exists(select 1 from financed_private.profiles where id=uid) then raise exception 'Completa tu perfil'; end if;
 insert into financed_private.contacts(owner_id,contact_id) values(uid,p_contact) on conflict do nothing;
 return true;
end $$;
create or replace function public.fn_transfer(p_to uuid,p_amount bigint,p_concept text,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();sender financed_private.profiles;receiver financed_private.profiles;prior financed_private.ledger;
begin
 if p_key is null or p_amount is null or p_amount not between 1 and 100000000 or p_concept is null or length(trim(p_concept)) not between 1 and 80 then raise exception 'Transferencia inválida'; end if;
 if p_to is null or uid=p_to or not exists(select 1 from financed_private.contacts where owner_id=uid and contact_id=p_to) then raise exception 'Agrega ese usuario a tus contactos'; end if;
 -- Orden de bloqueos estable para transferencias simultáneas en ambos sentidos.
 perform id from financed_private.profiles where id in (uid,p_to) order by id for update;
 select * into prior from financed_private.ledger where id=p_key;
 if found then
  if prior.from_id<>uid or prior.to_id is distinct from p_to or prior.amount<>p_amount or prior.concept<>trim(p_concept) then raise exception 'Identificador de operación ya utilizado'; end if;
  return p_key;
 end if;
 select * into sender from financed_private.profiles where id=uid;
 select * into receiver from financed_private.profiles where id=p_to;
 if sender.id is null or receiver.id is null then raise exception 'Cuenta inválida'; end if;
 if sender.balance<p_amount then raise exception 'Saldo insuficiente'; end if;
 update financed_private.profiles set balance=balance-p_amount where id=uid;
 update financed_private.profiles set balance=balance+p_amount where id=p_to;
 insert into financed_private.ledger(id,from_id,to_id,amount,concept,from_name,to_name) values(p_key,uid,p_to,p_amount,trim(p_concept),sender.name,receiver.name);
 return p_key;
end $$;
create or replace function public.fn_save_bank(p_bank text,p_type text,p_number text) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();did uuid;
begin
 if p_bank is null or length(trim(p_bank)) not between 1 and 40 or p_type is null or length(trim(p_type)) not between 1 and 40 or p_number is null or p_number !~ '^[0-9]{4,20}$' then raise exception 'Datos de cuenta inválidos'; end if;
 if not exists(select 1 from financed_private.profiles where id=uid) then raise exception 'Completa tu perfil'; end if;
 insert into financed_private.bank_destinations(owner_id,bank,account_type,account_number) values(uid,trim(p_bank),trim(p_type),p_number) on conflict(owner_id,bank,account_type,account_number) do update set bank=excluded.bank returning id into did;
 return did;
end $$;
-- La solicitud solo marca una revisión pendiente: no transfiere ni descuenta fondos.
create or replace function public.fn_request_bank_review(p_destination uuid,p_amount bigint) returns timestamptz language plpgsql security definer set search_path='' as $$
declare uid uuid:=financed_private.require_user();requested timestamptz;
begin
 if p_amount is null or p_amount not between 1 and 100000000 then raise exception 'Monto inválido'; end if;
 if not exists(select 1 from financed_private.bank_destinations where id=p_destination and owner_id=uid) then raise exception 'La cuenta de destino no te pertenece'; end if;
 perform 1 from financed_private.profiles where id=uid for update;
 if not found then raise exception 'Completa tu perfil'; end if;
 if (select balance from financed_private.profiles where id=uid)<p_amount then raise exception 'Saldo insuficiente'; end if;
 update financed_private.profiles set bank_review_requested_at=coalesce(bank_review_requested_at,now()) where id=uid returning bank_review_requested_at into requested;
 return requested;
end $$;
-- También bloquea clientes anteriores y llamadas directas al RPC de retiro.
create or replace function public.fn_bank_transfer(p_destination uuid,p_amount bigint,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
begin
 perform financed_private.require_user();
 raise exception 'Los retiros de esta cuenta están bloqueados.';
end $$;
revoke all on function public.fn_request_bank_review(uuid,bigint) from public,anon;
grant execute on function public.fn_request_bank_review(uuid,bigint) to authenticated;
revoke all on function public.fn_open(text),public.fn_state(),public.fn_search(text),public.fn_add_contact(uuid),public.fn_transfer(uuid,bigint,text,uuid),public.fn_save_bank(text,text,text),public.fn_bank_transfer(uuid,bigint,uuid) from public,anon;
grant execute on function public.fn_open(text),public.fn_state(),public.fn_search(text),public.fn_add_contact(uuid),public.fn_transfer(uuid,bigint,text,uuid),public.fn_save_bank(text,text,text),public.fn_bank_transfer(uuid,bigint,uuid) to authenticated;
commit;
