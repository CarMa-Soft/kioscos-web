-- =====================================================================
-- Pruebas: aumentos masivos de precios (etapa 7). Usa el negocio C (07 a 11): Carla (dueña) y Cami (empleada).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.cat_aum', public.guardar_categoria(null, 'Secos') ->> 'id', false);
select set_config('prueba.fid', public.guardar_producto(jsonb_build_object('nombre', 'Fideos', 'categoria_id', current_setting('prueba.cat_aum'),
  'costo', 100, 'precio', 153)) ->> 'id', false);
select set_config('prueba.arr', public.guardar_producto(jsonb_build_object('nombre', 'Arroz', 'categoria_id', current_setting('prueba.cat_aum'),
  'costo', 200, 'precio', 300)) ->> 'id', false);
select set_config('prueba.ace', public.guardar_producto('{"nombre": "Aceite", "costo": 500, "precio": 1000}') ->> 'id', false);
select set_config('prueba.pa', public.guardar_proveedor('{"nombre": "Aceitera del Sur"}') ->> 'id', false);
select public.registrar_compra(jsonb_build_object('proveedor_id', current_setting('prueba.pa'), 'comprobante', 'A 0001-00000999',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.ace'), 'cantidad', 1, 'costo', 500))));

\echo == Por categoría, con el costo y redondeo
select set_config('prueba.a1', public.aumento_masivo(jsonb_build_object('alcance', 'categoria', 'categoria_id', current_setting('prueba.cat_aum'),
  'modo', 'pct', 'valor', 10, 'costo', true, 'redondear', true, 'descripcion', '+10% a Secos')) ->> 'id', false);
select pruebas.ok((pruebas.prod(current_setting('prueba.fid')) ->> 'precio')::numeric = 170 and (pruebas.prod(current_setting('prueba.fid')) ->> 'costo')::numeric = 110,
  '153 + 10% = 168,30 redondeado a 170; el costo 110');
select pruebas.ok((pruebas.prod(current_setting('prueba.arr')) ->> 'precio')::numeric = 330 and (pruebas.prod(current_setting('prueba.arr')) ->> 'costo')::numeric = 220,
  'Arroz 330 y costo 220');
select pruebas.ok((pruebas.prod(current_setting('prueba.ace')) ->> 'precio')::numeric = 1000, 'lo de otra categoría no cambia');

\echo == A productos elegidos, monto fijo, sin costo ni redondeo
select public.aumento_masivo(jsonb_build_object('alcance', 'ids', 'ids', jsonb_build_array(current_setting('prueba.fid')::bigint),
  'modo', 'monto', 'valor', '5', 'costo', false, 'redondear', false, 'descripcion', '+$5 a Fideos'));
select pruebas.ok((pruebas.prod(current_setting('prueba.fid')) ->> 'precio')::numeric = 175 and (pruebas.prod(current_setting('prueba.fid')) ->> 'costo')::numeric = 110,
  'monto fijo al precio, el costo no cambia');

\echo == Por proveedor, sin redondeo en Ajustes
select pruebas.ok(public.guardar_redondeo(0) = 0, 'guarda el redondeo');
select public.aumento_masivo(jsonb_build_object('alcance', 'proveedor', 'proveedor_id', current_setting('prueba.pa'),
  'modo', 'pct', 'valor', '-2,5', 'costo', false, 'redondear', true));
select pruebas.ok((pruebas.prod(current_setting('prueba.ace')) ->> 'precio')::numeric = 975, 'a los productos del proveedor (rebaja de 2,5%)');
select pruebas.ok((pruebas.prod(current_setting('prueba.arr')) ->> 'precio')::numeric = 330, 'los de otros proveedores no cambian');

\echo == Deshacer
select set_config('prueba.d', public.deshacer_aumento(current_setting('prueba.a1')::bigint)::text, false);
select pruebas.ok(current_setting('prueba.d')::jsonb = '{"revertidos": 1, "saltados": 1}'::jsonb, 'revierte uno y saltea el que cambió después');
select pruebas.ok((pruebas.prod(current_setting('prueba.arr')) ->> 'precio')::numeric = 300 and (pruebas.prod(current_setting('prueba.arr')) ->> 'costo')::numeric = 200,
  'Arroz vuelve a 300 y costo 200');
select pruebas.ok((pruebas.prod(current_setting('prueba.fid')) ->> 'precio')::numeric = 175, 'Fideos no se pisa');
select pruebas.falla(format('select public.deshacer_aumento(%s)', current_setting('prueba.a1')), 'ya se deshizo', 'no se deshace dos veces');
select pruebas.ok(jsonb_array_length(public.aumentos()) = 3 and (public.aumentos() -> 2 ->> 'deshecho')::boolean
  and public.aumentos() -> 2 ->> 'descripcion' = '+10% a Secos' and (public.aumentos() -> 2 ->> 'cantidad')::int = 2, 'la lista de aumentos');

\echo == Controles
select pruebas.falla($$select public.aumento_masivo('{"alcance": "todos", "modo": "pct", "valor": 0}')$$, 'Poné el aumento', 'aumento en cero');
select pruebas.falla($$select public.aumento_masivo('{"alcance": "todos", "modo": "pct", "valor": -100}')$$, 'entre -99 y 1000', 'no baja todo a cero');
select pruebas.falla($$select public.aumento_masivo('{"alcance": "todos", "modo": "otro", "valor": 5}')$$, 'porcentaje o un monto', 'modo inválido');
select pruebas.falla($$select public.aumento_masivo('{"alcance": "categoria", "categoria_id": 0, "modo": "pct", "valor": 5}')$$, 'Elegí la categoría', 'categoría que no existe');
select pruebas.falla($$select public.aumento_masivo('{"alcance": "ids", "ids": [0], "modo": "pct", "valor": 5}')$$, 'No hay productos', 'sin productos que coincidan');
select pruebas.falla($$select public.guardar_redondeo(-1)$$, 'entre 0 y 100000', 'redondeo negativo');
select pruebas.ok(jsonb_array_length(public.aumentos()) = 3, 'lo que falló no dejó aumentos');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.aumento_masivo('{"alcance": "todos", "modo": "pct", "valor": 5}')$$, 'solo lo puede hacer el dueño', 'el empleado no aumenta precios');
select pruebas.falla($$select public.aumentos()$$, 'solo lo puede hacer el dueño', 'el empleado no ve los aumentos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format($$select public.aumento_masivo('{"alcance": "ids", "ids": [%s], "modo": "pct", "valor": 5}')$$, current_setting('prueba.fid')),
  'No hay productos', 'A no aumenta productos de C');
select pruebas.falla(format('select public.deshacer_aumento(%s)', current_setting('prueba.a1')), 'No se encontró', 'A no deshace aumentos de C');
select pruebas.falla('select * from public.aumentos', 'permission denied', 'nadie lee la tabla aumentos directo');
reset role;

\echo == Todas las pruebas de aumentos masivos dieron bien
