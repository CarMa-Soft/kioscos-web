-- =====================================================================
-- Pruebas: entradas y salidas de mercadería (etapa 6). Usa el negocio C (07 a 10): Carla (dueña), Cami (empleada),
-- Yerba (p1) y Galletitas (p2).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.s1', pruebas.prod(current_setting('prueba.p1')) ->> 'stock', false);
select set_config('prueba.s2', pruebas.prod(current_setting('prueba.p2')) ->> 'stock', false);

\echo == Motivos
select pruebas.ok(public.motivos_remito() -> 'egreso' ? 'Vencido', 'trae los motivos de fábrica');
select pruebas.ok(public.guardar_motivos_remito('{"ingreso": [" Sobrante ", "Sobrante", ""], "egreso": ["Vencido", "Rotura"]}')
  = '{"ingreso": ["Sobrante"], "egreso": ["Vencido", "Rotura"]}'::jsonb, 'guarda los motivos sin repetidos ni vacíos');
select pruebas.falla($$select public.guardar_motivos_remito('{"ingreso": [], "egreso": ["Vencido"]}')$$, 'al menos un motivo de entrada', 'no deja una lista vacía');

\echo == Salida
select set_config('prueba.re', public.registrar_remito(jsonb_build_object('tipo', 'egreso', 'motivo', 'Vencido', 'notas', 'lote viejo',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 2),
                             jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 1),
                             jsonb_build_object('producto_id', current_setting('prueba.p2'), 'cantidad', '0,5')))))::text, false);
select pruebas.ok(current_setting('prueba.re')::jsonb ->> 'etiqueta' = 'RE-0001', 'la primera salida es RE-0001');
select pruebas.ok(jsonb_array_length(current_setting('prueba.re')::jsonb -> 'items') = 2
  and (current_setting('prueba.re')::jsonb -> 'items' @> jsonb_build_array(jsonb_build_object('nombre', 'Yerba', 'cantidad', 3))), 'el mismo producto dos veces se suma');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.s1')::numeric - 3
  and (pruebas.prod(current_setting('prueba.p2')) ->> 'stock')::numeric = current_setting('prueba.s2')::numeric - 0.5, 'resta el stock');
select pruebas.ok((current_setting('prueba.re')::jsonb -> 'items' -> 0 ->> 'stock_antes')::numeric
  - (current_setting('prueba.re')::jsonb -> 'items' -> 0 ->> 'stock_despues')::numeric = 3, 'guarda el stock antes y después');
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.remitos('egreso')) r where r ->> 'etiqueta' = 'RE-0001' and (r ->> 'items')::int = 2),
  'aparece en la lista de salidas');

\echo == Entrada
select set_config('prueba.ri', public.registrar_remito(jsonb_build_object('tipo', 'ingreso', 'motivo', 'Sobrante',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p1'), 'cantidad', 5)))) ->> 'id', false);
select pruebas.ok(public.remito(current_setting('prueba.ri')::bigint) ->> 'etiqueta' = 'RI-0001', 'las entradas se numeran aparte (RI-0001)');
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.s1')::numeric + 2, 'suma el stock');
select pruebas.ok(jsonb_array_length(public.remitos('ingreso')) = 1 and jsonb_array_length(public.remitos(null)) = 2, 'filtra por tipo');

\echo == Stock negativo
select set_config('prueba.neg', public.registrar_remito(jsonb_build_object('tipo', 'egreso', 'motivo', 'Robo',
  'items', jsonb_build_array(jsonb_build_object('producto_id', current_setting('prueba.p2'), 'cantidad', 1000))))::text, false);
select pruebas.ok(current_setting('prueba.neg')::jsonb -> 'stock_negativo' = '["Galletitas"]'::jsonb, 'avisa qué quedó con stock negativo');

\echo == Anular
select public.anular_remito((current_setting('prueba.neg')::jsonb ->> 'id')::bigint);
select pruebas.ok((pruebas.prod(current_setting('prueba.p2')) ->> 'stock')::numeric = current_setting('prueba.s2')::numeric - 0.5, 'anular una salida devuelve el stock');
select public.anular_remito(current_setting('prueba.ri')::bigint);
select pruebas.ok((pruebas.prod(current_setting('prueba.p1')) ->> 'stock')::numeric = current_setting('prueba.s1')::numeric - 3, 'anular una entrada lo descuenta');
select pruebas.ok((public.remito(current_setting('prueba.ri')::bigint) ->> 'anulado')::boolean
  and public.remito(current_setting('prueba.ri')::bigint) ->> 'anulado_por' = 'Carla', 'queda anulada y quién lo hizo');
select pruebas.falla(format('select public.anular_remito(%s)', current_setting('prueba.ri')), 'Ya estaba anulada', 'no se anula dos veces');

\echo == Controles
select pruebas.falla(format($$select public.registrar_remito('{"tipo": "otro", "motivo": "x", "items": [{"producto_id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.p1')), 'entrada o una salida', 'tipo inválido');
select pruebas.falla(format($$select public.registrar_remito('{"tipo": "egreso", "motivo": " ", "items": [{"producto_id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.p1')), 'Elegí el motivo', 'sin motivo');
select pruebas.falla($$select public.registrar_remito('{"tipo": "egreso", "motivo": "Vencido", "items": []}')$$, 'ningún producto', 'sin productos');
select pruebas.falla(format($$select public.registrar_remito('{"tipo": "egreso", "motivo": "Vencido", "items": [{"producto_id": %s, "cantidad": 0}]}')$$,
  current_setting('prueba.p1')), 'Cantidad en 0', 'cantidad en cero');
select pruebas.ok(jsonb_array_length(public.remitos('egreso')) = 2, 'lo que falló no dejó nada a medias');

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla($$select public.remitos(null)$$, 'solo lo puede hacer el dueño', 'el empleado no ve las entradas y salidas');
select pruebas.falla(format($$select public.registrar_remito('{"tipo": "egreso", "motivo": "Vencido", "items": [{"producto_id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.p1')), 'solo lo puede hacer el dueño', 'el empleado no registra salidas');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format('select public.remito(%s)', current_setting('prueba.ri')), 'No se encontró', 'A no ve las entradas de C');
select pruebas.falla(format($$select public.registrar_remito('{"tipo": "egreso", "motivo": "Vencido", "items": [{"producto_id": %s, "cantidad": 1}]}')$$,
  current_setting('prueba.p1')), 'Producto no encontrado', 'A no mueve el stock de C');
select pruebas.ok(jsonb_array_length(public.remitos(null)) = 0, 'A no tiene entradas ni salidas');
select pruebas.falla('select * from public.remitos', 'permission denied', 'nadie lee la tabla remitos directo');
reset role;

\echo == Todas las pruebas de entradas y salidas dieron bien
