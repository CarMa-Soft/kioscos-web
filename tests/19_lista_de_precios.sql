-- =====================================================================
-- Pruebas: lista de precios e historial de precios. Usa el negocio C (07 a 18): Carla (dueña), Cami (empleada) y el
-- proveedor Aceitera del Sur (prueba.pa).
-- =====================================================================
create function pruebas.en_lista(p_filtro jsonb, p_id text) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.lista_precios(p_filtro)) x where x ->> 'id' = p_id;
$$;
grant execute on function pruebas.en_lista(jsonb, text) to authenticated;
-- el día de hoy en la zona horaria del negocio C (como postgres: las funciones internas no están abiertas a la app)
select set_config('prueba.hoy_c', (now() at time zone public.zona_horaria((select negocio_id from public.usuarios where id = current_setting('prueba.carla')::bigint)))::date::text, false);
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.cat_lp', public.guardar_categoria(null, 'Conservas') ->> 'id', false);
select set_config('prueba.ace2', public.guardar_producto(jsonb_build_object('nombre', 'Aceitunas verdes', 'codigo', '7790000000093',
  'categoria_id', current_setting('prueba.cat_lp'), 'costo', 600, 'precio', 1000)) ->> 'id', false);
select set_config('prueba.pr', public.guardar_producto('{"nombre": "Pan rallado", "costo": 300, "precio": 700}') ->> 'id', false);

\echo == Historial de precios
select public.guardar_producto(jsonb_build_object('id', current_setting('prueba.ace2'), 'nombre', 'Aceitunas verdes', 'codigo', '7790000000093',
  'categoria_id', current_setting('prueba.cat_lp'), 'costo', 600, 'precio', 1200));
select pruebas.ok((pruebas.en_lista(jsonb_build_object('precio_desde', current_setting('prueba.hoy_c')), current_setting('prueba.ace2')) ->> 'precio_antes')::numeric = 1000
  and (pruebas.en_lista(jsonb_build_object('precio_desde', current_setting('prueba.hoy_c')), current_setting('prueba.ace2')) ->> 'precio')::numeric = 1200,
  'cambiaron de precio hoy: trae el precio de antes y el nuevo');
select pruebas.ok(pruebas.en_lista(jsonb_build_object('precio_desde', current_setting('prueba.hoy_c')), current_setting('prueba.pr')) is null,
  'el que no cambió de precio no está');
select pruebas.ok(pruebas.en_lista(jsonb_build_object('precio_desde', (current_setting('prueba.hoy_c')::date + 1)::text), current_setting('prueba.ace2')) is null,
  'desde mañana no hay cambios');
select public.aumento_masivo(jsonb_build_object('alcance', 'ids', 'ids', jsonb_build_array(current_setting('prueba.ace2')::bigint), 'modo', 'monto', 'valor', 100));
select pruebas.ok((pruebas.en_lista(jsonb_build_object('precio_desde', current_setting('prueba.hoy_c')), current_setting('prueba.ace2')) ->> 'precio_antes')::numeric = 1000
  and (pruebas.en_lista(jsonb_build_object('precio_desde', current_setting('prueba.hoy_c')), current_setting('prueba.ace2')) ->> 'precio')::numeric = 1300,
  'con dos cambios, el de antes es el del primero (1000) y el precio el actual (1300)');

\echo == Llegaron en compras
select set_config('prueba.cpr', public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0009-00000019',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.pr'), 'cantidad', 6, 'costo', 320)))) ->> 'id', false);
select pruebas.ok(pruebas.en_lista(jsonb_build_object('compra_ids', jsonb_build_array(current_setting('prueba.cpr')::bigint)), current_setting('prueba.pr')) ->> 'llego' is not null
  and pruebas.en_lista(jsonb_build_object('compra_ids', jsonb_build_array(current_setting('prueba.cpr')::bigint)), current_setting('prueba.ace2')) is null,
  'de una compra: solo lo que llegó en ella');
select pruebas.ok(pruebas.en_lista(jsonb_build_object('compras_desde', current_setting('prueba.hoy_c')), current_setting('prueba.pr')) is not null,
  'compras desde hoy');
select pruebas.ok((pruebas.en_lista('{}', current_setting('prueba.pr')) ->> 'costo')::numeric = 320, 'trae el costo (lo cambió la compra)');

\echo == Otros filtros
select pruebas.ok(pruebas.en_lista(jsonb_build_object('categoria_id', current_setting('prueba.cat_lp')), current_setting('prueba.ace2')) ->> 'categoria' = 'Conservas'
  and pruebas.en_lista(jsonb_build_object('categoria_id', current_setting('prueba.cat_lp')), current_setting('prueba.pr')) is null, 'por categoría');
select pruebas.ok(pruebas.en_lista(jsonb_build_object('proveedor_id', current_setting('prueba.pa')), current_setting('prueba.pr')) is not null, 'por proveedor');
select pruebas.ok(pruebas.en_lista('{"texto": "aceituna"}', current_setting('prueba.ace2')) is not null
  and pruebas.en_lista('{"texto": "7790000000093"}', current_setting('prueba.ace2')) is not null
  and pruebas.en_lista('{"texto": "aceituna"}', current_setting('prueba.pr')) is null, 'por nombre o código');
select pruebas.ok(pruebas.en_lista(jsonb_build_object('categoria_id', current_setting('prueba.cat_lp'), 'compra_ids', jsonb_build_array(current_setting('prueba.cpr')::bigint)),
  current_setting('prueba.ace2')) is null, 'los filtros se combinan');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.lista_precios('{}')$$, 'solo lo puede hacer el dueño', 'el empleado no ve la lista con costos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(pruebas.en_lista('{}', current_setting('prueba.ace2')) is null, 'A no ve productos de C');
select pruebas.falla('select * from public.cambios_precio', 'permission denied', 'nadie lee la tabla cambios_precio directo');
reset role;

\echo == Todas las pruebas de lista de precios dieron bien
