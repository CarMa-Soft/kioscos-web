-- =====================================================================
-- Pruebas: lo agregado desde el catálogo general sin costo o sin categoría queda a revisar. Negocio C (Carla, dueña).
-- =====================================================================
insert into public.catalogo_general (codigo, nombre, marca, contenido, unidad, precio_ref, cadenas, categoria) values
  ('99990000000062', 'PRUEBA REVISAR COMPLETO', 'PRUEBA', 1, 'un', 100, 1, 'Prueba Revisar'),
  ('99990000000079', 'PRUEBA REVISAR SIN COSTO', 'PRUEBA', 1, 'un', 100, 1, 'Prueba Revisar'),
  ('99990000000086', 'PRUEBA REVISAR SIN CATEGORIA', 'PRUEBA', 1, 'un', 100, 1, null);
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.rv', public.agregar_desde_catalogo('[{"codigo": "99990000000062", "precio": 150, "costo": 100, "categoria": "sugerida"},
  {"codigo": "99990000000079", "precio": 150, "categoria": "sugerida"}, {"codigo": "99990000000086", "precio": 150, "costo": 100, "categoria": "sugerida"}]')::text, false);

\echo == A revisar
select pruebas.ok((select not (x ->> 'a_revisar')::boolean from jsonb_array_elements(current_setting('prueba.rv')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000062'),
  'con costo y categoría, no');
select pruebas.ok((select (x ->> 'a_revisar')::boolean from jsonb_array_elements(current_setting('prueba.rv')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000079'),
  'sin costo, a revisar');
select pruebas.ok((select (x ->> 'a_revisar')::boolean from jsonb_array_elements(current_setting('prueba.rv')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000086'),
  'sin categoría (la sugerida no existe), a revisar');
select public.guardar_producto(format('{"id": %s, "nombre": "PRUEBA REVISAR SIN COSTO", "precio": 150, "costo": 90}',
  (select x ->> 'id' from jsonb_array_elements(current_setting('prueba.rv')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000079'))::jsonb);
reset role;
select pruebas.ok((select not a_revisar from public.productos where codigo = '99990000000079'), 'al guardarlo desde la ficha deja de estar a revisar');

\echo == Todas las pruebas de a revisar desde el catálogo dieron bien
