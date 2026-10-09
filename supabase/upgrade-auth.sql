-- Financed: actualización para instalaciones anteriores. Preserva cuentas y movimientos.
begin;
create or replace function public.mb_ping() returns boolean language sql security invoker set search_path='' as $$select auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)$$;
create or replace function public.mb_create(p_name text,p_player text,p_initial bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare gid uuid; c text;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Inicia sesión con correo y contraseña'; end if;
 if length(trim(p_name)) not between 1 and 50 or length(trim(p_player)) not between 1 and 24 or p_initial not between 1 and 1000000 then raise exception 'Datos de cuenta inválidos'; end if;
 -- 32 random bits; retry an unlikely code collision.
 loop
  c:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  begin
   insert into monopoly_private.games(code,name,host_id,initial_balance) values(c,trim(p_name),auth.uid(),p_initial) returning id into gid;
   exit;
  exception when unique_violation then null;
  end;
 end loop;
 insert into monopoly_private.players(id,game_id,name,balance) values(auth.uid(),gid,trim(p_player),p_initial);
 return gid;
end $$;
create or replace function public.mb_join(p_code text,p_player text) returns uuid
language plpgsql security definer set search_path='' as $$
declare g monopoly_private.games; n integer;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Inicia sesión con correo y contraseña'; end if;
 if length(trim(p_player)) not between 1 and 24 then raise exception 'Nombre inválido'; end if;
 select * into g from monopoly_private.games where code=upper(trim(p_code)) for update;
 if not found then raise exception 'No existe un espacio con ese código'; end if;
 if exists(select 1 from monopoly_private.players where game_id=g.id and id=auth.uid()) then return g.id; end if;
 select count(*) into n from monopoly_private.players where game_id=g.id;
 if n>=8 then raise exception 'Este espacio ya tiene 8 titulares'; end if;
 if exists(select 1 from monopoly_private.players where game_id=g.id and name=trim(p_player)) then raise exception 'Ya hay un titular con ese nombre'; end if;
 insert into monopoly_private.players(id,game_id,name,balance) values(auth.uid(),g.id,trim(p_player),g.initial_balance);
 return g.id;
end $$;
create or replace function public.mb_state(p_game uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or not exists(select 1 from monopoly_private.players where game_id=p_game and id=auth.uid()) then raise exception 'No tienes acceso a esta cuenta'; end if;
 return jsonb_build_object(
 'game',(select to_jsonb(g) from monopoly_private.games g where id=p_game),
 'me',auth.uid(),
 'players',coalesce((select jsonb_agg(to_jsonb(p) order by p.joined_at) from monopoly_private.players p where game_id=p_game),'[]'::jsonb),
 'transactions',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (select * from monopoly_private.transactions where game_id=p_game order by created_at desc limit 200) t),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from monopoly_private.go_requests r where game_id=p_game and status='pending'),'[]'::jsonb));
