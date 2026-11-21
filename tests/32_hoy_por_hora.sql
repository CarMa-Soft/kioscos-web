-- =====================================================================
-- Pruebas: Hoy trae las ventas de hoy hora por hora. Usa el negocio C (07 en adelante), que ya vendió hoy.
-- =====================================================================
set local role authenticated;

\echo == La dueña ve todas las ventas de hoy por hora
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select pruebas.ok(jsonb_array_length(public.inicio() -> 'por_hora') > 0, 'hay al menos una hora con ventas');
select pruebas.ok((select sum((h ->> 'total')::numeric) from jsonb_array_elements(public.inicio() -> 'por_hora') h)
  = (public.inicio() ->> 'total')::numeric + (public.inicio() ->> 'devuelto')::numeric, 'las horas suman lo vendido hoy (antes de devoluciones)');
select pruebas.ok((select sum((h ->> 'tickets')::int) from jsonb_array_elements(public.inicio() -> 'por_hora') h) = (public.inicio() ->> 'tickets')::int,
  'la cantidad de ventas por hora suma las ventas de hoy');

\echo == El empleado, solo las suyas
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok(coalesce((select sum((h ->> 'tickets')::int) from jsonb_array_elements(public.inicio() -> 'por_hora') h), 0) = (public.inicio() ->> 'tickets')::int,
  'el empleado ve por hora solo sus ventas');
reset role;

\echo == Todas las pruebas de Hoy por hora dieron bien
