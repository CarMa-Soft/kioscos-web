-- =====================================================================
-- Pruebas: las ventas de un período para "Descargar mis datos". Usa el negocio C (07 en adelante), que ya vendió hoy.
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == Las ventas de hoy, con productos y formas de pago
select pruebas.ok(jsonb_array_length(public.ventas_periodo(current_setting('prueba.hoy')::date, current_setting('prueba.hoy')::date)) > 0,
  'trae las ventas de hoy');
select pruebas.ok((select bool_and(v ? 'productos' and v ? 'formas' and v ? 'total')
  from jsonb_array_elements(public.ventas_periodo(current_setting('prueba.hoy')::date, current_setting('prueba.hoy')::date)) v), 'cada una con sus datos');
select pruebas.ok(jsonb_array_length(public.ventas_periodo(current_setting('prueba.hoy')::date - 30, current_setting('prueba.hoy')::date - 20)) = 0,
  'otro período, sin ventas');
select pruebas.falla($$select public.ventas_periodo('2026-01-01', '2027-06-01')$$, 'un año', 'más de un año, no');

\echo == Solo el dueño
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.ventas_periodo(current_date, current_date)$$, 'dueño', 'el empleado no descarga');
reset role;

\echo == Todas las pruebas de descargar ventas dieron bien
