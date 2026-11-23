-- =====================================================================
-- Pruebas: promociones por cantidad. Usa el negocio C (07 en adelante): Carla (dueña) y Cami (empleada).
-- =====================================================================
-- vender(renglones [[producto, cantidad]], base, formas de pago, promos quitadas): la venta en efectivo (o con las formas dadas,
-- repartiendo la base: todo a la primera menos 1 peso a la segunda)
create function pruebas.vender(p_items jsonb, p_base numeric, p_formas text[] default '{Efectivo}', p_sin bigint[] default null, p_promos numeric default null)
returns jsonb language sql as $$
  select public.registrar_venta(gen_random_uuid(),
    (select jsonb_agg(case when jsonb_array_length(x) > 2 then jsonb_build_object('producto_id', x -> 0, 'cantidad', x -> 1, 'precio', x -> 2)
                           else jsonb_build_object('producto_id', x -> 0, 'cantidad', x -> 1) end) from jsonb_array_elements(p_items) x),
    case when cardinality(p_formas) = 1 then jsonb_build_array(jsonb_build_object('forma', p_formas[1], 'base', p_base))
         else jsonb_build_array(jsonb_build_object('forma', p_formas[1], 'base', p_base - 1), jsonb_build_object('forma', p_formas[2], 'base', 1)) end,
    p_sin_promos => p_sin, p_promos => p_promos);
$$;
-- lo que descontó la promoción en el renglón n (1, 2…) de la venta
create function pruebas.promo_renglon(v jsonb, n int) returns numeric language sql as $$ select (v -> 'items' -> (n - 1) ->> 'promo')::numeric $$;
grant execute on function pruebas.vender(jsonb, numeric, text[], bigint[], numeric), pruebas.promo_renglon(jsonb, int) to authenticated;
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select public.abrir_turno(0) where coalesce(public.estado_caja() -> 'turno', 'null') = 'null'::jsonb;
select public.guardar_ajustes_cobro('["Débito"]', '{}', 10);
select set_config('prueba.alf1', public.guardar_producto('{"nombre": "Alfajor triple", "precio": 1000}') ->> 'id', false);
select set_config('prueba.alf2', public.guardar_producto('{"nombre": "Alfajor simple", "precio": 800}') ->> 'id', false);
select set_config('prueba.alf3', public.guardar_producto('{"nombre": "Alfajor chico", "precio": 600}') ->> 'id', false);
select set_config('prueba.gas', public.guardar_producto('{"nombre": "Gaseosa", "precio": 500}') ->> 'id', false);
select set_config('prueba.vino1', public.guardar_producto('{"nombre": "Vino A", "precio": 1000}') ->> 'id', false);
select set_config('prueba.vino2', public.guardar_producto('{"nombre": "Vino B", "precio": 700}') ->> 'id', false);
select set_config('prueba.yerba', public.guardar_producto('{"nombre": "Yerba", "precio": 1000}') ->> 'id', false);
select set_config('prueba.fiambre', public.guardar_producto('{"nombre": "Fiambre", "precio": 9000, "por_peso": true}') ->> 'id', false);

\echo == Armar promociones (solo el dueño)
select set_config('prueba.p3x2', public.guardar_promocion(format('{"nombre": "3x2 alfajores", "tipo": "lleva_paga", "cantidad": 3, "paga": 2, "productos": [%s, %s, %s]}',
  current_setting('prueba.alf1'), current_setting('prueba.alf2'), current_setting('prueba.alf3'))::jsonb) ->> 'id', false);
select set_config('prueba.p2da', public.guardar_promocion(format('{"nombre": "2da al 50%%", "tipo": "unidad_pct", "cantidad": 2, "pct": 50, "productos": [%s]}',
  current_setting('prueba.gas'))::jsonb) ->> 'id', false);
select set_config('prueba.p6', public.guardar_promocion(format('{"nombre": "6 o más 10%%", "tipo": "desde_pct", "cantidad": 6, "pct": 10, "productos": [%s]}',
  current_setting('prueba.gas'))::jsonb) ->> 'id', false);
select set_config('prueba.pvinos', public.guardar_promocion(format('{"nombre": "2 vinos por $1500", "tipo": "precio", "cantidad": 2, "precio": 1500, "productos": [%s, %s]}',
  current_setting('prueba.vino1'), current_setting('prueba.vino2'))::jsonb) ->> 'id', false);
