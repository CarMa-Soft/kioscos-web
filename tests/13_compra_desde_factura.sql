-- =====================================================================
-- Pruebas: compra desde la factura leída con IA (etapa 8a). Usa el negocio C (07 a 12): Carla (dueña), Cami (empleada), Yerba (p1).
-- La lectura en sí la hace la función de Supabase "leer-factura" (no se prueba acá): se prueba el permiso, el consumo,
-- reconocer proveedor y productos, y guardar la compra.
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.sy', pruebas.prod(current_setting('prueba.p1')) ->> 'stock', false);
select set_config('prueba.fac', jsonb_build_object(
  'proveedor', jsonb_build_object('nombre', 'VALLEVERDE LÁCTEOS S.A.', 'cuit', null), 'comprobante', 'A 0005-00001234', 'fecha', '2026-11-10', 'vencimiento', '',
  'items', jsonb_build_array(
    jsonb_build_object('codigo', 'L01', 'codigo_barras', '7790001112223', 'descripcion', 'LECHE ENTERA X 1LT', 'cantidad', 2, 'unidad', 'bulto',
                       'unidades_por_bulto', 12, 'precio_unitario', 9600, 'bonificacion', null, 'importe', 19200, 'alicuota_iva', 21, 'precio_sugerido', null),
    jsonb_build_object('codigo', 'Y9', 'codigo_barras', '', 'descripcion', 'YERBA MATE SUAVE 1KG', 'cantidad', 3, 'unidad', 'unidad',
                       'unidades_por_bulto', null, 'precio_unitario', 900, 'bonificacion', null, 'importe', 2700, 'alicuota_iva', 21, 'precio_sugerido', null)),
  'descuento_global', null, 'otros_cargos', null, 'subtotal', 21900, 'iva', 4599, 'percepciones', null, 'total', 26499, 'observaciones', null)::text, false);

\echo == Margen
select pruebas.ok(public.guardar_margen(35) = 35, 'guarda el margen');
select pruebas.falla('select public.guardar_margen(-1)', 'entre 0 y 1000', 'margen negativo');

\echo == Reconocer una factura nueva
select set_config('prueba.prep', public.preparar_factura(jsonb_build_object('factura', current_setting('prueba.fac')::jsonb))::text, false);
select pruebas.ok(current_setting('prueba.prep')::jsonb -> 'proveedor' = 'null'::jsonb and (current_setting('prueba.prep')::jsonb ->> 'margen')::numeric = 35,
  'proveedor desconocido; trae el margen');
