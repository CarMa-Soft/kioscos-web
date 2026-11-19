-- =====================================================================
-- Pruebas: encargos (sin pagar o con seña). Usa el negocio C (07 a 23): Carla (dueña, con el turno abierto) y Cami (empleada).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.vino', public.guardar_producto('{"nombre": "Vino Malbec reserva", "precio": 5000, "stock": 0}') ->> 'id', false);

\echo == Encargar con seña: entra a la caja, no toca el stock y aparece en Pedidos
select set_config('prueba.e1', public.registrar_encargo(jsonb_build_object('producto_id', current_setting('prueba.vino'), 'cantidad', 3,
  'nombre', 'María Gómez', 'telefono', '11 5555-6666', 'sena', 4000, 'sena_forma', 'Efectivo'))::text, false);
select pruebas.ok((current_setting('prueba.e1')::jsonb ->> 'sena')::numeric = 4000 and current_setting('prueba.e1')::jsonb ->> 'estado' = 'pendiente'
  and not (current_setting('prueba.e1')::jsonb ->> 'lista')::boolean, 'queda pendiente, con la seña, esperando mercadería');
select pruebas.ok((pruebas.prod(current_setting('prueba.vino')) ->> 'stock')::numeric = 0, 'el stock no cambia');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.pedidos() -> 'sin_proveedor') i
  where i ->> 'producto_id' = current_setting('prueba.vino') and (i ->> 'para_entregar')::numeric = 3
    and i ->> 'entregas' like '3 a María Gómez (encargo #%'), 'Pedidos lo propone, con a quién se le debe');
select pruebas.falla(format($$select public.registrar_encargo('{"producto_id": %s, "cantidad": 1}')$$, current_setting('prueba.vino')),
  'a nombre de quién', 'hace falta a nombre de quién');
select pruebas.falla(format($$select public.registrar_encargo('{"producto_id": %s, "cantidad": 1, "nombre": "X", "sena": 10, "sena_forma": "Fiado"}')$$,
  current_setting('prueba.vino')), 'Forma de pago de la seña', 'la seña no puede ser fiada');

\echo == La empleada encarga sin seña
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select set_config('prueba.e2', public.registrar_encargo(jsonb_build_object('producto_id', current_setting('prueba.vino'), 'cantidad', 1, 'nombre', 'Pedro'))::text, false);
select pruebas.ok(jsonb_array_length(public.encargos()) >= 2, 'la empleada ve los encargos');
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == Llega la mercadería y se vende: la seña se descuenta
select public.ajustar_stock(current_setting('prueba.vino')::bigint, 10, 'Llegó');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 3}]',
  '[{"forma": "Seña", "base": 4000}, {"forma": "Efectivo", "base": 11000}]')$$, current_setting('prueba.vino')),
  'pasa la de los encargos', 'sin el encargo no se puede pagar con seña');
select set_config('prueba.ve1', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 3}]', current_setting('prueba.vino'))::jsonb,
  '[{"forma": "Seña", "base": 4000}, {"forma": "Efectivo", "base": 11000}]', p_encargos => jsonb_build_array((current_setting('prueba.e1')::jsonb ->> 'id')::bigint))::text, false);
select pruebas.ok((current_setting('prueba.ve1')::jsonb ->> 'total')::numeric = 15000
  and current_setting('prueba.ve1')::jsonb -> 'pagos' @> '[{"forma": "Seña", "monto": 4000}]', 'la venta es por 15.000: 4.000 de seña y 11.000 en efectivo');
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.encargos()) e where e ->> 'id' = current_setting('prueba.e1')::jsonb ->> 'id'),
  'el encargo deja de estar pendiente');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 3}]', '[{"forma": "Efectivo", "base": 15000}]', p_encargos => '[%s]')$$,
  current_setting('prueba.vino'), current_setting('prueba.e1')::jsonb ->> 'id'), 'ya no está pendiente', 'no se entrega dos veces');

\echo == Anular esa venta: el encargo vuelve a estar pendiente
select public.anular_venta((current_setting('prueba.ve1')::jsonb ->> 'id')::bigint, 'prueba');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.encargos()) e where e ->> 'id' = current_setting('prueba.e1')::jsonb ->> 'id'),
  'anulada la venta, el encargo vuelve a pendiente');

\echo == Cancelar devolviendo la seña
select pruebas.falla(format('select public.cancelar_encargo(%s, null)', current_setting('prueba.e1')::jsonb ->> 'id'), 'si la seña se devuelve', 'con seña hay que elegir');
select public.cancelar_encargo((current_setting('prueba.e1')::jsonb ->> 'id')::bigint, true, 'No lo quiso');
select public.cancelar_encargo((current_setting('prueba.e2')::jsonb ->> 'id')::bigint, null);
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.encargos()) e
  where e ->> 'id' in (current_setting('prueba.e1')::jsonb ->> 'id', current_setting('prueba.e2')::jsonb ->> 'id')), 'cancelados, ya no están pendientes');
reset role;
select pruebas.ok((select count(*) from public.caja where concepto like 'Seña encargo #%' and tipo = 'ingreso' and monto = 4000) = 1
  and (select count(*) from public.caja where concepto like 'Devolución seña encargo #%' and tipo = 'egreso' and monto = 4000) = 1,
  'la seña entró a la caja y la devolución salió');
select pruebas.ok(not exists (select 1 from public.caja where venta_id = (current_setting('prueba.ve1')::jsonb ->> 'id')::bigint and forma = 'Seña'),
  'la parte pagada con seña no vuelve a entrar a la caja');

\echo == Todas las pruebas de encargos dieron bien
