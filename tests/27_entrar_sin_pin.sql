-- =====================================================================
-- Pruebas: entrar sin PIN en un negocio de una sola persona. Usa un negocio nuevo (E) con una sola usuaria, Elsa (dueña).
-- =====================================================================
reset role;
insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('d0000000-0000-4000-8000-0000000000e5', 'authenticated', 'authenticated', 'local.e@prueba.test', now(), now()),
  ('d0000000-0000-4000-8000-0000000000e6', 'authenticated', 'authenticated', 'dueno.e@prueba.test', now(), now());
select set_config('prueba.neg_e', public.admin_alta_negocio('Prueba E', 'dueno.e@prueba.test', 'local.e@prueba.test', 'Elsa', '5555')::text, false);
select set_config('prueba.elsa', (select id from public.usuarios where nombre = 'Elsa' and negocio_id = current_setting('prueba.neg_e')::uuid)::text, false);
set local role authenticated;

\echo == Sin activarlo, el PIN se pide siempre
select pruebas.como('d0000000-0000-4000-8000-0000000000e5');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '') ->> 'error' = 'PIN incorrecto', 'sin PIN no entra');
select set_config('prueba.t_elsa', public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '5555') ->> 'token', false);

\echo == La dueña lo activa: entra sin PIN
select pruebas.como('d0000000-0000-4000-8000-0000000000e5', current_setting('prueba.t_elsa'));
select public.guardar_config('entrar_sin_pin', 'true'::jsonb);
select pruebas.como('d0000000-0000-4000-8000-0000000000e5');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '') ->> 'token' is not null, 'única usuaria y activado: entra sin PIN');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '9999') ->> 'error' = 'PIN incorrecto', 'un PIN equivocado sigue sin servir');
select set_config('prueba.t_elsa', public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '5555') ->> 'token', false);

\echo == Con un segundo usuario, vuelve a pedirse el PIN
select pruebas.como('d0000000-0000-4000-8000-0000000000e5', current_setting('prueba.t_elsa'));
select set_config('prueba.emi', public.guardar_usuario(null, 'Emi', 'empleado', true, '6666') ->> 'id', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000e5');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '') ->> 'error' = 'PIN incorrecto', 'con dos usuarios, sin PIN no entra');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.emi')::bigint, '') ->> 'error' = 'PIN incorrecto', 'el empleado tampoco');

\echo == Desactivado el segundo, otra vez sin PIN
select set_config('prueba.t_elsa', public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '5555') ->> 'token', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000e5', current_setting('prueba.t_elsa'));
select public.guardar_usuario(current_setting('prueba.emi')::bigint, 'Emi', 'empleado', false, null);
select pruebas.como('d0000000-0000-4000-8000-0000000000e5');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.elsa')::bigint, '') ->> 'token' is not null, 'vuelve a ser la única: entra sin PIN');

\echo == Otro negocio no se ve afectado
select pruebas.como('d0000000-0000-4000-8000-0000000000c3');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.carla')::bigint, '') ->> 'error' = 'PIN incorrecto', 'en el negocio C sigue pidiendo PIN');
reset role;

\echo == Todas las pruebas de entrar sin PIN dieron bien
