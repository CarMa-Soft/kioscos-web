-- =====================================================================
-- Pruebas: ventas hechas sin conexión que se suben después (registrar_venta con p_sin_conexion). Negocio C.
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select public.abrir_turno(0) where coalesce(public.estado_caja() -> 'turno', 'null') = 'null'::jsonb;
select set_config('prueba.sc_gall', public.guardar_producto('{"nombre": "Galletita sin conexión", "precio": 1000}') ->> 'id', false);
select set_config('prueba.sc_2x1', public.guardar_promocion(format('{"nombre": "2x1 galletita sin conexión", "tipo": "lleva_paga", "cantidad": 2, "paga": 1, "productos": [%s]}',
  current_setting('prueba.sc_gall'))::jsonb) ->> 'id', false);
reset role;
-- después de vender sin conexión, el precio sube y la promoción se da de baja: la venta se sube como se cobró
update public.productos set precio = 1200 where id = current_setting('prueba.sc_gall')::bigint;
update public.promociones set activa = false where id = current_setting('prueba.sc_2x1')::bigint;
select set_config('prueba.sc_clave', gen_random_uuid()::text, false);
select set_config('prueba.sc_fecha', (now() - interval '2 hours')::text, false);

-- la sube Cami (empleada); la había hecho Carla
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select set_config('prueba.sc_v', public.registrar_venta(current_setting('prueba.sc_clave')::uuid,
  format('[{"producto_id": %s, "cantidad": 2, "precio": 1000, "lista": 1000}]', current_setting('prueba.sc_gall'))::jsonb,
  '[{"forma": "Efectivo", "base": 1000}]', p_promos => 0,
  p_sin_conexion => format('{"fecha": "%s", "usuario_id": %s, "promos": [{"k": 1, "promocion_id": %s, "descuento": 1000}]}',
    current_setting('prueba.sc_fecha'), current_setting('prueba.carla'), current_setting('prueba.sc_2x1'))::jsonb)::text, false);

\echo == Se sube como se cobró
select pruebas.ok((current_setting('prueba.sc_v')::jsonb ->> 'total')::numeric = 1000, 'el total que se cobró (con la promoción de ese momento)');
select pruebas.ok((current_setting('prueba.sc_v')::jsonb ->> 'descuento_promos')::numeric = 1000, 'con lo que descontó la promoción');
reset role;
select pruebas.ok((select sin_conexion and fecha = current_setting('prueba.sc_fecha')::timestamptz and usuario_id = current_setting('prueba.carla')::bigint
  and descuento_renglones = 0 from public.ventas where clave = current_setting('prueba.sc_clave')::uuid), 'marcada sin conexión, con su fecha y quien la hizo, sin descuento por la suba de precio');
select pruebas.ok((select i.precio_lista = 1000 and i.promo_nombre = '2x1 galletita sin conexión' from public.venta_items i join public.ventas v on v.id = i.venta_id
  where v.clave = current_setting('prueba.sc_clave')::uuid), 'el renglón con el precio de lista de ese momento y la promoción');
select pruebas.ok((select c.fecha = current_setting('prueba.sc_fecha')::timestamptz from public.caja c join public.ventas v on v.id = c.venta_id
  where v.clave = current_setting('prueba.sc_clave')::uuid), 'el ingreso a la caja con la misma fecha');
select pruebas.ok((select stock = -2 from public.productos where id = current_setting('prueba.sc_gall')::bigint), 'descuenta el stock');

\echo == No se registra dos veces
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok((public.registrar_venta(current_setting('prueba.sc_clave')::uuid,
  format('[{"producto_id": %s, "cantidad": 2, "precio": 1000, "lista": 1000}]', current_setting('prueba.sc_gall'))::jsonb,
  '[{"forma": "Efectivo", "base": 1000}]', p_sin_conexion => '{"fecha": "2026-01-01"}') ->> 'repetida')::boolean, 'subirla otra vez da la misma (repetida)');

\echo == Lo que no se puede sin conexión
select set_config('prueba.sc_item', format('[{"producto_id": %s, "cantidad": 1, "precio": 1000, "lista": 1000}]', current_setting('prueba.sc_gall')), false);
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '%s', '[{"forma": "Efectivo", "base": 1000}]',
  p_sin_conexion => jsonb_build_object('fecha', now() - interval '8 days'))$$, current_setting('prueba.sc_item')), 'fecha', 'de hace más de 7 días');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '%s', '[{"forma": "Efectivo", "base": 1000}]',
  p_sin_conexion => jsonb_build_object('fecha', now() + interval '1 hour'))$$, current_setting('prueba.sc_item')), 'fecha', 'del futuro');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '%s', '[{"forma": "Fiado", "base": 1000}]',
  p_sin_conexion => jsonb_build_object('fecha', now()))$$, current_setting('prueba.sc_item')), 'fiada', 'fiado');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '%s', '[{"forma": "Efectivo", "base": 1000}]',
  p_entrega => '{"nombre": "Juan"}', p_sin_conexion => jsonb_build_object('fecha', now()))$$, current_setting('prueba.sc_item')), 'entregas', 'entregas para después');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '%s', '[{"forma": "Efectivo", "base": 0.01}]',
  p_sin_conexion => jsonb_build_object('fecha', now(), 'promos', jsonb_build_array(jsonb_build_object('k', 2, 'promocion_id', %s, 'descuento', 999.99))))$$,
  current_setting('prueba.sc_item'), current_setting('prueba.sc_2x1')), 'no existe', 'promoción en un renglón que no está');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '%s', '[{"forma": "Efectivo", "base": 1}]',
  p_sin_conexion => jsonb_build_object('fecha', now(), 'promos', jsonb_build_array(jsonb_build_object('k', 1, 'promocion_id', %s, 'descuento', 1500))))$$,
  current_setting('prueba.sc_item'), current_setting('prueba.sc_2x1')), 'no es válida', 'promoción que descuenta más que el renglón');
-- el tope de descuento del empleado se sigue controlando, contra el precio de lista de ese momento
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1, "precio": 500, "lista": 1000}]',
  '[{"forma": "Efectivo", "base": 500}]', p_sin_conexion => jsonb_build_object('fecha', now()))$$, current_setting('prueba.sc_gall')), 'autorización', 'descuento por encima del tope');

\echo == Un producto dado de baja después de venderlo
reset role;
update public.productos set activo = false where id = current_setting('prueba.sc_gall')::bigint;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok((public.registrar_venta(gen_random_uuid(), current_setting('prueba.sc_item')::jsonb, '[{"forma": "Efectivo", "base": 1000}]',
  p_sin_conexion => jsonb_build_object('fecha', now() - interval '1 hour')) ->> 'total')::numeric = 1000, 'sin conexión se sube igual');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Efectivo", "base": 1200}]')$$,
  current_setting('prueba.sc_gall')), 'dado de baja', 'con conexión no se vende');
reset role;
update public.productos set activo = true where id = current_setting('prueba.sc_gall')::bigint;

\echo == Todas las pruebas de ventas sin conexión dieron bien
