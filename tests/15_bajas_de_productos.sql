-- =====================================================================
-- Pruebas: botón rápido, dar de baja y eliminar productos. Usa el negocio C (07 a 14): Carla (dueña) y Cami (empleada).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == Botón rápido (favorito)
select set_config('prueba.pan', public.guardar_producto('{"nombre": "Pan francés", "precio": 2800, "por_peso": true, "favorito": true}') ->> 'id', false);
select pruebas.ok((pruebas.prod(current_setting('prueba.pan')) ->> 'favorito')::boolean, 'se guarda como botón rápido');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.catalogo() -> 'productos') x
                          where (x ->> 'id')::bigint = current_setting('prueba.pan')::bigint and (x ->> 'favorito')::boolean),
  'el catálogo lo trae marcado');
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.pan'), 'nombre', 'Pan francés', 'precio', 2800, 'favorito', false));
select pruebas.ok(not (pruebas.prod(current_setting('prueba.pan')) ->> 'favorito')::boolean, 'se puede sacar');

\echo == Desactivar y volver a activar
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.pan'), 'nombre', 'Pan francés', 'precio', 2800, 'activo', false));
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.catalogo() -> 'productos') x
                              where (x ->> 'id')::bigint = current_setting('prueba.pan')::bigint),
  'el catálogo completo (el de Vender) no trae los dados de baja');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.productos_de_baja()) x
                          where (x ->> 'id')::bigint = current_setting('prueba.pan')::bigint and x ? 'costo'),
  'productos_de_baja los trae, con costo');
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.productos_de_baja()) x where (x ->> 'activo')::boolean),
  'productos_de_baja no trae activos');
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.pan'), 'nombre', 'Pan francés', 'precio', 2800, 'activo', true));
select pruebas.ok((pruebas.prod(current_setting('prueba.pan')) ->> 'activo')::boolean
  and not exists (select 1 from jsonb_array_elements(public.productos_de_baja()) x where (x ->> 'id')::bigint = current_setting('prueba.pan')::bigint),
  'se vuelve a activar');

\echo == Eliminar: solo si no tiene movimientos
select set_config('prueba.err', public.guardar_producto('{"nombre": "Cargado por error", "precio": 10, "stock": 5}') ->> 'id', false);
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.err'), 'nombre', 'Cargado por error', 'precio', 10, 'stock', 7));
select pruebas.ok(public.eliminar_producto(current_setting('prueba.err')::bigint) ? 'eliminado',
  'con solo "Stock inicial" y "Corrección desde la ficha" se borra');
select pruebas.ok(pruebas.prod(current_setting('prueba.err')) is null
  and not exists (select 1 from jsonb_array_elements(public.productos_de_baja()) x where (x ->> 'id')::bigint = current_setting('prueba.err')::bigint),
  'y ya no está, ni entre los dados de baja');

select set_config('prueba.aju', public.guardar_producto('{"nombre": "Con ajuste", "precio": 10}') ->> 'id', false);
select public.ajustar_stock(current_setting('prueba.aju')::bigint, 3, 'Conteo');
select pruebas.ok(public.eliminar_producto(current_setting('prueba.aju')::bigint) ? 'desactivado', 'con un ajuste de stock se da de baja');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.productos_de_baja()) x where (x ->> 'id')::bigint = current_setting('prueba.aju')::bigint),
  'queda entre los dados de baja');
reset role;   -- las tablas no se leen con el rol de la app: se controla como dueño de la base
select pruebas.ok(exists (select 1 from public.movimientos_stock where producto_id = current_setting('prueba.aju')::bigint), 'se conserva su movimiento');
set local role authenticated;

select set_config('prueba.com', public.guardar_producto('{"nombre": "Comprado", "precio": 10}') ->> 'id', false);
select set_config('prueba.pcom', public.guardar_proveedor('{"nombre": "Proveedor de bajas"}') ->> 'id', false);
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pcom'), 'comprobante', 'A 0001-00001500',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.com'), 'cantidad', 2, 'costo', 5))));
select pruebas.ok(public.eliminar_producto(current_setting('prueba.com')::bigint) ? 'desactivado', 'con una compra se da de baja (antes daba error)');
reset role;
select pruebas.ok(exists (select 1 from public.compra_items where producto_id = current_setting('prueba.com')::bigint)
  and exists (select 1 from public.movimientos_stock where producto_id = current_setting('prueba.com')::bigint),
  'se conservan la compra y su movimiento de stock');
set local role authenticated;

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.productos_de_baja()$$, 'solo lo puede hacer el dueño', 'el empleado no ve los dados de baja');
select pruebas.falla(format('select public.eliminar_producto(%s)', current_setting('prueba.pan')), 'solo lo puede hacer el dueño', 'el empleado no elimina productos');
select pruebas.falla(format('select public.producto_con_movimientos(%s)', current_setting('prueba.pan')), 'permission denied', 'nadie llama directo a producto_con_movimientos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.productos_de_baja()) x
                              where (x ->> 'id')::bigint in (current_setting('prueba.aju')::bigint, current_setting('prueba.com')::bigint)),
  'A no ve los dados de baja de C');
select pruebas.falla(format('select public.eliminar_producto(%s)', current_setting('prueba.pan')), 'Producto no encontrado', 'A no elimina productos de C');
reset role;

\echo == Todas las pruebas de bajas de productos dieron bien
