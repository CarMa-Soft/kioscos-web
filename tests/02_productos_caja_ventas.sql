-- =====================================================================
-- Pruebas: productos, caja y ventas (etapa 3). Usa las ayudas, cuentas y negocios de 01_negocios_y_usuarios.sql
-- (corren en la misma transacción, en orden).
-- =====================================================================

\echo == Preparación
update public.negocios set activo = true where id = current_setting('prueba.neg_a')::uuid;
set local role authenticated;
select pruebas.como('a0000000-0000-4000-8000-0000000000c1');
select set_config('prueba.t_ana', public.iniciar_usuario(current_setting('prueba.ana')::bigint, '1111') ->> 'token', false);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select set_config('prueba.eva', public.guardar_usuario(null, 'Eva', 'empleado', true, '5555') ->> 'id', false);
select set_config('prueba.teo', public.guardar_usuario(null, 'Teo', 'empleado', true, '6666') ->> 'id', false);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1');
select set_config('prueba.t_eva', public.iniciar_usuario(current_setting('prueba.eva')::bigint, '5555') ->> 'token', false);
select set_config('prueba.t_teo', public.iniciar_usuario(current_setting('prueba.teo')::bigint, '6666') ->> 'token', false);
select pruebas.como('b0000000-0000-4000-8000-0000000000c2');
select set_config('prueba.t_beto', public.iniciar_usuario(current_setting('prueba.beto')::bigint, '2222') ->> 'token', false);

-- ---------------------------------------------------------------------
\echo == Productos (Ana, dueña de A)
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(jsonb_array_length(public.catalogo() -> 'productos') = 0, 'el catálogo empieza vacío');
select set_config('prueba.cat', public.guardar_categoria(null, 'Bebidas') ->> 'id', false);
select pruebas.falla($$select public.guardar_categoria(null, ' bebidas ')$$, 'Ya existe', 'no repite categorías');
select set_config('prueba.coca', public.guardar_producto(jsonb_build_object('nombre', 'Coca 1.5', 'codigo', '7790001',
  'categoria_id', current_setting('prueba.cat'), 'costo', '500', 'precio', '1000', 'stock', '10')) ->> 'id', false);
select set_config('prueba.queso', public.guardar_producto('{"nombre": "Queso por kilo", "precio": "8000,00", "stock": "5", "por_peso": true}') ->> 'id', false);
select set_config('prueba.chicle', public.guardar_producto('{"nombre": "Chicle", "precio": "200"}') ->> 'id', false);
select pruebas.falla($$select public.guardar_producto('{"nombre": "Otra", "codigo": "7790001"}')$$, 'ya lo tiene "Coca 1.5"', 'no repite códigos');
select pruebas.falla($$select public.guardar_producto('{"nombre": "Mal", "precio": "abc"}')$$, 'Precio: valor inválido', 'avisa un precio inválido');
select pruebas.falla($$select public.guardar_producto('{"nombre": "Neg", "precio": "-5"}')$$, 'check', 'no acepta precios negativos');
select pruebas.ok((public.catalogo() -> 'productos' -> 0 ->> 'costo')::numeric = 500, 'el dueño ve el costo');
select public.ajustar_stock(current_setting('prueba.chicle')::bigint, 50, 'Conteo');
select pruebas.ok((select (p ->> 'stock')::numeric from jsonb_array_elements(public.catalogo() -> 'productos') p
  where p ->> 'nombre' = 'Chicle') = 50, 'ajusta el stock');
reset role;
select pruebas.ok((select count(*) from public.movimientos_stock where producto_id = current_setting('prueba.coca')::bigint and motivo = 'Stock inicial') = 1,
  'el stock inicial queda como movimiento');
set local role authenticated;

\echo == El otro negocio y el empleado
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.t_beto'));
select pruebas.ok(jsonb_array_length(public.catalogo() -> 'productos') = 0 and jsonb_array_length(public.catalogo() -> 'categorias') = 0,
  'el negocio B no ve los productos ni las categorías de A');
select pruebas.falla(format($$select public.guardar_producto('{"nombre": "X", "categoria_id": %s}')$$, current_setting('prueba.cat')),
  'Categoría no encontrada', 'B no puede usar una categoría de A');
select pruebas.falla(format($$select public.guardar_producto('{"id": %s, "nombre": "Hackeado"}')$$, current_setting('prueba.coca')),
  'Producto no encontrado', 'B no puede editar un producto de A');
