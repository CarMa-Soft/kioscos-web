-- =====================================================================
-- Pruebas: Cargar productos — en la misma lista, los del catálogo general y los nuevos (que no están en él). Negocio C.
-- =====================================================================
insert into public.catalogo_general (codigo, nombre, marca, contenido, unidad, precio_ref, cadenas, categoria) values
  ('99990000000093', 'PRUEBA CARGAR DEL CATALOGO', 'PRUEBA', 1, 'un', 100, 1, null);
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.agregar_desde_catalogo('[{"nuevo": true, "nombre": "x", "precio": 1}]')$$, 'dueño', 'el empleado no carga');

select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.cat1', (select x ->> 'id' from jsonb_array_elements(public.crear_categorias('["Prueba Cargar"]')) x where x ->> 'nombre' = 'Prueba Cargar'), false);
select set_config('prueba.cp', public.agregar_desde_catalogo(format('[{"codigo": "99990000000093", "precio": 150},
  {"nuevo": true, "nombre": " Pan casero ", "codigo": "2000000000017", "precio": 900, "costo": 500, "stock": 6, "categoria_id": %s},
  {"nuevo": true, "nombre": "Alfajor de la zona", "precio": 700}]', current_setting('prueba.cat1'))::jsonb)::text, false);

\echo == Los dos tipos juntos
select pruebas.ok((current_setting('prueba.cp')::jsonb ->> 'creados')::int = 3, 'crea el del catálogo y los dos nuevos');
select pruebas.ok((select x ->> 'codigo' = '2000000000017' and (x ->> 'precio')::numeric = 900 and (x ->> 'costo')::numeric = 500 and not (x ->> 'a_revisar')::boolean
  from jsonb_array_elements(current_setting('prueba.cp')::jsonb -> 'productos') x where x ->> 'nombre' = 'Pan casero'), 'el nuevo con código, precio, costo y categoría (no queda a revisar)');
select pruebas.ok((select x ->> 'codigo' is null and (x ->> 'a_revisar')::boolean
  from jsonb_array_elements(current_setting('prueba.cp')::jsonb -> 'productos') x where x ->> 'nombre' = 'Alfajor de la zona'), 'sin código, sin costo ni categoría: a revisar');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"nuevo": true, "nombre": "Otro pan", "codigo": "2000000000017", "precio": 1}]')$$, 'ya lo tiene', 'un código que ya está');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"nuevo": true, "nombre": " ", "precio": 1}]')$$, 'nombre', 'sin nombre');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"nuevo": true, "nombre": "Sin precio"}]')$$, 'precio', 'sin precio');
reset role;
select pruebas.ok((select stock = 6 from public.productos where codigo = '2000000000017'), 'con el stock');
select pruebas.ok(exists (select 1 from public.movimientos_stock m join public.productos p on p.id = m.producto_id
  where p.codigo = '2000000000017' and m.cantidad = 6 and m.motivo = 'Stock inicial'), 'y su movimiento de stock inicial');

\echo == Todas las pruebas de cargar productos dieron bien
