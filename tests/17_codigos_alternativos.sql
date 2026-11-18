-- =====================================================================
-- Pruebas: varios códigos de barras por producto. Usa el negocio C (07 a 16): Carla (dueña), Cami (empleada) y el
-- proveedor Aceitera del Sur (prueba.pa, de la 12).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.gd', public.guardar_producto('{"nombre": "Galletitas Dulces", "codigo": "7790000000017", "precio": 900}') ->> 'id', false);
select set_config('prueba.sc', public.guardar_producto('{"nombre": "Sal fina", "precio": 700}') ->> 'id', false);
select set_config('prueba.mt', public.guardar_producto('{"nombre": "Mate cocido", "codigo": "7790000000055", "precio": 1100}') ->> 'id', false);

\echo == Agregar códigos
select pruebas.ok(public.agregar_codigo(current_setting('prueba.gd')::bigint, ' 7790000000024 ') -> 'codigos' = '["7790000000024"]'::jsonb,
  'un producto con código suma otro (el envase nuevo)');
select pruebas.ok(pruebas.prod(current_setting('prueba.gd')) ->> 'codigo' = '7790000000017'
  and pruebas.prod(current_setting('prueba.gd')) -> 'codigos' = '["7790000000024"]'::jsonb, 'el catálogo trae el principal y los otros');
select pruebas.ok(public.agregar_codigo(current_setting('prueba.sc')::bigint, '7790000000048') ->> 'codigo' = '7790000000048', 'sin código: queda como el principal');
select pruebas.falla(format($$select public.agregar_codigo(%s, '7790000000024')$$, current_setting('prueba.mt')), 'ya lo tiene "Galletitas Dulces"',
  'un código de otro producto no se repite');
select pruebas.falla(format($$select public.agregar_codigo(%s, '7790000000017')$$, current_setting('prueba.mt')), 'ya lo tiene "Galletitas Dulces"',
  'tampoco el principal de otro');
select pruebas.falla(format($$select public.agregar_codigo(%s, '7790000000024')$$, current_setting('prueba.gd')), 'ya es de', 'ni dos veces en el mismo');
select pruebas.falla(format($$select public.agregar_codigo(%s, 'con espacio')$$, current_setting('prueba.gd')), 'sin espacios', 'sin espacios');
select pruebas.falla(format($$select public.guardar_producto(jsonb_build_object('id', %s, 'nombre', 'Mate cocido', 'codigo', '7790000000024', 'precio', 1100))$$,
  current_setting('prueba.mt')), 'ya lo tiene "Galletitas Dulces"', 'la ficha no pone como principal un código que es de otro');

\echo == Leer facturas con el otro código
select pruebas.ok((public.preparar_factura(jsonb_build_object('factura', jsonb_build_object('proveedor', jsonb_build_object('nombre', 'Otro', 'cuit', null),
  'items', jsonb_build_array(jsonb_build_object('codigo', 'X1', 'codigo_barras', '7790000000024', 'descripcion', 'GALLETITAS DULCES NUEVAS', 'cantidad', 1,
    'unidad', 'unidad', 'importe', 500))))) #>> '{lineas,0,producto_id}') = current_setting('prueba.gd'), 'la factura lo reconoce por el otro código');
select public.registrar_compra_factura(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000017',
  'lineas', jsonb_build_array(
    jsonb_build_object('producto_id', current_setting('prueba.mt')::bigint, 'codigo_barras', '7790000000062', 'descripcion', 'MATE COCIDO NUEVO', 'unidades', 1, 'cantidad', 2, 'costo', 600),
    jsonb_build_object('producto_id', current_setting('prueba.sc')::bigint, 'codigo_barras', '7790000000048', 'descripcion', 'SAL FINA', 'unidades', 1, 'cantidad', 2, 'costo', 300))));
select pruebas.ok(pruebas.prod(current_setting('prueba.mt')) -> 'codigos' = '["7790000000062"]'::jsonb
  and pruebas.prod(current_setting('prueba.mt')) ->> 'codigo' = '7790000000055', 'un código nuevo de la factura queda como otro código');
select pruebas.ok(pruebas.prod(current_setting('prueba.sc')) -> 'codigos' = '[]'::jsonb, 'el que ya era suyo no se duplica');

\echo == Cambiar el principal y quitar
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.mt'), 'nombre', 'Mate cocido', 'codigo', '7790000000062', 'precio', 1100));
select pruebas.ok(pruebas.prod(current_setting('prueba.mt')) ->> 'codigo' = '7790000000062' and pruebas.prod(current_setting('prueba.mt')) -> 'codigos' = '[]'::jsonb,
  'si un otro código pasa a ser el principal, sale de la lista de otros');
select pruebas.ok(public.quitar_codigo(current_setting('prueba.gd')::bigint, '7790000000024') -> 'codigos' = '[]'::jsonb, 'se quita un otro código');
select pruebas.falla(format($$select public.quitar_codigo(%s, '7790000000024')$$, current_setting('prueba.gd')), 'no está entre', 'quitar uno que no está');
select pruebas.ok(public.agregar_codigo(current_setting('prueba.mt')::bigint, '7790000000024') -> 'codigos' = '["7790000000024"]'::jsonb,
  'el código quitado queda libre para otro producto');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla(format($$select public.agregar_codigo(%s, '7790000000079')$$, current_setting('prueba.gd')), 'solo lo puede hacer el dueño', 'el empleado no agrega códigos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format($$select public.agregar_codigo(%s, '7790000000079')$$, current_setting('prueba.gd')), 'Producto no encontrado', 'A no toca productos de C');
select pruebas.ok(public.guardar_producto('{"nombre": "Galletitas de A", "codigo": "7790000000024", "precio": 500}') ->> 'codigo' = '7790000000024',
  'otro negocio puede usar el mismo código');
select pruebas.falla('select * from public.producto_codigos', 'permission denied', 'nadie lee la tabla producto_codigos directo');
reset role;

\echo == Todas las pruebas de códigos alternativos dieron bien