select pruebas.falla(format($$select public.ajustar_stock(%s, 0)$$, current_setting('prueba.coca')), 'Producto no encontrado', 'B no ajusta stock de A');
select pruebas.falla(format($$select public.eliminar_producto(%s)$$, current_setting('prueba.coca')), 'Producto no encontrado', 'B no borra productos de A');
select pruebas.ok(public.guardar_producto('{"nombre": "Coca de B", "codigo": "7790001", "precio": "900"}') ->> 'codigo' = '7790001',
  'otro negocio puede usar el mismo código');
select set_config('prueba.coca_b', (public.catalogo() -> 'productos' -> 0 ->> 'id'), false);

select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select pruebas.ok(jsonb_array_length(public.catalogo() -> 'productos') = 3, 'el empleado ve el catálogo');
select pruebas.ok(not (public.catalogo() -> 'productos' -> 0 ? 'costo'), 'el empleado no ve los costos');
select pruebas.falla($$select public.guardar_producto('{"nombre": "X"}')$$, 'solo lo puede hacer el dueño', 'el empleado no crea productos');
select pruebas.falla(format($$select public.ajustar_stock(%s, 0)$$, current_setting('prueba.coca')), 'solo lo puede hacer el dueño', 'el empleado no ajusta stock');
select pruebas.falla($$select public.guardar_categoria(null, 'Y')$$, 'solo lo puede hacer el dueño', 'el empleado no crea categorías');
select pruebas.falla('select * from public.productos', 'permission denied', 'nadie lee la tabla productos directo');
select pruebas.falla('select * from public.ventas', 'permission denied', 'nadie lee la tabla ventas directo');
select pruebas.falla('select * from public.caja', 'permission denied', 'nadie lee la tabla caja directo');

-- ---------------------------------------------------------------------
\echo == Turno y venta
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "monto": 1000}]')$$,
  current_setting('prueba.coca')), 'La caja está cerrada', 'sin turno no se vende');
select public.abrir_turno(1000);
select pruebas.falla('select public.abrir_turno(0)', 'Ya hay un turno abierto', 'un solo turno abierto por negocio');
select set_config('prueba.clave', gen_random_uuid()::text, false);
select set_config('prueba.v1', public.registrar_venta(current_setting('prueba.clave')::uuid,
  jsonb_build_array(
    jsonb_build_object('producto_id', current_setting('prueba.coca'), 'cantidad', 2),
    jsonb_build_object('producto_id', current_setting('prueba.queso'), 'cantidad', '0,5'),
    jsonb_build_object('nombre', 'Carga SUBE', 'importe', 300)),
  '[{"forma": "Efectivo", "monto": 5000}, {"forma": "Débito", "monto": 1300}]', 10000)::text, false);
select pruebas.ok((current_setting('prueba.v1')::jsonb ->> 'total')::numeric = 6300, 'sin precio en el renglón, cobra el precio del producto');
select pruebas.ok((current_setting('prueba.v1')::jsonb ->> 'numero')::int = 1, 'la primera venta del negocio es la 1');
select pruebas.ok(not (current_setting('prueba.v1')::jsonb -> 'items' -> 0 ? 'costo'), 'la venta no muestra costos');
select pruebas.ok((public.registrar_venta(current_setting('prueba.clave')::uuid, '[{"nombre": "x", "importe": 1}]', '[{"forma": "Efectivo", "monto": 1}]')
  ->> 'id') = current_setting('prueba.v1')::jsonb ->> 'id', 'con la misma clave no se registra dos veces');
select pruebas.ok((select (p ->> 'stock')::numeric from jsonb_array_elements(public.catalogo() -> 'productos') p
  where (p ->> 'id') = current_setting('prueba.coca')) = 8, 'descuenta el stock una sola vez');
select pruebas.ok((select (p ->> 'stock')::numeric from jsonb_array_elements(public.catalogo() -> 'productos') p
  where (p ->> 'id') = current_setting('prueba.queso')) = 4.5, 'los productos por peso aceptan decimales');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1.5}]', '[{"forma": "Efectivo", "monto": 1500}]')$$,
  current_setting('prueba.coca')), 'tiene que ser entera', 'un producto por unidad no acepta decimales');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "monto": 999}]')$$,
  current_setting('prueba.coca')), 'no suman el total', 'los pagos tienen que sumar el total');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Bitcoin", "monto": 1000}]')$$,
  current_setting('prueba.coca')), 'Forma de pago inválida', 'solo formas de pago del negocio');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "monto": 900}]')$$,
  current_setting('prueba.coca_b')), 'Producto no encontrado', 'no se puede vender un producto de otro negocio');
