-- =====================================================================
-- Pruebas: con la caja cerrada, estado_caja() propone el efectivo que quedó al cerrar el último turno. Negocio nuevo (F).
-- =====================================================================
reset role;
insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('d0000000-0000-4000-8000-0000000000f5', 'authenticated', 'authenticated', 'local.f@prueba.test', now(), now()),
  ('d0000000-0000-4000-8000-0000000000f6', 'authenticated', 'authenticated', 'dueno.f@prueba.test', now(), now());
select set_config('prueba.neg_f', public.admin_alta_negocio('Prueba F', 'dueno.f@prueba.test', 'local.f@prueba.test', 'Fede', '7777')::text, false);
select set_config('prueba.fede', (select id from public.usuarios where nombre = 'Fede' and negocio_id = current_setting('prueba.neg_f')::uuid)::text, false);
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000f5');
select set_config('prueba.t_fede', public.iniciar_usuario(current_setting('prueba.fede')::bigint, '7777') ->> 'token', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000f5', current_setting('prueba.t_fede'));

\echo == Sin turnos anteriores no propone nada
select pruebas.ok(public.estado_caja() -> 'turno' = 'null'::jsonb and public.estado_caja() ->> 'queda_anterior' is null, 'caja nueva: sin efectivo anterior');

\echo == Cerrado un turno, propone lo que quedó (contado − retiro)
select public.abrir_turno(100);
select public.cerrar_turno(500, 200);
select pruebas.ok((public.estado_caja() ->> 'queda_anterior')::numeric = 300, 'quedaron 300 (contó 500, retiró 200)');
select public.abrir_turno(300);
select pruebas.ok(public.estado_caja() ->> 'queda_anterior' is null and (public.estado_caja() -> 'turno' ->> 'inicial')::numeric = 300, 'con la caja abierta no viene');
reset role;

\echo == Todas las pruebas de abrir la caja dieron bien
