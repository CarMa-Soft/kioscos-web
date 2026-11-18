-- =====================================================================
-- Pruebas: cuenta del cliente con plazo, vencimientos y aplicación de pagos. Usa el negocio C (07 a 21): Carla (dueña),
-- Cami (empleada) y el turno abierto de C.
-- =====================================================================
-- Ayudas: pendiente − a favor = saldo, y lo pendiente de una compra (venta) o deuda (ajuste)
create function pruebas.cuadra_cli(p_id bigint) returns boolean language sql as $$
  select (select coalesce(sum((d ->> 'pendiente')::numeric), 0) from jsonb_array_elements(c -> 'pendientes') d) - (c ->> 'a_favor')::numeric = (c ->> 'saldo')::numeric
  from (select public.cuenta_cliente(p_id) as c) x;
$$;
create function pruebas.pend_cli(p_id bigint, p_venta text, p_deuda text) returns numeric language sql as $$
  select coalesce((select (d ->> 'pendiente')::numeric from jsonb_array_elements(public.cuenta_cliente(p_id) -> 'pendientes') d
    where d ->> 'venta_id' is not distinct from p_venta and d ->> 'deuda_id' is not distinct from p_deuda), 0);
$$;
grant execute on function pruebas.cuadra_cli(bigint), pruebas.pend_cli(bigint, text, text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == Plazo
-- (en dos pasos: cuenta_cliente es stable y no ve lo que se guardó en la misma sentencia)
select set_config('prueba.cli_plazo', public.guardar_cliente('{"nombre": "Para ver el plazo"}') ->> 'id', false);
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.cli_plazo')::bigint) ->> 'plazo_general')::int = 30,
  'el plazo general de fábrica es 30 días');
select pruebas.ok(public.guardar_plazo_clientes(15) = 15, 'el dueño cambia el plazo general');
select pruebas.falla('select public.guardar_plazo_clientes(400)', 'entre 0 y 365', 'plazo general fuera de rango');
select set_config('prueba.rosa', public.guardar_cliente('{"nombre": "Rosa Fiadora"}') ->> 'id', false);
select set_config('prueba.leo', public.guardar_cliente('{"nombre": "Leo Plazo", "plazo": "7"}') ->> 'id', false);
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.leo')::bigint) ->> 'plazo')::int = 7, 'el cliente guarda su plazo');
select pruebas.falla($$select public.guardar_cliente('{"nombre": "Mal plazo", "plazo": "1,5"}')$$, 'de 0 a 365', 'plazo con decimales');

\echo == Ventas fiadas y deuda anterior
select set_config('prueba.yerba', public.guardar_producto('{"nombre": "Yerba de prueba", "precio": 1000, "stock": 100}') ->> 'id', false);
select set_config('prueba.v1', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.yerba'))::jsonb,
  '[{"forma": "Fiado", "base": 1000}]', p_cliente_id => current_setting('prueba.rosa')::bigint) ->> 'id', false);
select set_config('prueba.v2', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 2}]', current_setting('prueba.yerba'))::jsonb,
  '[{"forma": "Fiado", "base": 2000}]', p_cliente_id => current_setting('prueba.rosa')::bigint) ->> 'id', false);
select public.ajuste_cliente(current_setting('prueba.rosa')::bigint, 500, 'Deuda del cuaderno');
select set_config('prueba.aj', (select d ->> 'deuda_id' from jsonb_array_elements(public.cuenta_cliente(current_setting('prueba.rosa')::bigint) -> 'pendientes') d
  where d ->> 'deuda_id' is not null), false);
select pruebas.ok(jsonb_array_length(public.cuenta_cliente(current_setting('prueba.rosa')::bigint) -> 'pendientes') = 3
  and (public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'saldo')::numeric = 3500, 'dos compras y la deuda anterior, pendientes');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.rosa')::bigint) -> 'pendientes' -> 0 ->> 'vencimiento')::date
  = (public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'hoy')::date + 15, 'sin plazo propio vence con el general (15 días)');
select set_config('prueba.vleo', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.yerba'))::jsonb,
  '[{"forma": "Fiado", "base": 1000}]', p_cliente_id => current_setting('prueba.leo')::bigint) ->> 'id', false);
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.leo')::bigint) -> 'pendientes' -> 0 ->> 'vencimiento')::date
  = (public.cuenta_cliente(current_setting('prueba.leo')::bigint) ->> 'hoy')::date + 7, 'con plazo propio vence a los 7 días');

\echo == Cobrar sin elegir: a lo que vence primero
select public.cobrar_cliente(current_setting('prueba.rosa')::bigint, 1200, 'Efectivo');
select pruebas.ok(pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v1'), null) = 0
  and pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v2'), null) = 1800, 'paga la primera y parte de la segunda');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.cuenta_cliente(current_setting('prueba.rosa')::bigint) -> 'pagadas') d
  where d ->> 'venta_id' = current_setting('prueba.v1') and d ->> 'pagada' is not null), 'la primera queda entre las pagadas, con la fecha');
select pruebas.ok(pruebas.cuadra_cli(current_setting('prueba.rosa')::bigint), 'cuadra');

