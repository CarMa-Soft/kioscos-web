-- =====================================================================
-- Pruebas: precios y márgenes (margen automático, actualizar en bloque, deshacer). Usa el negocio C (07 a 19): Carla
-- (dueña), Cami (empleada) y el proveedor Aceitera del Sur (prueba.pa).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select public.guardar_redondeo(10);
select set_config('prueba.ma', public.guardar_producto('{"nombre": "Mermelada", "costo": 1000, "precio": 1500}') ->> 'id', false);
select set_config('prueba.mb', public.guardar_producto('{"nombre": "Dulce de leche", "costo": 2000, "precio": 2600}') ->> 'id', false);
select set_config('prueba.mc', public.guardar_producto('{"nombre": "Miel", "costo": 500, "precio": 900}') ->> 'id', false);
select set_config('prueba.md', public.guardar_producto('{"nombre": "Sin costo", "precio": 300}') ->> 'id', false);

\echo == Asignar margen
select set_config('prueba.aj1', public.ajustar_precios(jsonb_build_object('que', 'margen', 'margen', 40, 'descripcion', 'Margen 40%',
  'ids', jsonb_build_array(current_setting('prueba.ma')::bigint, current_setting('prueba.mb')::bigint, current_setting('prueba.md')::bigint)))::text, false);
select pruebas.ok((current_setting('prueba.aj1')::jsonb ->> 'cantidad')::int = 2 and (current_setting('prueba.aj1')::jsonb ->> 'saltados')::int = 1,
  'a 2 productos; el que no tiene costo queda igual');
select pruebas.ok((pruebas.prod(current_setting('prueba.ma')) ->> 'precio')::numeric = 1400 and (pruebas.prod(current_setting('prueba.ma')) ->> 'margen')::numeric = 40
  and (pruebas.prod(current_setting('prueba.mb')) ->> 'precio')::numeric = 2800, 'el precio es costo + 40% y queda el margen');

\echo == El precio sigue al costo
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.ma'), 'nombre', 'Mermelada', 'costo', 1100, 'precio', 1400));
select pruebas.ok((pruebas.prod(current_setting('prueba.ma')) ->> 'precio')::numeric = 1540, 'cambiar el costo en la ficha recalcula el precio (1100 + 40%)');
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000020',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.mb'), 'cantidad', 2, 'costo', 2105))));
select pruebas.ok((pruebas.prod(current_setting('prueba.mb')) ->> 'precio')::numeric = 2950, 'una compra con costo nuevo también (2105 + 40% = 2947 → 2950)');
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.mc'), 'nombre', 'Miel', 'costo', 600, 'precio', 900));
select pruebas.ok((pruebas.prod(current_setting('prueba.mc')) ->> 'precio')::numeric = 900, 'el de precio fijo no cambia con el costo');

\echo == Actualizar el precio de venta: solo los de precio fijo
select set_config('prueba.aj2', public.ajustar_precios(jsonb_build_object('que', 'venta', 'modo', 'pct', 'valor', 10, 'redondeo', 50,
  'ids', jsonb_build_array(current_setting('prueba.ma')::bigint, current_setting('prueba.mc')::bigint)))::text, false);
select pruebas.ok((current_setting('prueba.aj2')::jsonb ->> 'cantidad')::int = 1 and (pruebas.prod(current_setting('prueba.mc')) ->> 'precio')::numeric = 1000
  and (pruebas.prod(current_setting('prueba.ma')) ->> 'precio')::numeric = 1540, 'el fijo sube (990 → 1000 redondeando a 50); el de margen no se toca');

\echo == Actualizar el costo: los de margen recalculan, los fijos mantienen el precio
select public.ajustar_precios(jsonb_build_object('que', 'costo', 'modo', 'pct', 'valor', 10,
  'ids', jsonb_build_array(current_setting('prueba.ma')::bigint, current_setting('prueba.mc')::bigint)));
select pruebas.ok((pruebas.prod(current_setting('prueba.ma')) ->> 'costo')::numeric = 1210 and (pruebas.prod(current_setting('prueba.ma')) ->> 'precio')::numeric = 1700
  and (pruebas.prod(current_setting('prueba.mc')) ->> 'costo')::numeric = 660 and (pruebas.prod(current_setting('prueba.mc')) ->> 'precio')::numeric = 1000,
  'Mermelada: costo 1210 y precio 1694 → 1700; Miel: costo 660 y el precio igual');

\echo == Quitar el margen y deshacer
select set_config('prueba.aj3', public.ajustar_precios(jsonb_build_object('que', 'margen', 'margen', null,
  'ids', jsonb_build_array(current_setting('prueba.ma')::bigint))) ->> 'id', false);
select pruebas.ok(pruebas.prod(current_setting('prueba.ma')) -> 'margen' = 'null'::jsonb and (pruebas.prod(current_setting('prueba.ma')) ->> 'precio')::numeric = 1700,
  'sin margen queda con su precio, ahora fijo');
select public.deshacer_aumento(current_setting('prueba.aj3')::bigint);
select pruebas.ok((pruebas.prod(current_setting('prueba.ma')) ->> 'margen')::numeric = 40, 'deshacer devuelve el margen');

\echo == Margen desde la ficha
select pruebas.ok((public.margen_producto(current_setting('prueba.mc')::bigint, 25) ->> 'margen')::numeric = 25
  and (pruebas.prod(current_setting('prueba.mc')) ->> 'precio')::numeric = 1000, 'se fija el margen sin cambiar el precio');
select public.margen_producto(current_setting('prueba.mc')::bigint, null);
select pruebas.ok(pruebas.prod(current_setting('prueba.mc')) -> 'margen' = 'null'::jsonb, 'y se quita');

\echo == Controles
select pruebas.falla(format($$select public.ajustar_precios('{"que": "venta", "modo": "pct", "valor": 0, "ids": [%s]}')$$, current_setting('prueba.mc')), 'cuánto se cambia', 'sin valor');
select pruebas.falla(format($$select public.ajustar_precios('{"que": "venta", "modo": "pct", "valor": -95, "ids": [%s]}')$$, current_setting('prueba.mc')), 'entre -90 y 500', 'porcentaje fuera de rango');
select pruebas.falla(format($$select public.ajustar_precios('{"que": "margen", "margen": 2000, "ids": [%s]}')$$, current_setting('prueba.mc')), 'entre 0 y 1000', 'margen fuera de rango');
select pruebas.falla($$select public.ajustar_precios('{"que": "venta", "modo": "pct", "valor": 5, "ids": []}')$$, 'No hay productos', 'sin productos');
select pruebas.falla(format($$select public.ajustar_precios('{"que": "venta", "modo": "pct", "valor": 5, "ids": [%s]}')$$, current_setting('prueba.ma')), 'Ninguno', 'nada que cambiar');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla(format($$select public.ajustar_precios('{"que": "venta", "modo": "pct", "valor": 5, "ids": [%s]}')$$, current_setting('prueba.mc')), 'solo lo puede hacer el dueño', 'el empleado no cambia precios');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format($$select public.ajustar_precios('{"que": "venta", "modo": "pct", "valor": 5, "ids": [%s]}')$$, current_setting('prueba.mc')), 'Ninguno', 'A no cambia productos de C');
select pruebas.falla(format('select public.margen_producto(%s, 30)', current_setting('prueba.mc')), 'Producto no encontrado', 'A no pone márgenes en C');
reset role;

\echo == Todas las pruebas de precios y márgenes dieron bien
