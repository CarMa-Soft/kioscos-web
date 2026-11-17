-- =====================================================================
-- Pruebas: proveedores, compras y cuenta corriente de proveedores (etapa 5a). Usa el negocio C de 07_reportes.sql:
-- Carla (dueña) con el turno abierto, Cami (empleada), Yerba (p1) y Galletitas (p2).
-- =====================================================================
create function pruebas.prod(p_id text) returns jsonb language sql as $$
  select p from jsonb_array_elements(public.catalogo() -> 'productos') p where p ->> 'id' = p_id;
$$;
grant execute on function pruebas.prod(text) to authenticated;
set local role authenticated;

\echo == Proveedores
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla('select public.proveedores()', 'solo lo puede hacer el dueño', 'el empleado no ve los proveedores');
select pruebas.falla($$select public.registrar_compra('{"items": []}')$$, 'solo lo puede hacer el dueño', 'el empleado no carga compras');
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select pruebas.falla($$select public.guardar_proveedor('{"nombre": "Mal", "cuit": "20-12345678-5"}')$$, 'no es válido', 'controla el dígito verificador del CUIT');
select pruebas.falla($$select public.guardar_proveedor('{"nombre": "Corto", "cuit": "2012345"}')$$, '11 números', 'el CUIT tiene 11 números');
select set_config('prueba.prov', public.guardar_proveedor('{"nombre": "Distribuidora Sur", "cuit": "20123456786", "plazo": "30"}') ->> 'id', false);
select pruebas.ok((select public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'cuit') = '20-12345678-6', 'guarda el CUIT con guiones');
select pruebas.falla($$select public.guardar_proveedor('{"nombre": "Otra", "cuit": "20-12345678-6"}')$$, 'Ya hay un proveedor con el CUIT', 'no repite CUIT');
select pruebas.falla($$select public.guardar_proveedor('{"nombre": " distribuidora sur "}')$$, 'Ya hay un proveedor con ese nombre', 'no repite nombres');

\echo == Compra a cuenta
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select set_config('prueba.stock_y', pruebas.prod(current_setting('prueba.p1')) ->> 'stock', false);
select set_config('prueba.cp1', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.prov'), 'comprobante', 'A 0001-00000123',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 10, 'costo', '700', 'precio_nuevo', '1200'))))::text, false);
select pruebas.ok((current_setting('prueba.cp1')::jsonb ->> 'total')::numeric = 7000, 'total = suma de los renglones');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.stock_y')::numeric + 10, 'suma el stock');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'costo')::numeric = 700 and (pruebas.prod(current_setting('prueba.p1')) ->> 'precio')::numeric = 1200,
  'actualiza el costo y el precio nuevo');
select pruebas.ok(pruebas.prod(current_setting('prueba.p1')) ->> 'proveedor_id' = current_setting('prueba.prov'), 'queda como proveedor habitual');
select pruebas.ok(public.proveedores_de_producto(current_setting('prueba.p1')::bigint) @> '[{"nombre": "Distribuidora Sur", "ultimo_costo": 700, "habitual": true}]',
  'guarda el último costo de ese proveedor');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = 7000, 'la compra suma a la cuenta del proveedor');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric, 'a cuenta no toca la caja');

\echo == Compra pagada con la caja, con el total de la factura
select set_config('prueba.cp2', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.prov'), 'pagar_caja', true, 'forma', 'Efectivo', 'total', '1300',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p2'), 'cantidad', 5, 'costo', 250))))::text, false);
select pruebas.ok((current_setting('prueba.cp2')::jsonb ->> 'total')::numeric = 1300, 'vale el total de la factura');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric - 1300, 'sale de la caja');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = 7000, 'pagada con la caja: la cuenta no cambia');
select pruebas.falla(format($$select public.registrar_compra('{"items": [{"producto_id": %s, "cantidad": 0, "costo": 1}]}')$$, current_setting('prueba.p1')),
  'Cantidad en 0', 'no acepta cantidades en 0');

