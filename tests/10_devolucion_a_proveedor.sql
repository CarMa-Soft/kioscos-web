-- =====================================================================
-- Pruebas: devolución a proveedor (etapa 5c). Usa el negocio C (07 a 09): Carla con el turno abierto, Yerba (p1).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.po', public.guardar_proveedor('{"nombre": "Lácteos Oeste"}') ->> 'id', false);
select set_config('prueba.cx', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.po'), 'comprobante', 'B 0002-00000077',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 10, 'costo', 500))))::text, false);
select set_config('prueba.cx_item', current_setting('prueba.cx')::jsonb -> 'items' -> 0 ->> 'id', false);
select set_config('prueba.stock0', pruebas.prod(current_setting('prueba.p1')) ->> 'stock', false);
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);

\echo == A cuenta del proveedor
select set_config('prueba.d1', public.devolver_compra(jsonb_build_object('compra_id', current_setting('prueba.cx')::jsonb ->> 'id', 'forma', 'Cuenta', 'motivo', 'Vencidos',
  'items', jsonb_build_array(jsonb_build_object('id', current_setting('prueba.cx_item'), 'cantidad', 2))))::text, false);
select pruebas.ok(current_setting('prueba.d1')::jsonb -> 'devolucion' ->> 'etiqueta' = 'DP-0001' and (current_setting('prueba.d1')::jsonb -> 'devolucion' ->> 'total')::numeric = 1000,
  'DP-0001 por costo × cantidad');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.stock0')::numeric - 2, 'sale el stock');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.po')::bigint) ->> 'saldo')::numeric = 4000, 'baja lo que se le debe');
select pruebas.ok(pruebas.pendiente(current_setting('prueba.po')::bigint, current_setting('prueba.cx')::jsonb ->> 'id', null) = 4000, 'se aplica sola a esa factura');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.po')::bigint), 'cuadra');

\echo == El proveedor devolvió la plata
select public.devolver_compra(jsonb_build_object('compra_id', current_setting('prueba.cx')::jsonb ->> 'id', 'forma', 'Efectivo',
  'items', jsonb_build_array(jsonb_build_object('id', current_setting('prueba.cx_item'), 'cantidad', 1))));
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric + 500, 'la plata entra a la caja');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.po')::bigint) ->> 'saldo')::numeric = 4000, 'la cuenta no cambia (devolución y reintegro se compensan)');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.po')::bigint), 'cuadra');

\echo == Controles
select pruebas.falla(format($$select public.devolver_compra('{"compra_id": %s, "forma": "Cuenta", "items": [{"id": %s, "cantidad": 8}]}')$$,
  current_setting('prueba.cx')::jsonb ->> 'id', current_setting('prueba.cx_item')), 'hasta 7', 'no se devuelve más de lo que queda');
select pruebas.falla(format($$select public.devolver_compra('{"compra_id": %s, "forma": "Sin reintegro", "items": [{"id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.cx')::jsonb ->> 'id', current_setting('prueba.cx_item')), 'va a su cuenta', 'con proveedor no hay "sin reintegro"');
select pruebas.falla(format($$select public.devolver_compra('{"compra_id": %s, "forma": "Bitcoin", "items": [{"id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.cx')::jsonb ->> 'id', current_setting('prueba.cx_item')), 'qué pasa con la plata', 'forma inválida');
-- el proveedor acredita otro monto
select public.devolver_compra(jsonb_build_object('compra_id', current_setting('prueba.cx')::jsonb ->> 'id', 'forma', 'Cuenta', 'total', '450',
  'items', jsonb_build_array(jsonb_build_object('id', current_setting('prueba.cx_item'), 'cantidad', 1))));
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.po')::bigint) ->> 'saldo')::numeric = 3550, 'el importe se puede cambiar');
select pruebas.ok((public.compra((current_setting('prueba.cx')::jsonb ->> 'id')::bigint) -> 'items' -> 0 ->> 'devuelto')::numeric = 4
  and jsonb_array_length(public.compra((current_setting('prueba.cx')::jsonb ->> 'id')::bigint) -> 'devoluciones') = 3, 'la compra muestra lo devuelto');

\echo == Anular una compra con devoluciones
select public.anular_compra((current_setting('prueba.cx')::jsonb ->> 'id')::bigint);
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.stock0')::numeric - 10, 'anular saca solo el stock que quedó');
select pruebas.ok((public.cuenta_proveedor(current_setting('prueba.po')::bigint) ->> 'saldo')::numeric = 0, 'y la cuenta queda en cero');
select pruebas.ok(pruebas.cuadra(current_setting('prueba.po')::bigint), 'cuadra');
select pruebas.falla(format($$select public.devolver_compra('{"compra_id": %s, "forma": "Cuenta", "items": [{"id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.cx')::jsonb ->> 'id', current_setting('prueba.cx_item')), 'está anulada', 'no se devuelve de una compra anulada');

\echo == Compra sin proveedor, pagada con la caja
select set_config('prueba.cy', public.registrar_compra(jsonb_build_object('pagar_caja', true, 'forma', 'Efectivo',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 3, 'costo', 300))))::text, false);
select pruebas.falla(format($$select public.devolver_compra('{"compra_id": %s, "forma": "Cuenta", "items": [{"id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.cy')::jsonb ->> 'id', current_setting('prueba.cy')::jsonb -> 'items' -> 0 ->> 'id'), 'no tiene proveedor', 'sin proveedor no hay cuenta');
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select public.devolver_compra(jsonb_build_object('compra_id', current_setting('prueba.cy')::jsonb ->> 'id', 'forma', 'Efectivo',
  'items', jsonb_build_array(jsonb_build_object('id', current_setting('prueba.cy')::jsonb -> 'items' -> 0 ->> 'id', 'cantidad', 1))));
select public.anular_compra((current_setting('prueba.cy')::jsonb ->> 'id')::bigint);
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric + 300 + 600,
  'anular vuelve a la caja lo pagado menos lo que el proveedor ya devolvió');

\echo == Otro negocio
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format($$select public.devolver_compra('{"compra_id": %s, "forma": "Cuenta", "items": []}')$$, current_setting('prueba.cy')::jsonb ->> 'id'),
  'Compra no encontrada', 'A no devuelve compras de C');
select pruebas.falla('select * from public.devoluciones_compra', 'permission denied', 'nadie lee la tabla devoluciones_compra directo');
reset role;

\echo == Todas las pruebas de devolución a proveedor dieron bien