end $$;
create or replace function public.mb_transfer(p_game uuid,p_from uuid,p_to uuid,p_amount bigint,p_concept text,p_key uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g monopoly_private.games; old monopoly_private.transactions; bal bigint;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Inicia sesión con correo y contraseña'; end if;
 if p_amount is null or p_amount not between 1 and 100000000 or p_key is null or p_concept is null or length(trim(p_concept)) not between 1 and 80 or p_from is not distinct from p_to then raise exception 'Transferencia inválida'; end if;
 -- Serializing on the game row makes balance changes and idempotency atomic.
 select * into g from monopoly_private.games where id=p_game for update;
 if not found or not exists(select 1 from monopoly_private.players where game_id=p_game and id=auth.uid()) then raise exception 'No tienes acceso a esta cuenta'; end if;
 if p_from is null and auth.uid()<>g.host_id then raise exception 'Solo el administrador puede emitir dinero'; end if;
 if p_from is not null and p_from<>auth.uid() and not (auth.uid()=g.host_id and p_to is null) then raise exception 'Solo puedes transferir desde tu cuenta'; end if;
 select * into old from monopoly_private.transactions where id=p_key;
 if found then
  if old.game_id<>p_game or old.actor_id<>auth.uid() or old.from_id is distinct from p_from or old.to_id is distinct from p_to or old.amount<>p_amount or old.concept<>trim(p_concept) then raise exception 'Identificador de operación ya utilizado'; end if;
  return old.id;
 end if;
 if p_to is not null and not exists(select 1 from monopoly_private.players where game_id=p_game and id=p_to) then raise exception 'Destinatario inválido'; end if;
 if p_from is not null then
  select balance into bal from monopoly_private.players where game_id=p_game and id=p_from;
  if not found then raise exception 'Cuenta de origen inválida'; end if;
  if bal<p_amount then raise exception 'Saldo insuficiente'; end if;
  update monopoly_private.players set balance=balance-p_amount where game_id=p_game and id=p_from;
 end if;
 if p_to is not null then update monopoly_private.players set balance=balance+p_amount where game_id=p_game and id=p_to; end if;
 insert into monopoly_private.transactions(id,game_id,from_id,to_id,amount,concept,actor_id) values(p_key,p_game,p_from,p_to,p_amount,trim(p_concept),auth.uid());
 return p_key;
end $$;
create or replace function public.mb_request_go(p_game uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or not exists(select 1 from monopoly_private.players where game_id=p_game and id=auth.uid()) then raise exception 'No tienes acceso a esta cuenta'; end if;
 insert into monopoly_private.go_requests(game_id,player_id) values(p_game,auth.uid()) returning id into rid;
 return rid;
exception when unique_violation then raise exception 'Ya tienes una solicitud pendiente';
end $$;
create or replace function public.mb_approve(p_request uuid,p_approve boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare r monopoly_private.go_requests; g monopoly_private.games;
begin
 select * into r from monopoly_private.go_requests where id=p_request;
 if not found then raise exception 'Solicitud inexistente'; end if;
 select * into g from monopoly_private.games where id=r.game_id for update;
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or auth.uid()<>g.host_id then raise exception 'Solo el administrador puede aprobar solicitudes'; end if;
 select * into r from monopoly_private.go_requests where id=p_request for update;
 if r.status<>'pending' then return r.status='approved'; end if;
 if p_approve is null then raise exception 'Decisión inválida'; end if;
 if p_approve then
  perform public.mb_transfer(r.game_id,null,r.player_id,200,'Abono de cuenta',r.id);
 end if;
 update monopoly_private.go_requests set status=case when p_approve then 'approved' else 'rejected' end where id=p_request;
 return p_approve;
end $$;
revoke all on function public.mb_ping() from public,anon;
revoke all on function public.mb_create(text,text,bigint) from public,anon;
revoke all on function public.mb_join(text,text) from public,anon;
revoke all on function public.mb_state(uuid) from public,anon;
revoke all on function public.mb_transfer(uuid,uuid,uuid,bigint,text,uuid) from public,anon;
revoke all on function public.mb_request_go(uuid) from public,anon;
revoke all on function public.mb_approve(uuid,boolean) from public,anon;
grant execute on function public.mb_ping(),public.mb_create(text,text,bigint),public.mb_join(text,text),public.mb_state(uuid),public.mb_transfer(uuid,uuid,uuid,bigint,text,uuid),public.mb_request_go(uuid),public.mb_approve(uuid,boolean) to authenticated;
create or replace function public.mb_accounts() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Inicia sesión con correo y contraseña'; end if;
 return coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from
  (select g.id,g.code,g.name,g.host_id,g.created_at,p.balance from monopoly_private.games g
   join monopoly_private.players p on p.game_id=g.id where p.id=auth.uid()) a),'[]'::jsonb);
end $$;
revoke all on function public.mb_accounts() from public,anon;
grant execute on function public.mb_accounts() to authenticated;
commit;
