-- =====================================================================
-- Pruebas: la lista de clientes trae la antigüedad de la deuda (para ordenarla). Usa el negocio C (07 a 25): Carla (dueña).
-- =====================================================================
create function pruebas.cli(p_id text) returns jsonb language sql as $$
  select c from jsonb_array_elements(public.clientes()) c where c ->> 'id' = p_id;
$$;
grant execute on function pruebas.cli(text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.al_dia', public.guardar_cliente('{"nombre": "Sin deuda"}') ->> 'id', false);
select set_config('prueba.deudor', public.guardar_cliente('{"nombre": "Con deuda vieja", "plazo": "10"}') ->> 'id', false);
select public.ajuste_cliente(current_setting('prueba.deudor')::bigint, 1500, 'Deuda del cuaderno');

\echo == Antigüedad de la deuda
select pruebas.ok(pruebas.cli(current_setting('prueba.al_dia')) ->> 'deuda_desde' is null
  and pruebas.cli(current_setting('prueba.al_dia')) ->> 'vence' is null
  and pruebas.cli(current_setting('prueba.al_dia')) ->> 'ultimo' is null, 'sin deuda ni movimientos: todo vacío');
select pruebas.ok(pruebas.cli(current_setting('prueba.deudor')) ->> 'deuda_desde' is not null
  and (pruebas.cli(current_setting('prueba.deudor')) ->> 'vence')::date = current_setting('prueba.hoy')::date + 10
  and pruebas.cli(current_setting('prueba.deudor')) ->> 'ultimo' is not null, 'con deuda: desde cuándo debe, cuándo vence y el último movimiento');
select pruebas.ok((pruebas.cli(current_setting('prueba.deudor')) ->> 'saldo')::numeric = 1500, 'el saldo sigue viniendo');

\echo == Cobrada la deuda, ya no tiene antigüedad (pero sí último movimiento)
select public.cobrar_cliente(current_setting('prueba.deudor')::bigint, 1500, 'Efectivo');
select pruebas.ok(pruebas.cli(current_setting('prueba.deudor')) ->> 'deuda_desde' is null
  and pruebas.cli(current_setting('prueba.deudor')) ->> 'ultimo' is not null, 'al día: sin "debe desde"');
reset role;

\echo == Todas las pruebas de antigüedad de clientes dieron bien