select pruebas.ok(current_setting('prueba.prep')::jsonb #> '{lineas,0,producto_id}' = 'null'::jsonb, 'la leche no se conoce');
select pruebas.ok(current_setting('prueba.prep')::jsonb #> '{lineas,1,sugerencias}' @> jsonb_build_array(jsonb_build_object('id', current_setting('prueba.p1')::bigint)),
  'para la yerba propone el producto Yerba');
select pruebas.falla($$select public.preparar_factura('{"factura": {}}')$$, 'no tiene renglones', 'factura sin renglones');

\echo == Guardar la compra
select set_config('prueba.cf', public.registrar_compra_factura(jsonb_build_object(
  'proveedor_nuevo', jsonb_build_object('nombre', 'Valleverde Lácteos', 'cuit', ''), 'comprobante', 'A 0005-00001234', 'total', 26499,
  'fecha_factura', '2026-11-10', 'notas', 'cargada desde la factura',
  'lineas', jsonb_build_array(
    jsonb_build_object('nuevo', jsonb_build_object('nombre', 'Leche entera 1 L', 'categoria_id', null, 'por_peso', false, 'precio', 1200),
      'codigo', 'L01', 'codigo_barras', '7790001112223', 'descripcion', 'LECHE ENTERA X 1LT', 'unidades', 12, 'cantidad', 24, 'costo', 968, 'precio_nuevo', 1200),
    jsonb_build_object('producto_id', current_setting('prueba.p1')::bigint, 'codigo', 'Y9', 'descripcion', 'YERBA MATE SUAVE 1KG',
      'unidades', 1, 'cantidad', 3, 'costo', 1089, 'precio_nuevo', ''))))::text, false);
select set_config('prueba.leche', current_setting('prueba.cf')::jsonb -> 'productos' ->> 0, false);
select pruebas.ok((current_setting('prueba.cf')::jsonb ->> 'creados')::int = 1 and (current_setting('prueba.cf')::jsonb ->> 'total')::numeric = 26499,
  'crea el producto nuevo y la compra con el total de la factura');
select pruebas.ok(pruebas.prod(current_setting('prueba.leche')) ->> 'codigo' = '7790001112223' and (pruebas.prod(current_setting('prueba.leche')) ->> 'stock')::numeric = 24
  and (pruebas.prod(current_setting('prueba.leche')) ->> 'precio')::numeric = 1200 and (pruebas.prod(current_setting('prueba.leche')) ->> 'costo')::numeric = 968,
  'la leche entra con su código de barras, 24 unidades, costo y precio');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.sy')::numeric + 3, 'la yerba suma 3');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.proveedores()) x where x ->> 'nombre' = 'Valleverde Lácteos'), 'crea el proveedor');

\echo == La próxima factura del mismo proveedor se reconoce sola
select set_config('prueba.prep', public.preparar_factura(jsonb_build_object('factura', current_setting('prueba.fac')::jsonb))::text, false);
select pruebas.ok(current_setting('prueba.prep')::jsonb #>> '{proveedor,id}' = (current_setting('prueba.cf')::jsonb ->> 'proveedor_id'),
  'reconoce al proveedor por el nombre');
select pruebas.ok((current_setting('prueba.prep')::jsonb #>> '{lineas,0,producto_id}') = current_setting('prueba.leche')
  and (current_setting('prueba.prep')::jsonb #>> '{lineas,0,unidades}')::numeric = 12, 'la leche por el código de barras, con 12 unidades por bulto');
select pruebas.ok((current_setting('prueba.prep')::jsonb #>> '{lineas,1,producto_id}') = current_setting('prueba.p1'), 'la yerba por el código del proveedor');

\echo == Controles
select pruebas.falla($$select public.registrar_compra_factura('{"proveedor_nuevo": {"nombre": "X"}, "lineas": [{"descripcion": "ALGO", "cantidad": 1, "costo": 1}]}')$$,
  'Falta elegir qué producto', 'renglón sin producto');
select pruebas.falla($$select public.registrar_compra_factura('{"lineas": [{"nuevo": {"nombre": "Algo"}, "cantidad": 1, "costo": 1}]}')$$,
  'Elegí el proveedor', 'sin proveedor');
select pruebas.falla($$select public.registrar_compra_factura('{"proveedor_nuevo": {"nombre": "X", "cuit": "20-12345678-5"}, "lineas": [{"nuevo": {"nombre": "Algo"}, "cantidad": 1, "costo": 1}]}')$$,
  'no es válido', 'CUIT inválido');

\echo == Permiso y consumo de la IA
select set_config('prueba.neg_c', public.permiso_lectura_ia() ->> 'negocio_id', false);
select pruebas.ok((public.uso_ia() #>> '{mes,lecturas}')::int = 0, 'todavía no hay lecturas');
select pruebas.falla(format($$select public.anotar_lectura_ia('%s', null, '{}')$$, current_setting('prueba.neg_c')), 'permission denied', 'el navegador no puede anotar lecturas');
reset role;
-- lo que hace la función de Supabase con la clave de servicio
select public.anotar_lectura_ia(current_setting('prueba.neg_c')::uuid, null, '{"modelo": "claude-opus-5-5", "tokens_entrada": 3000, "tokens_salida": 900, "costo_usd": 0.03, "resultado": "2 renglones"}');
set local role authenticated;
select pruebas.ok((public.uso_ia() #>> '{mes,lecturas}')::int = 1 and (public.uso_ia() #>> '{mes,costo_usd}')::numeric = 0.03
  and public.uso_ia() #>> '{ultimas,0,resultado}' = '2 renglones', 'el consumo del mes');
reset role;
insert into public.lecturas_ia (negocio_id) select current_setting('prueba.neg_c')::uuid from generate_series(1, 59);
set local role authenticated;
select pruebas.falla('select public.permiso_lectura_ia()', '60 facturas', 'hasta 60 lecturas por día');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla('select public.permiso_lectura_ia()', 'solo lo puede hacer el dueño', 'el empleado no lee facturas con IA');
select pruebas.falla(format($$select public.preparar_factura('{"factura": %s}')$$, current_setting('prueba.fac')), 'solo lo puede hacer el dueño', 'ni prepara facturas');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(public.preparar_factura(jsonb_build_object('factura', current_setting('prueba.fac')::jsonb,
  'proveedor_id', current_setting('prueba.cf')::jsonb ->> 'proveedor_id')) -> 'proveedor' = 'null'::jsonb, 'A no usa proveedores de C');
select pruebas.ok((public.uso_ia() #>> '{total,lecturas}')::int = 0, 'A no ve el consumo de C');
select pruebas.falla('select * from public.lecturas_ia', 'permission denied', 'nadie lee la tabla lecturas_ia directo');
reset role;

\echo == Todas las pruebas de compra desde factura dieron bien
