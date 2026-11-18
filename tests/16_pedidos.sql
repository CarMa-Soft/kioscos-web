-- =====================================================================
-- Pruebas: pedidos a proveedores. Usa el negocio C (07 a 15): Carla (dueña) y Cami (empleada).
-- =====================================================================
-- Un producto en el pedido (en cualquier grupo), con el grupo donde está: 'proveedor:<nombre>', 'sin_proveedor' o 'pendientes'
create function pruebas.en_pedido(p_id text) returns jsonb language sql as $$
  with p as (select public.pedidos() as j)
  select coalesce(
    (select i || jsonb_build_object('grupo', 'proveedor:' || (g ->> 'nombre')) from p, jsonb_array_elements(j -> 'proveedores') g,
       jsonb_array_elements(g -> 'items') i where i ->> 'producto_id' = p_id limit 1),
    (select i || '{"grupo": "sin_proveedor"}' from p, jsonb_array_elements(j -> 'sin_proveedor') i where i ->> 'producto_id' = p_id limit 1),
    (select i || '{"grupo": "pendientes"}' from p, jsonb_array_elements(j -> 'pendientes') i where i ->> 'producto_id' = p_id limit 1));
$$;
grant execute on function pruebas.en_pedido(text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

select set_config('prueba.bn', public.guardar_proveedor('{"nombre": "Bebidas Norte", "telefono": "11 5555-1234"}') ->> 'id', false);
select set_config('prueba.mc', public.guardar_proveedor('{"nombre": "Mayorista Centro"}') ->> 'id', false);
select set_config('prueba.gas', public.guardar_producto('{"nombre": "Gaseosa Cola 2L", "costo": 800, "precio": 1500, "stock_min": 10}') ->> 'id', false);
select set_config('prueba.jugo', public.guardar_producto('{"nombre": "Jugo de naranja", "costo": 300, "precio": 600}') ->> 'id', false);
select set_config('prueba.queso', public.guardar_producto('{"nombre": "Queso cremoso", "costo": 6000, "precio": 9000, "por_peso": true, "stock": 0.4, "stock_min": 2}') ->> 'id', false);
select set_config('prueba.car', public.guardar_producto('{"nombre": "Caramelos", "costo": 10, "precio": 30, "stock": 50, "stock_min": 10}') ->> 'id', false);
-- la gaseosa se le compró a Bebidas Norte (queda como habitual, con su último costo)
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.bn'), 'comprobante', 'B 0001-00000321',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.gas'), 'cantidad', 3, 'costo', 750))));

\echo == Qué aparece y dónde
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.gas')) ->> 'grupo' = 'proveedor:Bebidas Norte'
  and (pruebas.en_pedido(current_setting('prueba.gas')) ->> 'propuesta')::numeric = 17
  and (pruebas.en_pedido(current_setting('prueba.gas')) ->> 'ultimo_costo')::numeric = 750
  and not (pruebas.en_pedido(current_setting('prueba.gas')) ->> 'sin_stock')::boolean, 'stock bajo: en su proveedor, propone hasta el doble del mínimo (17) y el último costo');
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.jugo')) ->> 'grupo' = 'sin_proveedor'
  and (pruebas.en_pedido(current_setting('prueba.jugo')) ->> 'sin_stock')::boolean
  and (pruebas.en_pedido(current_setting('prueba.jugo')) ->> 'propuesta')::numeric = 1, 'sin stock y sin proveedor: propone 1');
select pruebas.ok((pruebas.en_pedido(current_setting('prueba.queso')) ->> 'propuesta')::numeric = 3.6, 'por kilo: propone 3,6 kg');
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.car')) is null, 'con stock suficiente no aparece');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.pedidos() -> 'proveedores') g
  where g ->> 'nombre' = 'Bebidas Norte' and g ->> 'telefono' = '11 5555-1234'), 'el pedido trae el teléfono del proveedor');

\echo == Cantidad
select public.pedido_cantidad(current_setting('prueba.gas')::bigint, 24);
select pruebas.ok((pruebas.en_pedido(current_setting('prueba.gas')) ->> 'cantidad')::numeric = 24, 'se cambia la cantidad');
select public.pedido_cantidad(current_setting('prueba.gas')::bigint, null);
select pruebas.ok((pruebas.en_pedido(current_setting('prueba.gas')) ->> 'cantidad')::numeric = 17, 'vacía vuelve a la propuesta');
select pruebas.falla(format('select public.pedido_cantidad(%s, -1)', current_setting('prueba.gas')), 'mayor a 0', 'cantidad negativa');

\echo == Cambiar el proveedor
select public.pedido_proveedor(current_setting('prueba.jugo')::bigint, current_setting('prueba.mc')::bigint);
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.jugo')) ->> 'grupo' = 'proveedor:Mayorista Centro', 'pasa al pedido del proveedor elegido');
select pruebas.ok((pruebas.prod(current_setting('prueba.jugo')) ->> 'proveedor_id') = current_setting('prueba.mc'), 'y queda como su habitual');

\echo == Quitar y volver
select public.pedido_pendiente(current_setting('prueba.gas')::bigint, true);
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.gas')) ->> 'grupo' = 'pendientes'
  and pruebas.en_pedido(current_setting('prueba.gas')) ->> 'proveedor' = 'Bebidas Norte', 'quitado: queda en Pendientes de pedir, con su proveedor');
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.pedidos() -> 'proveedores') g where g ->> 'nombre' = 'Bebidas Norte'),
  'el pedido que queda vacío no se muestra');
select public.pedido_pendiente(current_setting('prueba.gas')::bigint, false);
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.gas')) ->> 'grupo' = 'proveedor:Bebidas Norte', 'vuelve al pedido');

\echo == Al cargar la compra
select public.pedido_cantidad(current_setting('prueba.gas')::bigint, 24);
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.bn'), 'comprobante', 'B 0001-00000322',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.gas'), 'cantidad', 24, 'costo', 760))));
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.gas')) is null, 'lo que llegó y supera el mínimo sale del pedido');
select public.pedido_cantidad(current_setting('prueba.queso')::bigint, 5);
select public.pedido_pendiente(current_setting('prueba.queso')::bigint, true);
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.mc'), 'comprobante', 'B 0001-00000323',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.queso'), 'cantidad', 1, 'costo', 6100))));
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.queso')) ->> 'grupo' = 'proveedor:Mayorista Centro'
  and (pruebas.en_pedido(current_setting('prueba.queso')) ->> 'cantidad')::numeric = 2.6,
  'si llegó menos de lo necesario, vuelve al pedido con una propuesta nueva (2,6 kg)');

\echo == Dados de baja
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.jugo'), 'nombre', 'Jugo de naranja', 'precio', 600, 'activo', false));
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.jugo')) is null, 'un producto dado de baja no se pide');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla('select public.pedidos()', 'solo lo puede hacer el dueño', 'el empleado no ve los pedidos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format('select public.pedido_cantidad(%s, 3)', current_setting('prueba.queso')), 'Producto no encontrado', 'A no toca los pedidos de C');
select pruebas.falla(format('select public.pedido_proveedor(%s, %s)', current_setting('prueba.queso'), current_setting('prueba.mc')), 'Producto no encontrado',
  'A no cambia proveedores de C');
select pruebas.ok(pruebas.en_pedido(current_setting('prueba.queso')) is null, 'A no ve los productos de C en su pedido');
select pruebas.falla('select * from public.pedido_items', 'permission denied', 'nadie lee la tabla pedido_items directo');
reset role;

\echo == Todas las pruebas de pedidos dieron bien