\echo == Pagos y ajustes
select public.pagar_proveedor(current_setting('prueba.prov')::bigint, 3000, false, 'Transferencia del banco');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = 4000, 'pago aparte: baja la deuda');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric - 1300, 'y no toca la caja');
select public.pagar_proveedor(current_setting('prueba.prov')::bigint, 1000, true, 'Efectivo');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric - 2300, 'pago de la caja: sale del turno');
select set_config('prueba.aj', (select (x ->> 'id') from jsonb_array_elements(
  (public.ajuste_proveedor(current_setting('prueba.prov')::bigint, 500, 'Deuda del cuaderno') || public.cuenta_proveedor(current_setting('prueba.prov')::bigint)) -> 'movimientos') x
  where x ->> 'tipo' = 'ajuste'), false);
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = 3500, 'saldo inicial o ajuste');
select public.anular_mov_proveedor(current_setting('prueba.aj')::bigint);
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = 3000, 'anular el ajuste lo revierte');
select pruebas.falla(format('select public.anular_mov_proveedor(%s)', current_setting('prueba.aj')), 'ya estaba anulado', 'no se anula dos veces');
select pruebas.falla(format('select public.anular_mov_proveedor(%s)', (select x ->> 'id' from jsonb_array_elements(public.cuenta_proveedor(current_setting('prueba.prov')::bigint) -> 'movimientos') x
  where x ->> 'tipo' = 'compra' limit 1)), 'es de una compra', 'lo de una compra se anula anulando la compra');

\echo == Anular compras
select public.anular_compra((current_setting('prueba.cp1')::jsonb ->> 'id')::bigint);
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.stock_y')::numeric, 'anular saca el stock que entró');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = -4000, 'y saca la deuda (lo que se había pagado queda a favor)');
select set_config('prueba.esp2', public.estado_caja() -> 'turno' ->> 'esperado', false);
select public.anular_compra((current_setting('prueba.cp2')::jsonb ->> 'id')::bigint);
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp2')::numeric + 1300, 'anular una pagada con la caja devuelve la plata');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.prov')::bigint) ->> 'saldo')::numeric = -4000, 'y la cuenta no cambia');
select pruebas.falla(format('select public.anular_compra(%s)', current_setting('prueba.cp2')::jsonb ->> 'id'), 'ya estaba anulada', 'no se anula dos veces');
select pruebas.falla(format('select public.eliminar_proveedor(%s)', current_setting('prueba.prov')), 'tiene compras', 'no se borra un proveedor con compras');
select pruebas.ok(jsonb_array_length(public.compras()) = 2, 'lista de compras');

\echo == Otro negocio no ve ni toca proveedores ni compras de C
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.proveedores()) x where x ->> 'nombre' = 'Distribuidora Sur'), 'A no ve los proveedores de C');
select pruebas.falla(format('select public.cuenta_proveedor(%s)', current_setting('prueba.prov')), 'Proveedor no encontrado', 'A no ve la cuenta de un proveedor de C');
select pruebas.falla(format($$select public.pagar_proveedor(%s, 10, false, 'x')$$, current_setting('prueba.prov')), 'Proveedor no encontrado', 'A no le paga a un proveedor de C');
select pruebas.falla(format($$select public.registrar_compra('{"items": [{"producto_id": %s, "cantidad": 1, "costo": 1}]}')$$, current_setting('prueba.p1')),
  'Producto no encontrado', 'A no compra productos de C');
select pruebas.falla(format('select public.anular_compra(%s)', current_setting('prueba.cp1')::jsonb ->> 'id'), 'Compra no encontrada', 'A no anula compras de C');
select pruebas.falla('select * from public.compras', 'permission denied', 'nadie lee la tabla compras directo');
select pruebas.falla('select * from public.cc_prov', 'permission denied', 'nadie lee la tabla cc_prov directo');
reset role;

\echo == Todas las pruebas de proveedores y compras dieron bien
