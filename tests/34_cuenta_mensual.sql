-- =====================================================================
-- Pruebas: cuenta mensual del cliente (lo de cada mes vence un día del mes siguiente). Usa el negocio C (07 en adelante):
-- Carla (dueña) y Cami (empleada).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == Cliente con cuenta mensual: vence el día elegido del mes siguiente
select set_config('prueba.mensual', public.guardar_cliente('{"nombre": "Cuenta mensual", "vence_dia": 10}') ->> 'id', false);
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.mensual')::bigint) ->> 'vence_dia')::int = 10, 'guarda el día de vencimiento');
select public.ajuste_cliente(current_setting('prueba.mensual')::bigint, 800, 'Compra del mes');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.mensual')::bigint) -> 'pendientes' -> 0 ->> 'vencimiento')::date
  = (date_trunc('month', current_setting('prueba.hoy')::date) + interval '1 month')::date + 9, 'lo de este mes vence el 10 del mes que viene');

\echo == Volver a "por días": vence a los días del plazo
select public.guardar_cliente(jsonb_build_object('id', current_setting('prueba.mensual')::bigint, 'nombre', 'Cuenta mensual', 'vence_dia', null, 'plazo', 7));
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.mensual')::bigint) -> 'pendientes' -> 0 ->> 'vencimiento')::date
  = current_setting('prueba.hoy')::date + 7, 'sin cuenta mensual, la fecha más el plazo');

\echo == Validaciones y permisos
select pruebas.falla($$select public.guardar_cliente('{"nombre": "Día raro", "vence_dia": 31}')$$, 'del 1 al 28', 'el día va del 1 al 28');
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla(format($$select public.guardar_cliente('{"id": %s, "nombre": "Cuenta mensual", "vence_dia": 5}')$$, current_setting('prueba.mensual')),
  'solo el dueño', 'el empleado no cambia el plazo');
reset role;

\echo == Todas las pruebas de cuenta mensual dieron bien
