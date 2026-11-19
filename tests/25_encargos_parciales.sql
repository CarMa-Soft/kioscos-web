-- =====================================================================
-- Pruebas: encargos entregados en partes (solo lo que llegó). Usa el negocio C (07 a 24): Carla (dueña, con el turno abierto).
-- =====================================================================
create function pruebas.enc(p_id text) returns jsonb language sql as $$
  select e from jsonb_array_elements(public.encargos()) e where e ->> 'id' = p_id;
$$;
grant execute on function pruebas.enc(text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.gas', public.guardar_producto('{"nombre": "Gaseosa cola 2L", "precio": 1000, "stock": 0}') ->> 'id', false);
select set_config('prueba.e5', public.registrar_encargo(jsonb_build_object('producto_id', current_setting('prueba.gas'), 'cantidad', 10,
  'nombre', 'Club del barrio', 'sena', 5000, 'sena_forma', 'Efectivo')) ->> 'id', false);

\echo == Sin mercadería no se entrega
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "base": 1000}]', p_encargos => '[{"id": %s, "cantidad": 1}]')$$,
  current_setting('prueba.gas'), current_setting('prueba.e5')), 'entregá del encargo solo lo que llegó', 'con 0 en stock no se entrega');

\echo == Llegan 4 de 10: se entregan 4 y quedan 6
select public.ajustar_stock(current_setting('prueba.gas')::bigint, 4, 'Llegó una parte');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 5}]', '[{"forma": "Efectivo", "base": 5000}]', p_encargos => '[{"id": %s, "cantidad": 5}]')$$,
  current_setting('prueba.gas'), current_setting('prueba.e5')), 'hay 4 en stock', 'no se entrega más de lo que hay');
select public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 4}]', current_setting('prueba.gas'))::jsonb,
  '[{"forma": "Seña", "base": 4000}]', p_encargos => jsonb_build_array(jsonb_build_object('id', current_setting('prueba.e5')::bigint, 'cantidad', 4)));
select pruebas.ok((pruebas.enc(current_setting('prueba.e5')) ->> 'cantidad')::numeric = 6 and (pruebas.enc(current_setting('prueba.e5')) ->> 'sena')::numeric = 1000
  and (pruebas.enc(current_setting('prueba.e5')) ->> 'entregado')::numeric = 4, 'quedan 6 por entregar y 1.000 de seña');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.pedidos() -> 'sin_proveedor') i
  where i ->> 'producto_id' = current_setting('prueba.gas') and i ->> 'entregas' like '6 a Club del barrio (encargo #%'), 'Pedidos muestra los 6 que faltan');

\echo == Llega el resto: se entregan los 6 y se usa la seña que quedaba
select public.ajustar_stock(current_setting('prueba.gas')::bigint, 6, 'Llegó el resto');
select set_config('prueba.v6', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 6}]', current_setting('prueba.gas'))::jsonb,
  '[{"forma": "Seña", "base": 1000}, {"forma": "Efectivo", "base": 5000}]', p_encargos => jsonb_build_array(current_setting('prueba.e5')::bigint)) ->> 'id', false);
select pruebas.ok(pruebas.enc(current_setting('prueba.e5')) is null, 'entregado todo, deja de estar pendiente');

\echo == Anular la última venta: vuelven 6 pendientes con 1.000 de seña
select public.anular_venta(current_setting('prueba.v6')::bigint, 'prueba');
select pruebas.ok((pruebas.enc(current_setting('prueba.e5')) ->> 'cantidad')::numeric = 6 and (pruebas.enc(current_setting('prueba.e5')) ->> 'sena')::numeric = 1000,
  'vuelve pendiente lo de esa venta, con su seña');
select public.cancelar_encargo(current_setting('prueba.e5')::bigint, true);
reset role;
select pruebas.ok(exists (select 1 from public.caja where concepto like 'Devolución seña encargo #%Club del barrio%' and monto = 1000), 'al cancelar se devuelve solo la seña que quedaba');

\echo == Todas las pruebas de encargos en partes dieron bien
