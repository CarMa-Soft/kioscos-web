-- =====================================================================
-- Pruebas: combos (promociones con productos distintos). Usa el negocio C y pruebas.vender / pruebas.promo_renglon de 37.
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.fernet', public.guardar_producto('{"nombre": "Fernet", "precio": 10000}') ->> 'id', false);
select set_config('prueba.coca', public.guardar_producto('{"nombre": "Coca 2,25", "precio": 3000}') ->> 'id', false);
select set_config('prueba.sprite', public.guardar_producto('{"nombre": "Sprite 2,25", "precio": 2800}') ->> 'id', false);
select set_config('prueba.papas', public.guardar_producto('{"nombre": "Papas", "precio": 1500}') ->> 'id', false);
select set_config('prueba.dip', public.guardar_producto('{"nombre": "Dip", "precio": 500}') ->> 'id', false);

\echo == Armar combos
select set_config('prueba.cfer', public.guardar_promocion(format('{"nombre": "Fernet + Coca o Sprite", "tipo": "combo", "precio": 12000,
  "componentes": [{"productos": [%s], "cantidad": 1}, {"productos": [%s, %s], "cantidad": 1}]}',
  current_setting('prueba.fernet'), current_setting('prueba.coca'), current_setting('prueba.sprite'))::jsonb) ->> 'id', false);
select set_config('prueba.cpap', public.guardar_promocion(format('{"nombre": "Papas + dip 20%%", "tipo": "combo", "pct": 20,
  "componentes": [{"productos": [%s], "cantidad": 2}, {"productos": [%s], "cantidad": 1}]}',
  current_setting('prueba.papas'), current_setting('prueba.dip'))::jsonb) ->> 'id', false);
select pruebas.ok((select (x ->> 'cantidad')::int = 3 and jsonb_array_length(x -> 'componentes') = 2 and jsonb_array_length(x -> 'productos') = 2
  from jsonb_array_elements(public.promociones() -> 'promociones') x where (x ->> 'id')::bigint = current_setting('prueba.cpap')::bigint),
  'guarda los componentes, todos los productos y las unidades del combo');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "combo", "precio": 100, "componentes": [{"productos": [%s], "cantidad": 1}]}')$$,
  current_setting('prueba.fernet')), 'al menos dos', 'un combo lleva dos productos distintos');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "combo", "precio": 100, "componentes": [{"productos": [%s], "cantidad": 1}, {"productos": [%s, %s], "cantidad": 1}]}')$$,
  current_setting('prueba.fernet'), current_setting('prueba.fernet'), current_setting('prueba.coca')), 'dos partes', 'un producto en dos partes, no');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "combo", "precio": 100, "pct": 10, "componentes": [{"productos": [%s], "cantidad": 1}, {"productos": [%s], "cantidad": 1}]}')$$,
  current_setting('prueba.fernet'), current_setting('prueba.coca')), 'uno de los dos', 'precio o porcentaje, no los dos');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "combo", "pct": 10, "componentes": [{"productos": [%s], "cantidad": 1.5}, {"productos": [%s], "cantidad": 1}]}')$$,
  current_setting('prueba.fernet'), current_setting('prueba.coca')), 'entero', 'cantidades enteras');

\echo == Combo a precio fijo
select set_config('prueba.vc1', pruebas.vender(format('[[%s, 1], [%s, 1]]', current_setting('prueba.fernet'), current_setting('prueba.coca'))::jsonb, 12000)::text, false);
select pruebas.ok(pruebas.promo_renglon(current_setting('prueba.vc1')::jsonb, 1) = 769.23 and pruebas.promo_renglon(current_setting('prueba.vc1')::jsonb, 2) = 230.77,
  '1000 repartidos en proporción: 769,23 al fernet y 230,77 a la coca');
select set_config('prueba.vc2', pruebas.vender(format('[[%s, 2], [%s, 1], [%s, 1]]', current_setting('prueba.fernet'), current_setting('prueba.sprite'), current_setting('prueba.coca'))::jsonb, 24000)::text, false);
select pruebas.ok((current_setting('prueba.vc2')::jsonb ->> 'descuento_promos')::numeric = 1800 and pruebas.promo_renglon(current_setting('prueba.vc2')::jsonb, 1) = 1394.23
  and pruebas.promo_renglon(current_setting('prueba.vc2')::jsonb, 2) = 175 and pruebas.promo_renglon(current_setting('prueba.vc2')::jsonb, 3) = 230.77,
  'dos combos: fernet con la coca (la más cara) y fernet con la sprite');
select pruebas.ok((pruebas.vender(format('[[%s, 2], [%s, 1]]', current_setting('prueba.fernet'), current_setting('prueba.coca'))::jsonb, 22000) ->> 'descuento_promos')::numeric = 1000,
  'sin la segunda gaseosa, un solo combo');
select pruebas.ok((pruebas.vender(format('[[%s, 1]]', current_setting('prueba.fernet'))::jsonb, 10000) ->> 'descuento_promos')::numeric = 0, 'el fernet solo, nada');

\echo == Combo con porcentaje
select set_config('prueba.vc3', pruebas.vender(format('[[%s, 3], [%s, 2]]', current_setting('prueba.papas'), current_setting('prueba.dip'))::jsonb, 4800)::text, false);
select pruebas.ok(pruebas.promo_renglon(current_setting('prueba.vc3')::jsonb, 1) = 600 and pruebas.promo_renglon(current_setting('prueba.vc3')::jsonb, 2) = 100,
  'un combo (2 papas + 1 dip): 20% de esas unidades; lo que sobra queda afuera');
reset role;

\echo == Todas las pruebas de combos dieron bien
