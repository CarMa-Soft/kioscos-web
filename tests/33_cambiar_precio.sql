-- =====================================================================
-- Pruebas: cambiar el precio desde la tabla de Productos. Usa el negocio C (07 en adelante): Carla (dueña) y Cami (empleada).
-- =====================================================================
create function pruebas.precio_de(p_id text) returns table (precio numeric, margen numeric) language sql security definer set search_path = '' as $$
  select p.precio, p.margen from public.productos p where p.id = p_id::bigint;
$$;
grant execute on function pruebas.precio_de(text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.cp', public.guardar_producto('{"nombre": "Para cambiar precio", "costo": 100, "precio": 150}') ->> 'id', false);
select public.margen_producto(current_setting('prueba.cp')::bigint, 50);

\echo == Cambiar el precio deja el precio fijo
select pruebas.ok((public.cambiar_precio(current_setting('prueba.cp')::bigint, 199.999) ->> 'precio')::numeric = 200, 'redondea a centavos y lo devuelve');
select pruebas.ok((select precio = 200 and margen is null from pruebas.precio_de(current_setting('prueba.cp'))), 'queda sin margen automático');
select pruebas.falla(format('select public.cambiar_precio(%s, -1)', current_setting('prueba.cp')), 'negativo', 'precio negativo, no');

\echo == Solo el dueño
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla(format('select public.cambiar_precio(%s, 300)', current_setting('prueba.cp')), 'dueño', 'el empleado no cambia precios');
reset role;

\echo == Todas las pruebas de cambiar precio dieron bien