select set_config('prueba.pyerba', public.guardar_promocion(format('{"nombre": "Yerba 20%% en efectivo", "tipo": "desde_pct", "cantidad": 1, "pct": 20, "formas": ["Efectivo"], "productos": [%s]}',
  current_setting('prueba.yerba'))::jsonb) ->> 'id', false);
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "lleva_paga", "cantidad": 3, "paga": 3, "productos": [%s]}')$$, current_setting('prueba.gas')),
  'menor que N', 'en NxM, M menor que N');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "desde_pct", "cantidad": 1, "pct": 12.5, "productos": [%s]}')$$, current_setting('prueba.gas')),
  'entero', 'el porcentaje es entero');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "desde_pct", "cantidad": 1, "pct": 10, "productos": [%s]}')$$, current_setting('prueba.fiambre')),
  'por kilo', 'los productos por kilo no entran');
select pruebas.falla($$select public.guardar_promocion('{"nombre": "x", "tipo": "desde_pct", "cantidad": 1, "pct": 10, "productos": []}')$$, 'Elegí los productos', 'sin productos, no');
select pruebas.falla(format($$select public.guardar_promocion('{"nombre": "x", "tipo": "desde_pct", "cantidad": 1, "pct": 10, "desde": "2027-02-01", "hasta": "2027-01-01", "productos": [%s]}')$$,
  current_setting('prueba.gas')), 'anterior', 'hasta antes de desde, no');
select pruebas.ok(jsonb_array_length(public.promociones() -> 'promociones') = 5, 'el dueño ve las 5');

\echo == Vigencia: fechas y días
select set_config('prueba.pman', public.guardar_promocion(format('{"nombre": "Mañana", "tipo": "desde_pct", "cantidad": 1, "pct": 50, "dias": [%s], "productos": [%s]}',
  extract(isodow from (public.promociones() ->> 'hoy')::date)::int % 7 + 1, current_setting('prueba.gas'))::jsonb) ->> 'id', false);
select set_config('prueba.pven', public.guardar_promocion(format('{"nombre": "Vencida", "tipo": "desde_pct", "cantidad": 1, "pct": 50, "hasta": "%s", "productos": [%s]}',
  (public.promociones() ->> 'hoy')::date - 1, current_setting('prueba.gas'))::jsonb) ->> 'id', false);
select set_config('prueba.pfut', public.guardar_promocion(format('{"nombre": "Futura", "tipo": "desde_pct", "cantidad": 1, "pct": 50, "desde": "%s", "productos": [%s]}',
  (public.promociones() ->> 'hoy')::date + 1, current_setting('prueba.gas'))::jsonb) ->> 'id', false);
select set_config('prueba.ppau', public.guardar_promocion(format('{"nombre": "Pausada", "tipo": "desde_pct", "cantidad": 1, "pct": 50, "activa": false, "productos": [%s]}',
  current_setting('prueba.gas'))::jsonb) ->> 'id', false);
select pruebas.ok((select array_agg((x ->> 'id')::bigint order by (x ->> 'id')::bigint) from jsonb_array_elements(public.promociones_vigentes()) x)
  = array[current_setting('prueba.p3x2'), current_setting('prueba.p2da'), current_setting('prueba.p6'), current_setting('prueba.pvinos'), current_setting('prueba.pyerba')]::bigint[],
  'vigentes: ni la de otro día, ni la vencida, ni la futura, ni la pausada');

\echo == 3x2 con productos mezclados
-- unidades de la más cara a la más barata: 1000 1000 800 | 800 600 600 → salen gratis 800 y 600
select set_config('prueba.v1', pruebas.vender(format('[[%s, 2], [%s, 2], [%s, 2]]', current_setting('prueba.alf1'), current_setting('prueba.alf2'), current_setting('prueba.alf3'))::jsonb, 3400)::text, false);
select pruebas.ok((current_setting('prueba.v1')::jsonb ->> 'total')::numeric = 3400 and (current_setting('prueba.v1')::jsonb ->> 'descuento_promos')::numeric = 1400,
  '3x2: 4800 − 1400');
select pruebas.ok(pruebas.promo_renglon(current_setting('prueba.v1')::jsonb, 1) = 0 and pruebas.promo_renglon(current_setting('prueba.v1')::jsonb, 2) = 800
  and pruebas.promo_renglon(current_setting('prueba.v1')::jsonb, 3) = 600, 'gratis las más baratas de cada grupo');
select pruebas.ok((current_setting('prueba.v1')::jsonb -> 'items' -> 2 ->> 'importe')::numeric = 600
  and current_setting('prueba.v1')::jsonb -> 'items' -> 2 ->> 'promo_nombre' = '3x2 alfajores', 'el renglón queda con el importe rebajado y el nombre de la promo');
select pruebas.ok((pruebas.vender(format('[[%s, 4]]', current_setting('prueba.alf1'))::jsonb, 3000) ->> 'total')::numeric = 3000, 'con 4, la cuarta queda fuera');
select pruebas.ok((pruebas.vender(format('[[%s, 3, 900]]', current_setting('prueba.alf1'))::jsonb, 2700) ->> 'descuento_promos')::numeric = 0,
  'con el precio cambiado a mano no entra en la promoción');