\echo == Cobrar eligiendo, parcial y con sobrante
select public.cobrar_cliente(current_setting('prueba.rosa')::bigint, 500, 'Efectivo', null, jsonb_build_array(jsonb_build_object('deuda_id', current_setting('prueba.aj'), 'monto', 500)));
select pruebas.ok(pruebas.pend_cli(current_setting('prueba.rosa')::bigint, null, current_setting('prueba.aj')) = 0
  and pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v2'), null) = 1800, 'va solo a la deuda anterior');
select public.cobrar_cliente(current_setting('prueba.rosa')::bigint, 300, 'Efectivo', null, jsonb_build_array(jsonb_build_object('venta_id', current_setting('prueba.v2'), 'monto', 100)));
select pruebas.ok(pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v2'), null) = 1700
  and (public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'a_favor')::numeric = 200, 'aplica 100 y quedan 200 a favor');
select pruebas.ok(pruebas.cuadra_cli(current_setting('prueba.rosa')::bigint), 'cuadra con plata a favor');
select pruebas.falla(format($$select public.cobrar_cliente(%s, 100, 'Efectivo', null, '[{"venta_id": %s, "monto": 500}]')$$,
  current_setting('prueba.rosa'), current_setting('prueba.v2')), 'suma más que el pago', 'no se aplica más de lo que se paga');
select pruebas.falla(format($$select public.cobrar_cliente(%s, 9000, 'Efectivo', null, '[{"venta_id": %s, "monto": 5000}]')$$,
  current_setting('prueba.rosa'), current_setting('prueba.v2')), 'le quedan', 'no se aplica más de lo pendiente');
select pruebas.falla(format($$select public.cobrar_cliente(%s, 100, 'Efectivo', null, '[{"venta_id": %s, "monto": 50}]')$$,
  current_setting('prueba.rosa'), current_setting('prueba.vleo')), 'no es de este cliente', 'no se aplica a compras de otro cliente');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'saldo')::numeric = 1500, 'lo que falló no cobró nada');

\echo == Lo que está a favor se aplica solo a la compra siguiente
select set_config('prueba.v3', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.yerba'))::jsonb,
  '[{"forma": "Fiado", "base": 1000}]', p_cliente_id => current_setting('prueba.rosa')::bigint) ->> 'id', false);
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'a_favor')::numeric = 0
  and pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v2'), null) = 1500
  and pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v3'), null) = 1000, 'los 200 van a lo que vence primero');
select pruebas.ok(pruebas.cuadra_cli(current_setting('prueba.rosa')::bigint), 'cuadra');

\echo == Anular una compra pagada en parte: lo pagado pasa a la siguiente
select public.anular_venta(current_setting('prueba.v2')::bigint, 'prueba');
select pruebas.ok(pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v2'), null) = 0
  and not exists (select 1 from jsonb_array_elements(public.cuenta_cliente(current_setting('prueba.rosa')::bigint) -> 'pagadas') d
                  where d ->> 'venta_id' = current_setting('prueba.v2')), 'la anulada ya no está ni pendiente ni pagada');
select pruebas.ok(pruebas.pend_cli(current_setting('prueba.rosa')::bigint, current_setting('prueba.v3'), null) = 500
  and (public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'saldo')::numeric = 500, 'los 500 que tenía pagados van a la tercera');
select pruebas.ok(pruebas.cuadra_cli(current_setting('prueba.rosa')::bigint), 'cuadra después de anular');

\echo == Aplicar lo que está a favor (sin mover plata)
select public.ajuste_cliente(current_setting('prueba.leo')::bigint, -300, 'Bonificación');
select pruebas.ok(pruebas.pend_cli(current_setting('prueba.leo')::bigint, current_setting('prueba.vleo'), null) = 700, 'un ajuste que resta se aplica solo');
select pruebas.falla(format('select public.aplicar_cliente(%s, %s)', current_setting('prueba.leo'), quote_literal('[]')), 'Elegí a qué compras', 'aplicar sin elegir nada');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.rosa')::bigint) ->> 'saldo')::numeric = 500, 'el empleado ve la cuenta');
select pruebas.falla('select public.guardar_plazo_clientes(20)', 'solo lo puede hacer el dueño', 'el empleado no cambia el plazo general');
select pruebas.falla(format($$select public.guardar_cliente('{"id": %s, "nombre": "Leo Plazo", "plazo": "60"}')$$, current_setting('prueba.leo')),
  'solo el dueño', 'el empleado no cambia el plazo de un cliente');
select pruebas.ok((public.guardar_cliente(format('{"id": %s, "nombre": "Leo Plazo", "telefono": "1"}', current_setting('prueba.leo'))::jsonb) ->> 'plazo')::int = 7,
  'el empleado edita sin tocar el plazo');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format('select public.cuenta_cliente(%s)', current_setting('prueba.rosa')), 'Cliente no encontrado', 'A no ve la cuenta de un cliente de C');
select pruebas.falla(format($$select public.cobrar_cliente(%s, 10, 'Efectivo')$$, current_setting('prueba.rosa')), 'Cliente no encontrado', 'A no le cobra a un cliente de C');
select pruebas.falla(format('select public.aplicar_cliente(%s)', current_setting('prueba.rosa')), 'Cliente no encontrado', 'A no aplica en la cuenta de un cliente de C');
select pruebas.falla('select * from public.aplicaciones_cli', 'permission denied', 'nadie lee la tabla aplicaciones_cli directo');
select pruebas.falla(format('select * from public.deudas_cliente(%s)', current_setting('prueba.rosa')), 'permission denied', 'nadie llama directo a deudas_cliente');
reset role;

\echo == Todas las pruebas de la cuenta de clientes dieron bien
