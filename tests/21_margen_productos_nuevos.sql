-- =====================================================================
-- Pruebas: los productos nuevos de una factura quedan con el margen automático de la configuración. Usa el negocio C
-- (07 a 20): Carla y el proveedor Aceitera del Sur (prueba.pa).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select public.guardar_margen(30);
select set_config('prueba.f21', public.registrar_compra_factura(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000021',
  'lineas', jsonb_build_array(jsonb_build_object('nuevo', jsonb_build_object('nombre', 'Mostaza nueva', 'precio', 1350),
    'descripcion', 'MOSTAZA', 'unidades', 1, 'cantidad', 4, 'costo', 1000, 'precio_nuevo', 1350)))) -> 'productos' ->> 0, false);
select pruebas.ok((pruebas.prod(current_setting('prueba.f21')) ->> 'margen')::numeric = 30 and (pruebas.prod(current_setting('prueba.f21')) ->> 'precio')::numeric = 1350,
  'el producto nuevo queda con margen automático 30% y el precio que se eligió');
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000022',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.f21'), 'cantidad', 1, 'costo', 1200))));
select pruebas.ok((pruebas.prod(current_setting('prueba.f21')) ->> 'precio')::numeric = 1560, 'en la compra siguiente el precio sigue al costo (1200 + 30%)');
select public.guardar_margen(0);
select set_config('prueba.f22', public.registrar_compra_factura(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000023',
  'lineas', jsonb_build_array(jsonb_build_object('nuevo', jsonb_build_object('nombre', 'Ketchup nuevo', 'precio', 900),
    'descripcion', 'KETCHUP', 'unidades', 1, 'cantidad', 2, 'costo', 600, 'precio_nuevo', 900)))) -> 'productos' ->> 0, false);
select pruebas.ok(pruebas.prod(current_setting('prueba.f22')) -> 'margen' = 'null'::jsonb, 'con margen 0 en la configuración, el nuevo queda con precio fijo');
reset role;

\echo == Todas las pruebas de margen para productos nuevos dieron bien