select pruebas.falla('select public.anular_venta(1)', 'solo lo puede hacer el dueño', 'el empleado no anula ventas');

\echo == Caja del turno
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = 6000, 'efectivo esperado = inicial + ventas en efectivo');
select pruebas.ok((public.estado_caja() -> 'por_forma' ->> 'Débito')::numeric = 1300, 'totales por forma de pago');
select public.movimiento_caja('egreso', 'Pago al plomero', 500, 'Efectivo');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = 5500, 'los egresos bajan el efectivo esperado');
select pruebas.falla($$select public.movimiento_caja('egreso', '', 10, 'Efectivo')$$, 'Escribí el motivo', 'un movimiento lleva motivo');

select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_teo'));
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "monto": 1000}]')$$,
  current_setting('prueba.coca')), 'El turno abierto es de Eva', 'otro empleado no vende en el turno de Eva');
select pruebas.falla('select public.cerrar_turno(0)', 'Solo quien abrió el turno', 'otro empleado no cierra el turno de Eva');

\echo == El otro negocio no ve ni toca la venta
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.t_beto'));
select pruebas.ok(jsonb_typeof(public.estado_caja() -> 'turno') = 'null', 'B no ve el turno de A');
select public.abrir_turno(0);
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.coca_b'))::jsonb,
  '[{"forma": "Efectivo", "monto": 900}]') ->> 'numero')::int = 1, 'cada negocio numera sus ventas desde 1');
select pruebas.falla(format('select public.venta(%s)', current_setting('prueba.v1')::jsonb ->> 'id'), 'Venta no encontrada', 'B no ve una venta de A');
select pruebas.falla(format('select public.anular_venta(%s)', current_setting('prueba.v1')::jsonb ->> 'id'), 'Venta no encontrada', 'B no anula una venta de A');

\echo == Anular (Ana)
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select public.anular_venta((current_setting('prueba.v1')::jsonb ->> 'id')::bigint, 'Prueba');
select pruebas.ok((select (p ->> 'stock')::numeric from jsonb_array_elements(public.catalogo() -> 'productos') p
  where (p ->> 'id') = current_setting('prueba.coca')) = 10, 'anular devuelve el stock');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = 500, 'anular saca la plata de la caja');
select pruebas.ok((public.estado_caja() -> 'por_forma' ->> 'Débito')::numeric = 0, 'también la de débito');
select pruebas.falla(format('select public.anular_venta(%s)', current_setting('prueba.v1')::jsonb ->> 'id'), 'ya estaba anulada', 'no se anula dos veces');

\echo == Cerrar el turno (Eva)
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select pruebas.falla('select public.cerrar_turno(100, 200)', 'El retiro no puede ser mayor', 'el retiro no supera lo contado');
select pruebas.ok((public.cerrar_turno(450, 100) ->> 'diferencia')::numeric = -50, 'al cerrar calcula la diferencia');
select pruebas.ok(jsonb_typeof(public.estado_caja() -> 'turno') = 'null', 'después de cerrar no hay turno abierto');

\echo == Bajas
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(public.eliminar_producto(current_setting('prueba.coca')::bigint) ? 'desactivado', 'un producto vendido se da de baja, no se borra');
select pruebas.ok(public.eliminar_producto(current_setting('prueba.chicle')::bigint) ? 'eliminado', 'uno sin ventas se borra');
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.catalogo() -> 'productos') p where (p ->> 'id') = current_setting('prueba.coca')),
  'el dado de baja no está en el catálogo completo');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.catalogo(now() - interval '1 hour') -> 'productos') p
  where (p ->> 'id') = current_setting('prueba.coca') and (p ->> 'activo')::boolean = false), 'pero sí en la actualización, para sacarlo');
select public.abrir_turno(0);
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "monto": 1000}]')$$,
  current_setting('prueba.coca')), 'dado de baja', 'no se vende un producto dado de baja');
select pruebas.falla(format('select public.eliminar_categoria(%s)', current_setting('prueba.cat')), 'tiene 1 producto', 'no se borra una categoría con productos');

\echo == Sin sesión
reset role;
set local role anon;
select pruebas.como(null);
select pruebas.falla('select public.catalogo()', 'permission denied', 'anon no ve el catálogo');
select pruebas.falla($$select public.registrar_venta(gen_random_uuid(), '[]', '[]')$$, 'permission denied', 'anon no vende');
reset role;

\echo == Todas las pruebas de productos, caja y ventas dieron bien
