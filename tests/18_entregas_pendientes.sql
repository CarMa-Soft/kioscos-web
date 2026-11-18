-- =====================================================================
-- Pruebas: entregas pendientes (vender más de lo que hay y entregar el resto cuando llega). Usa el negocio C (07 a 17):
-- Carla (dueña, con el turno abierto), Cami (empleada) y el proveedor Aceitera del Sur (prueba.pa).
-- =====================================================================
create function pruebas.entrega_de(p_producto text) returns jsonb language sql as $$
  select e from jsonb_array_elements(public.entregas_pendientes()) e where e ->> 'producto_id' = p_producto limit 1;
$$;
grant execute on function pruebas.entrega_de(text) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.lima', public.guardar_producto('{"nombre": "Gaseosa Lima", "precio": 1000, "stock": 3}') ->> 'id', false);

\echo == Vender 5 con 3 en stock: se entregan 3 y quedan 2 pendientes
select set_config('prueba.vl', public.registrar_venta(gen_random_uuid(),
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.lima')::bigint, 'cantidad', 5, 'pendiente', 2)),
  '[{"forma": "Efectivo", "base": 5000}]', null, p_entrega => '{"nombre": "Juan Pérez", "telefono": "11 4444-5555"}')::text, false);
select pruebas.ok((current_setting('prueba.vl')::jsonb ->> 'total')::numeric = 5000, 'se cobran los 5');
select pruebas.ok((pruebas.prod(current_setting('prueba.lima')) ->> 'stock')::numeric = 0, 'del stock salen solo los 3 que se llevó');
select pruebas.ok(current_setting('prueba.vl')::jsonb -> 'pendientes' @> '[{"cantidad": 2, "a_nombre": "Juan Pérez"}]'::jsonb, 'la venta muestra lo pendiente');
select pruebas.ok((pruebas.entrega_de(current_setting('prueba.lima')) ->> 'cantidad')::numeric = 2
  and not (pruebas.entrega_de(current_setting('prueba.lima')) ->> 'lista')::boolean
  and pruebas.entrega_de(current_setting('prueba.lima')) ->> 'telefono' = '11 4444-5555', 'queda en entregas pendientes, todavía sin stock');
select pruebas.falla(format('select public.entregar_pendiente(%s)', pruebas.entrega_de(current_setting('prueba.lima')) ->> 'id'),
  'cargá primero la compra', 'sin stock no se puede entregar');

\echo == Controles al vender
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1, "pendiente": 1}]', '[{"forma": "Efectivo", "base": 1000}]')$$,
  current_setting('prueba.lima')), 'a nombre de quién', 'sin cliente ni nombre no se deja pendiente');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1, "pendiente": 2}]', '[{"forma": "Efectivo", "base": 1000}]', null, p_entrega => '{"nombre": "X"}')$$,
  current_setting('prueba.lima')), 'no puede pasar lo vendido', 'no queda pendiente más de lo vendido');

\echo == Pedidos lo suma, con la nota
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.pedidos() -> 'sin_proveedor') i
  where i ->> 'producto_id' = current_setting('prueba.lima') and (i ->> 'para_entregar')::numeric = 2 and (i ->> 'cantidad')::numeric = 3
    and i ->> 'entregas' like '2 a Juan Pérez (venta #%'), 'en Pedidos: 2 para entregar (propone 3: lo comprometido y 1 más)');

\echo == Llega la mercadería y se entrega
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000018',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.lima'), 'cantidad', 10, 'costo', 600))));
select pruebas.ok((pruebas.entrega_de(current_setting('prueba.lima')) ->> 'lista')::boolean, 'con la compra cargada queda lista para entregar');
select set_config('prueba.ent', pruebas.entrega_de(current_setting('prueba.lima')) ->> 'id', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok((public.entregar_pendiente((pruebas.entrega_de(current_setting('prueba.lima')) ->> 'id')::bigint) ->> 'a_nombre') = 'Juan Pérez',
  'la empleada la entrega en el mostrador');
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select pruebas.ok((pruebas.prod(current_setting('prueba.lima')) ->> 'stock')::numeric = 8 and pruebas.entrega_de(current_setting('prueba.lima')) is null,
  'sale del stock y deja de estar pendiente');

\echo == Devolución de lo que no se había entregado
select set_config('prueba.vela', public.guardar_producto('{"nombre": "Vela", "precio": 500, "stock": 1}') ->> 'id', false);
select set_config('prueba.vv', public.registrar_venta(gen_random_uuid(),
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.vela')::bigint, 'cantidad', 3, 'pendiente', 2)),
  '[{"forma": "Efectivo", "base": 1500}]', null, p_entrega => '{"nombre": "Ana"}')::text, false);
select public.devolver_venta((current_setting('prueba.vv')::jsonb ->> 'id')::bigint,
  jsonb_build_array(jsonb_build_object('id', current_setting('prueba.vv')::jsonb -> 'items' -> 0 -> 'id', 'cantidad', 2, 'vuelve_stock', true)), 'Efectivo');
select pruebas.ok((pruebas.prod(current_setting('prueba.vela')) ->> 'stock')::numeric = 0 and pruebas.entrega_de(current_setting('prueba.vela')) is null,
  'devolver lo no entregado cancela la entrega y no suma stock');
select public.devolver_venta((current_setting('prueba.vv')::jsonb ->> 'id')::bigint,
  jsonb_build_array(jsonb_build_object('id', current_setting('prueba.vv')::jsonb -> 'items' -> 0 -> 'id', 'cantidad', 1, 'vuelve_stock', true)), 'Efectivo');
select pruebas.ok((pruebas.prod(current_setting('prueba.vela')) ->> 'stock')::numeric = 1, 'lo que sí se llevó vuelve al stock');

\echo == Anular una venta con entrega pendiente
select set_config('prueba.vino', public.guardar_producto('{"nombre": "Vino", "precio": 3000, "stock": 1}') ->> 'id', false);
select set_config('prueba.vn', public.registrar_venta(gen_random_uuid(),
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.vino')::bigint, 'cantidad', 3, 'pendiente', 2)),
  '[{"forma": "Efectivo", "base": 9000}]', null, p_entrega => '{"nombre": "Luis"}')::text, false);
select public.anular_venta((current_setting('prueba.vn')::jsonb ->> 'id')::bigint);
select pruebas.ok((pruebas.prod(current_setting('prueba.vino')) ->> 'stock')::numeric = 1 and pruebas.entrega_de(current_setting('prueba.vino')) is null,
  'anular devuelve solo lo entregado y cancela lo pendiente');

\echo == Entregar todo aunque no haya stock (el stock estaba mal): sin pendiente, como antes
select public.registrar_venta(gen_random_uuid(), jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.vino')::bigint, 'cantidad', 3)),
  '[{"forma": "Efectivo", "base": 9000}]');
select pruebas.ok((pruebas.prod(current_setting('prueba.vino')) ->> 'stock')::numeric = -2 and pruebas.entrega_de(current_setting('prueba.vino')) is null,
  'sin pendiente sale todo del stock');

\echo == Otro negocio
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(jsonb_array_length(public.entregas_pendientes()) = 0, 'A no ve las entregas de C');
select pruebas.falla(format('select public.entregar_pendiente(%s)', current_setting('prueba.ent')), 'No se encontró', 'A no entrega las de C');
select pruebas.falla('select * from public.entregas_pendientes', 'permission denied', 'nadie lee la tabla entregas_pendientes directo');
reset role;

\echo == Todas las pruebas de entregas pendientes dieron bien
