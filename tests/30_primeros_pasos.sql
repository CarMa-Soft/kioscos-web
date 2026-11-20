-- =====================================================================
-- Pruebas: los datos de los primeros pasos en Hoy. Usa el negocio C (07 en adelante), que ya tiene turno y ventas.
-- =====================================================================
set local role authenticated;

\echo == La dueña ve si ya se abrió la caja y si ya se vendió
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select pruebas.ok((public.inicio() -> 'arranque' ->> 'hubo_turno')::boolean and (public.inicio() -> 'arranque' ->> 'hubo_venta')::boolean,
  'el negocio C ya abrió la caja y ya vendió');

\echo == El empleado no lo recibe
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok(public.inicio() -> 'arranque' = 'null'::jsonb, 'sin primeros pasos para el empleado');
reset role;

\echo == Todas las pruebas de primeros pasos dieron bien
