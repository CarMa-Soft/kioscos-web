-- =====================================================================
-- Pruebas: catálogo general (compartido) y marca/contenido en los productos. Negocio C: Carla (dueña) y Cami (empleada).
-- =====================================================================
-- productos inventados (los reales los carga la migración de datos)
insert into public.catalogo_general (codigo, nombre, marca, contenido, unidad, precio_ref, cadenas) values
  ('99990000000017', 'YERBA PRUEBA ÑANDÚ SUAVE 500 GRM', 'ÑANDÚ', 500, 'g', 3600, 4),
  ('99990000000024', 'YERBA PRUEBA ÑANDÚ COMPUESTA 1 KG', 'ÑANDÚ', 1, 'kg', 6000, 2),
  ('0999888777665', 'GASEOSA PRUEBA UPC 354 ML', 'PRUEBA', 354, 'ml', 900, 1);
set local role authenticated;

\echo == Buscar (cualquier usuario)
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok((select array_agg(x ->> 'codigo' order by x ->> 'codigo') from jsonb_array_elements(public.catalogo_general_buscar('yerba nandu prueba')) x)
  = array['99990000000017', '99990000000024'], 'por palabras, sin acentos ni mayúsculas');
select pruebas.ok(public.catalogo_general_buscar('yerba nandu prueba') -> 0 ->> 'codigo' = '99990000000017', 'primero el que está en más cadenas');
select pruebas.ok(public.catalogo_general_buscar('999888777665') -> 0 ->> 'nombre' = 'GASEOSA PRUEBA UPC 354 ML', 'un UPC leído sin el 0 de adelante');
select pruebas.ok(jsonb_array_length(public.catalogo_general_buscar('x')) = 0, 'una letra sola no busca');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"codigo": "99990000000017", "precio": 4000}]')$$, 'dueño', 'el empleado no agrega');

\echo == Agregar desde el catálogo general (el dueño)
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.ag', public.agregar_desde_catalogo('[{"codigo": "99990000000017", "precio": 4000, "costo": 2800}, {"codigo": "0999888777665", "precio": 1000}]')::text, false);
select pruebas.ok((current_setting('prueba.ag')::jsonb ->> 'creados')::int = 2, 'crea los dos');
select pruebas.ok((select x ->> 'nombre' = 'YERBA PRUEBA ÑANDÚ SUAVE 500 GRM' and x ->> 'marca' = 'ÑANDÚ' and (x ->> 'contenido')::numeric = 500 and x ->> 'unidad' = 'g'
    and (x ->> 'precio')::numeric = 4000 and (x ->> 'costo')::numeric = 2800
  from jsonb_array_elements(current_setting('prueba.ag')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000017'),
  'con nombre, marca, contenido, precio y costo');
select pruebas.ok((public.catalogo_general_buscar('99990000000017') -> 0 ->> 'ya')::boolean, 'después figura como que ya lo tiene');
select pruebas.ok((public.agregar_desde_catalogo('[{"codigo": "99990000000017", "precio": 1}]') -> 'ya') ->> 0 = 'YERBA PRUEBA ÑANDÚ SUAVE 500 GRM',
  'si ya lo tiene, lo saltea');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"codigo": "11111111", "precio": 1}]')$$, 'no está en el catálogo', 'un código que no está');

\echo == Marca y contenido en la ficha y en el alta desde caja
select set_config('prueba.mc', public.guardar_producto('{"nombre": "Con marca", "precio": 100, "marca": " Arcor ", "contenido": "2,25", "unidad": "lts"}') ->> 'id', false);
select public.guardar_producto(format('{"id": %s, "nombre": "Con marca", "precio": 120}', current_setting('prueba.mc'))::jsonb);
select pruebas.falla($$select public.guardar_producto('{"nombre": "x", "precio": 1, "contenido": 5, "unidad": "botella"}')$$, 'unidad', 'unidad desconocida');
select set_config('prueba.adc', public.alta_desde_caja('{"nombre": "GASEOSA PRUEBA 2", "codigo": "99990000000031", "precio": 900, "marca": "PRUEBA", "contenido": 354, "unidad": "ml"}') ->> 'id', false);
reset role;
select pruebas.ok((select marca = 'Arcor' and contenido = 2.25 and unidad = 'l' from public.productos where id = current_setting('prueba.mc')::bigint),
  'la ficha guarda marca y contenido; si no vienen, quedan como estaban');
select pruebas.ok((select marca = 'PRUEBA' and contenido = 354 and unidad = 'ml' and a_revisar from public.productos where id = current_setting('prueba.adc')::bigint),
  'el alta desde caja también');

\echo == Todas las pruebas del catálogo general dieron bien
