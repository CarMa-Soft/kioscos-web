-- =====================================================================
-- Pruebas: importar productos desde una planilla. Usa el negocio C (07 en adelante): Carla (dueña) y Cami (empleada).
-- =====================================================================
-- Ayudas (leen las tablas: con los permisos de quien las crea)
create function pruebas.prod(p_codigo text) returns public.productos language sql security definer set search_path = '' as $$
  select p from public.productos p where p.negocio_id = current_setting('prueba.neg_c')::uuid and p.codigo = p_codigo;
$$;
create function pruebas.stock_inicial(p_codigo text) returns numeric language sql security definer set search_path = '' as $$
  select sum(m.cantidad) from public.movimientos_stock m join public.productos p on p.id = m.producto_id
  where p.negocio_id = current_setting('prueba.neg_c')::uuid and p.codigo = p_codigo and m.motivo = 'Stock inicial';
$$;
grant execute on function pruebas.prod(text), pruebas.stock_inicial(text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == Crea los nuevos, con su categoría y stock inicial; las filas con error no cortan
select set_config('prueba.imp', public.importar_productos($$[
  {"fila": 2, "nombre": "Galletitas  Importadas", "codigo": "IMP001", "precio": "850,50", "costo": "600", "stock": "12", "categoria": "Almacén importado"},
  {"fila": 3, "nombre": "Jugo importado", "codigo": "IMP002", "precio": 1200, "categoria": "almacén IMPORTADO"},
  {"fila": 4, "nombre": "", "codigo": "IMP003", "precio": 100},
  {"fila": 5, "nombre": "Sin precio", "codigo": "IMP004"},
  {"fila": 6, "nombre": "Precio raro", "codigo": "IMP005", "precio": "mil"}
]$$::jsonb)::text, false);
select pruebas.ok((current_setting('prueba.imp')::jsonb ->> 'creados')::int = 2, 'crea los dos que están bien');
select pruebas.ok(jsonb_array_length(current_setting('prueba.imp')::jsonb -> 'errores') = 3
  and current_setting('prueba.imp')::jsonb -> 'errores' -> 0 ->> 'fila' = '4', 'devuelve las tres filas con error, con su número');
select pruebas.ok((pruebas.prod('IMP001')).nombre = 'Galletitas Importadas' and (pruebas.prod('IMP001')).precio = 850.5
  and (pruebas.prod('IMP001')).stock = 12 and (pruebas.prod('IMP001')).categoria_id = (pruebas.prod('IMP002')).categoria_id,
  'nombre limpio, precio con coma, stock y una sola categoría (sin importar mayúsculas)');
select pruebas.ok(pruebas.stock_inicial('IMP001') = 12, 'el stock queda como stock inicial');

\echo == Volver a importar actualiza precio y costo (no el stock ni el nombre), por código o alternativo
select public.agregar_codigo((pruebas.prod('IMP002')).id, 'IMP002ALT');
select set_config('prueba.imp', public.importar_productos($$[
  {"fila": 2, "nombre": "Otro nombre", "codigo": "IMP001", "precio": "900", "costo": "650", "stock": "99"},
  {"fila": 3, "codigo": "IMP002ALT", "precio": "1300"}
]$$::jsonb)::text, false);
select pruebas.ok((current_setting('prueba.imp')::jsonb ->> 'actualizados')::int = 2 and (current_setting('prueba.imp')::jsonb ->> 'creados')::int = 0, 'actualiza los dos');
select pruebas.ok((pruebas.prod('IMP001')).precio = 900 and (pruebas.prod('IMP001')).costo = 650 and (pruebas.prod('IMP001')).stock = 12
  and (pruebas.prod('IMP001')).nombre = 'Galletitas Importadas', 'precio y costo nuevos; stock y nombre como estaban');
select pruebas.ok((pruebas.prod('IMP002')).precio = 1300, 'encuentra el producto por su código alternativo');

\echo == Sin actualizar, los que ya existen se saltean
select pruebas.ok((public.importar_productos('[{"fila": 2, "codigo": "IMP001", "precio": "1"}]', false) ->> 'salteados')::int = 1,
  'lo saltea');
select pruebas.ok((pruebas.prod('IMP001')).precio = 900, 'y no cambia el precio');

\echo == Solo el dueño
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.importar_productos('[]')$$, 'dueño', 'el empleado no importa');
reset role;

\echo == Todas las pruebas de importar productos dieron bien
