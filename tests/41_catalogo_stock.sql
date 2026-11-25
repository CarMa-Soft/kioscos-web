-- =====================================================================
-- Pruebas: agregar desde el catálogo general con stock. Negocio C (Carla, dueña). Usa productos inventados del catálogo.
-- =====================================================================
insert into public.catalogo_general (codigo, nombre, marca, contenido, unidad, precio_ref, cadenas) values
  ('99990000000048', 'PRODUCTO PRUEBA CON STOCK 1 KG', 'PRUEBA', 1, 'kg', 100, 1),
  ('99990000000055', 'PRODUCTO PRUEBA SIN STOCK 1 KG', 'PRUEBA', 1, 'kg', 100, 1);
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == El stock que ya hay en el local
select set_config('prueba.cs', public.agregar_desde_catalogo('[{"codigo": "99990000000048", "precio": 150, "stock": 24}, {"codigo": "99990000000055", "precio": 150}]')::text, false);
select pruebas.ok((select (x ->> 'stock')::numeric = 24 from jsonb_array_elements(current_setting('prueba.cs')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000048'),
  'queda con el stock cargado');
select pruebas.ok((select (x ->> 'stock')::numeric = 0 from jsonb_array_elements(current_setting('prueba.cs')::jsonb -> 'productos') x where x ->> 'codigo' = '99990000000055'),
  'sin stock, en 0');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"codigo": "99990000000055", "precio": 1, "stock": -3}]')$$, 'negativo', 'stock negativo, no');
select pruebas.falla($$select public.agregar_desde_catalogo('[{"codigo": "99990000000055", "precio": 1, "stock": 2.5}]')$$, 'entero', 'stock con decimales, no');
reset role;
select pruebas.ok((select count(*) = 1 and sum(cantidad) = 24 from public.movimientos_stock m join public.productos p on p.id = m.producto_id
    where p.codigo = '99990000000048' and m.motivo = 'Stock inicial'), 'queda anotado como "Stock inicial" (solo el que tenía stock)');
select pruebas.ok(not exists (select 1 from public.movimientos_stock m join public.productos p on p.id = m.producto_id where p.codigo = '99990000000055'),
  'el que entró sin stock no anota movimiento');

\echo == Todas las pruebas de agregar con stock dieron bien