\echo == N por $X: se reparte en proporción al precio
select set_config('prueba.v2', pruebas.vender(format('[[%s, 1], [%s, 1]]', current_setting('prueba.vino2'), current_setting('prueba.vino1'))::jsonb, 1500)::text, false);
select pruebas.ok(pruebas.promo_renglon(current_setting('prueba.v2')::jsonb, 2) = 117.65 and pruebas.promo_renglon(current_setting('prueba.v2')::jsonb, 1) = 82.35,
  '200 repartidos: 117,65 al de 1000 y 82,35 al de 700');

\echo == Dos promociones del mismo producto: la que más descuenta
select set_config('prueba.v3', pruebas.vender(format('[[%s, 6]]', current_setting('prueba.gas'))::jsonb, 2250)::text, false);
select pruebas.ok(current_setting('prueba.v3')::jsonb -> 'items' -> 0 ->> 'promo_nombre' = '2da al 50%' and pruebas.promo_renglon(current_setting('prueba.v3')::jsonb, 1) = 750,
  '6 gaseosas: la 2da al 50% (750) le gana a 6 o más 10% (300)');
select pruebas.ok((pruebas.vender(format('[[%s, 6]]', current_setting('prueba.gas'))::jsonb, 2700, p_sin => array[current_setting('prueba.p2da')::bigint]) ->> 'descuento_promos')::numeric = 300,
  'quitando esa, queda la otra');
select pruebas.ok((pruebas.vender(format('[[%s, 3]]', current_setting('prueba.gas'))::jsonb, 1250) ->> 'descuento_promos')::numeric = 250, 'con 3, un solo grupo');

\echo == Formas de pago
select pruebas.ok((pruebas.vender(format('[[%s, 1]]', current_setting('prueba.yerba'))::jsonb, 800) ->> 'total')::numeric = 800, 'en efectivo, 20% menos');
select pruebas.ok((pruebas.vender(format('[[%s, 1]]', current_setting('prueba.yerba'))::jsonb, 1000, '{Débito}') ->> 'total')::numeric = 1000, 'con débito, no');
select pruebas.ok((pruebas.vender(format('[[%s, 1]]', current_setting('prueba.yerba'))::jsonb, 1000, '{Efectivo,Débito}') ->> 'total')::numeric = 1000, 'parte con débito, tampoco');

\echo == La venta avisa si las promociones cambiaron
select pruebas.falla(format($$select pruebas.vender('[[%s, 2]]', 750, p_promos => 0)$$, current_setting('prueba.gas')), 'promociones cambiaron', 'lo calculado no coincide');
select pruebas.ok((pruebas.vender(format('[[%s, 2]]', current_setting('prueba.gas'))::jsonb, 750, p_promos => 250) ->> 'total')::numeric = 750, 'coincide: se registra');

\echo == El empleado: la promo no pide autorización; no las arma
select public.cerrar_turno(0);
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select public.abrir_turno(0);
select pruebas.ok((pruebas.vender(format('[[%s, 2]]', current_setting('prueba.gas'))::jsonb, 750) ->> 'total')::numeric = 750, 'la 2da al 50% no cuenta para su tope del 10%');
select pruebas.ok(jsonb_array_length(public.promociones_vigentes()) = 5, 've las de hoy');
select pruebas.falla('select public.promociones()', 'dueño', 'no ve la lista para armarlas');
select pruebas.falla(format($$select public.borrar_promocion(%s)$$, current_setting('prueba.p6')), 'dueño', 'no las borra');

\echo == Otro negocio no ve ni toca las promociones de C
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.promociones() -> 'promociones') x where (x ->> 'id')::bigint = current_setting('prueba.p6')::bigint),
  'no aparecen en su lista');
select pruebas.falla(format($$select public.borrar_promocion(%s)$$, current_setting('prueba.p6')), 'no encontrada', 'no las borra');
select pruebas.falla(format($$select public.guardar_promocion('{"id": %s, "nombre": "x", "tipo": "desde_pct", "cantidad": 1, "pct": 10, "productos": [%s]}')$$,
  current_setting('prueba.p6'), current_setting('prueba.gas')), 'no encontrado', 'no usa productos de C');

\echo == Borrar: las ventas quedan con el nombre de la promo
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select public.borrar_promocion(current_setting('prueba.p3x2')::bigint);
reset role;
select pruebas.ok((select promo_nombre = '3x2 alfajores' and promocion_id is null and promo = 800 from public.venta_items
  where venta_id = (current_setting('prueba.v1')::jsonb ->> 'id')::bigint and producto_id = current_setting('prueba.alf2')::bigint), 'la venta conserva el nombre y lo descontado');

\echo == Todas las pruebas de promociones dieron bien
