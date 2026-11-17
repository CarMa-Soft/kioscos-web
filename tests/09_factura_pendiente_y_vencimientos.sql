-- =====================================================================
-- Pruebas: factura pendiente, fechas, vencimientos y aplicación de pagos (etapa 5b). Usa el negocio C (07 y 08):
-- Carla (dueña) con el turno abierto, Yerba (p1) y Galletitas (p2).
-- =====================================================================
-- Siempre: lo pendiente de las facturas − lo que está a cuenta sin aplicar = saldo de la cuenta
create function pruebas.cuadra(p_id bigint) returns boolean language sql as $$
  select (select coalesce(sum((d ->> 'pendiente')::numeric), 0) from jsonb_array_elements(c -> 'deudas') d) - (c ->> 'sin_aplicar')::numeric = (c ->> 'saldo')::numeric
  from (select public.cuenta_proveedor(p_id) as c) x;
$$;
create function pruebas.pendiente(p_id bigint, p_compra text, p_deuda text) returns numeric language sql as $$
  select coalesce((select (d ->> 'pendiente')::numeric from jsonb_array_elements(public.cuenta_proveedor(p_id) -> 'deudas') d
    where d ->> 'compra_id' is not distinct from p_compra and d ->> 'deuda_id' is not distinct from p_deuda), 0);
$$;
grant execute on function pruebas.cuadra(bigint), pruebas.pendiente(bigint, text, text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.pv', public.guardar_proveedor('{"nombre": "Mayorista Norte", "plazo": 30}') ->> 'id', false);

\echo == Factura pendiente
select set_config('prueba.ca', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pv'), 'comprobante', 'R-0001',
  'factura_pendiente', true, 'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 10, 'costo', 600))))::text, false);
select pruebas.ok((current_setting('prueba.ca')::jsonb ->> 'factura_pendiente')::boolean and current_setting('prueba.ca')::jsonb ->> 'remito' = 'R-0001'
  and current_setting('prueba.ca')::jsonb ->> 'comprobante' = '', 'sin factura: el número queda como remito');
select pruebas.ok(current_setting('prueba.ca')::jsonb -> 'fecha_factura' = 'null'::jsonb, 'sin fecha de factura todavía');
select pruebas.ok((current_setting('prueba.ca')::jsonb ->> 'vencimiento')::date - (now() at time zone 'America/Argentina/Buenos_Aires')::date = 30,
  'el vencimiento se estima con el plazo del proveedor');
select set_config('prueba.stock_y', pruebas.prod(current_setting('prueba.p1')) ->> 'stock', false);
select public.cargar_factura_compra(jsonb_build_object('id', current_setting('prueba.ca')::jsonb ->> 'id', 'comprobante', 'A 0001-00000045', 'fecha_factura', '2026-10-01',
  'items', jsonb_build_array(jsonb_build_object('id', current_setting('prueba.ca')::jsonb -> 'items' -> 0 ->> 'id', 'costo', 550))));
select pruebas.ok((public.compra((current_setting('prueba.ca')::jsonb ->> 'id')::bigint) ->> 'vencimiento') = '2026-10-31', 'la factura: vence a los 30 días de su fecha');
select pruebas.ok((public.compra((current_setting('prueba.ca')::jsonb ->> 'id')::bigint) -> 'items' -> 0 ->> 'costo_remito')::numeric = 600, 'guarda el costo del remito');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.stock_y')::numeric, 'agregar la factura no mueve el stock');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'costo')::numeric = 550, 'actualiza el costo (es la compra más reciente)');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.pv')::bigint) ->> 'saldo')::numeric = 5500, 'la factura vino por menos: la diferencia queda en la cuenta');
select pruebas.falla(format($$select public.cargar_factura_compra('{"id": %s, "comprobante": "X"}')$$, current_setting('prueba.ca')::jsonb ->> 'id'),
  'ya tiene la factura', 'no se carga la factura dos veces');

