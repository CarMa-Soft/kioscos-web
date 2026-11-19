-- =====================================================================
-- Pruebas: alta rápida desde caja (productos "a revisar") y "Varios" desactivable. Usa el negocio C (07 a 22):
-- Carla (dueña, con el turno abierto) y Cami (empleada).
-- =====================================================================
set local role authenticated;

\echo == La empleada crea un producto desde la caja con lo mínimo
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select set_config('prueba.caja1', public.alta_desde_caja('{"codigo": "7790000000231", "precio": 850}')::text, false);
select pruebas.ok(current_setting('prueba.caja1')::jsonb ->> 'nombre' = 'Producto 7790000000231'
  and (current_setting('prueba.caja1')::jsonb ->> 'a_revisar')::boolean and (current_setting('prueba.caja1')::jsonb ->> 'precio')::numeric = 850
  and not current_setting('prueba.caja1')::jsonb ? 'costo', 'sin nombre queda "Producto <código>", a revisar y sin mostrar el costo a la empleada');
select pruebas.falla($$select public.alta_desde_caja('{"codigo": "7790000000231", "precio": 900}')$$, 'ya lo tiene', 'no repite un código');
select pruebas.falla($$select public.alta_desde_caja('{"nombre": "Chicle", "precio": 0}')$$, 'Poné el precio', 'el precio es obligatorio');
select pruebas.falla($$select public.alta_desde_caja('{"codigo": "77 90", "precio": 10}')$$, 'espacios', 'el código no tiene espacios');

\echo == Se vende y no aparece en Pedidos hasta revisarlo
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select public.registrar_venta(gen_random_uuid(),
  jsonb_build_array(jsonb_build_object('producto_id', (current_setting('prueba.caja1')::jsonb ->> 'id')::bigint, 'cantidad', 2)),
  '[{"forma": "Efectivo", "base": 1700}]');
select pruebas.ok((pruebas.prod(current_setting('prueba.caja1')::jsonb ->> 'id') ->> 'stock')::numeric = -2, 'la venta descuenta el stock (queda en negativo)');
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.pedidos() -> 'sin_proveedor') i
  where i ->> 'producto_id' = current_setting('prueba.caja1')::jsonb ->> 'id'), 'mientras está a revisar no se propone pedirlo');

\echo == El dueño lo revisa desde la ficha
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.caja1')::jsonb ->> 'id', 'nombre', 'Alfajor triple',
  'codigo', '7790000000231', 'precio', 850, 'costo', 500, 'stock', 0, 'stock_min', 5));
select pruebas.ok(not (pruebas.prod(current_setting('prueba.caja1')::jsonb ->> 'id') ->> 'a_revisar')::boolean
  and pruebas.prod(current_setting('prueba.caja1')::jsonb ->> 'id') ->> 'nombre' = 'Alfajor triple', 'al guardarlo deja de estar a revisar');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.pedidos() -> 'sin_proveedor') i
  where i ->> 'producto_id' = current_setting('prueba.caja1')::jsonb ->> 'id'), 'ya revisado, con stock 0 y mínimo 5, aparece en Pedidos');

\echo == Varios desactivado
select public.guardar_config('varios', 'false');
select pruebas.falla($$select public.registrar_venta(gen_random_uuid(), '[{"nombre": "Fotocopia", "importe": 100}]', '[{"forma": "Efectivo", "base": 100}]')$$,
  'desactivada', 'con Varios desactivado no se vende sin producto');
select public.guardar_config('varios', 'true');
select pruebas.ok((public.registrar_venta(gen_random_uuid(), '[{"nombre": "Fotocopia", "importe": 100}]', '[{"forma": "Efectivo", "base": 100}]') ->> 'total')::numeric = 100,
  'activado de nuevo, se vende como Varios');
reset role;

\echo == Todas las pruebas de alta desde caja dieron bien
