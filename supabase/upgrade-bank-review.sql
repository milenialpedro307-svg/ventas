-- Financed: revisión pendiente, sin retiros ni envío de documentos.
-- Ejecutar después de instalar upgrade-contacts.sql.
begin;
alter table financed_private.profiles add column if not exists bank_review_requested_at timestamptz;
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
commit;