\echo == Vencimientos y aplicación de pagos
select set_config('prueba.cb', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pv'), 'comprobante', 'A 0001-00000050',
  'fecha_factura', '2026-10-10', 'vencimiento', '2026-10-20',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p2'), 'cantidad', 5, 'costo', 200))))::jsonb ->> 'id', false);
select public.ajuste_proveedor(current_setting('prueba.pv')::bigint, 2000, 'Saldo inicial', '2026-09-30');
select set_config('prueba.aj', (select d ->> 'deuda_id' from jsonb_array_elements(public.cuenta_proveedor(current_setting('prueba.pv')::bigint) -> 'deudas') d
  where d ->> 'deuda_id' is not null), false);
select pruebas.ok((select array_agg(coalesce(d ->> 'compra_id', 'aj') order by n) from jsonb_array_elements(public.cuenta_proveedor(current_setting('prueba.pv')::bigint) -> 'deudas')
  with ordinality as t(d, n)) = array['aj', current_setting('prueba.cb'), current_setting('prueba.ca')::jsonb ->> 'id'], 'las deudas, de la que vence primero a la última');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.pv')::bigint), 'cuadra: pendiente − a cuenta = saldo');
select public.pagar_proveedor(current_setting('prueba.pv')::bigint, 2500, false, 'Banco', null,
  jsonb_build_array(jsonb_build_object('deuda_id', current_setting('prueba.aj'), 'monto', 2000), jsonb_build_object('compra_id', current_setting('prueba.cb'), 'monto', 500)));
select pruebas.ok(pruebas.pendiente(current_setting('prueba.pv')::bigint, null, current_setting('prueba.aj')) = 0
  and pruebas.pendiente(current_setting('prueba.pv')::bigint, current_setting('prueba.cb'), null) = 500, 'el pago se aplica a las facturas elegidas (una completa, otra parcial)');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.pv')::bigint), 'cuadra después del pago');
select pruebas.falla(format($$select public.pagar_proveedor(%s, 1000, false, 'Banco', null, '[{"compra_id": %s, "monto": 2000}]')$$,
  current_setting('prueba.pv'), current_setting('prueba.ca')::jsonb ->> 'id'), 'suma más que el pago', 'no se aplica más que el pago');
select pruebas.falla(format($$select public.pagar_proveedor(%s, 1000, false, 'Banco', null, '[{"compra_id": %s, "monto": 600}]')$$,
  current_setting('prueba.pv'), current_setting('prueba.cb')), 'le quedan 500', 'no se aplica más que lo pendiente');
select public.pagar_proveedor(current_setting('prueba.pv')::bigint, 1000, false, 'Banco');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.pv')::bigint) ->> 'sin_aplicar')::numeric = 1000, 'un pago sin aplicar queda a cuenta');
select public.aplicar_proveedor(current_setting('prueba.pv')::bigint, jsonb_build_array(jsonb_build_object('compra_id', current_setting('prueba.cb'), 'monto', 500)));
select pruebas.ok(pruebas.pendiente(current_setting('prueba.pv')::bigint, current_setting('prueba.cb'), null) = 0
  and (public.cuenta_proveedor(current_setting('prueba.pv')::bigint) ->> 'sin_aplicar')::numeric = 500, 'aplicar lo que está a cuenta, sin mover plata');
select pruebas.falla(format($$select public.aplicar_proveedor(%s, '[{"compra_id": %s, "monto": 600}]')$$, current_setting('prueba.pv'), current_setting('prueba.ca')::jsonb ->> 'id'),
  'No hay tanto a cuenta', 'no se aplica más de lo que hay a cuenta');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.pv')::bigint), 'cuadra después de aplicar');

\echo == Lista de vencimientos
select pruebas.ok(not (public.vencimientos('2026-10-25') -> 'proveedores' @> format('[{"id": %s}]', current_setting('prueba.pv'))::jsonb),
  'hasta el 25/10 no hay nada que pagarle (lo que vencía ya está pagado)');
select pruebas.ok((select (x ->> 'total')::numeric from jsonb_array_elements(public.vencimientos('2026-11-30') -> 'proveedores') x
  where (x ->> 'id') = current_setting('prueba.pv')) = 5500, 'hasta el 30/11 vence la factura de 5500');

\echo == Anular un pago deshace sus aplicaciones
select public.anular_mov_proveedor((select (m ->> 'id')::bigint from jsonb_array_elements(public.cuenta_proveedor(current_setting('prueba.pv')::bigint) -> 'movimientos') m
  where (m ->> 'monto')::numeric = -2500));
select pruebas.ok(pruebas.pendiente(current_setting('prueba.pv')::bigint, null, current_setting('prueba.aj')) = 2000
  and pruebas.pendiente(current_setting('prueba.pv')::bigint, current_setting('prueba.cb'), null) = 500, 'las facturas vuelven a quedar pendientes');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.pv')::bigint), 'cuadra después de anular el pago');

\echo == Pagada con la caja y anulaciones
select set_config('prueba.cc', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pv'), 'pagar_caja', true, 'forma', 'Efectivo',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p2'), 'cantidad', 1, 'costo', 100))))::jsonb ->> 'id', false);
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.cuenta_proveedor(current_setting('prueba.pv')::bigint) -> 'deudas') d where d ->> 'compra_id' = current_setting('prueba.cc')),
  'pagada con la caja: queda saldada');
select public.aplicar_proveedor(current_setting('prueba.pv')::bigint, jsonb_build_array(jsonb_build_object('compra_id', current_setting('prueba.ca')::jsonb ->> 'id', 'monto', 500)));
select public.anular_compra((current_setting('prueba.ca')::jsonb ->> 'id')::bigint);
select pruebas.ok(pruebas.cuadra(current_setting('prueba.pv')::bigint), 'cuadra después de anular una compra con pagos aplicados');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.pv')::bigint) ->> 'sin_aplicar')::numeric = 500, 'lo aplicado a la compra anulada vuelve a quedar a cuenta');

\echo == Otro negocio
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format($$select public.aplicar_proveedor(%s, '[]')$$, current_setting('prueba.pv')), 'Proveedor no encontrado', 'A no aplica pagos de un proveedor de C');
select pruebas.falla(format($$select public.cargar_factura_compra('{"id": %s, "comprobante": "X"}')$$, current_setting('prueba.cb')), 'Compra no encontrada', 'A no carga facturas de C');
select pruebas.ok(not (public.vencimientos('2030-01-01') -> 'proveedores' @> '[{"nombre": "Mayorista Norte"}]'), 'A no ve los vencimientos de C');
reset role;

\echo == Todas las pruebas de factura pendiente y vencimientos dieron bien
