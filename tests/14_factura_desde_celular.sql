-- =====================================================================
-- Pruebas: mandar la factura desde el celular (etapa 8b). Usa el negocio C (07 a 13): Carla (dueña), Cami (empleada).
-- Lo de la función de Supabase "subir-factura" (clave de servicio) se prueba como postgres (sin rol).
-- La 13 dejó C al tope de 60 lecturas por día: acá se borran esas lecturas para poder probar.
-- =====================================================================
delete from public.lecturas_ia where negocio_id = (select negocio_id from public.usuarios where id = current_setting('prueba.carla')::bigint);
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));

\echo == La PC pide un código
select set_config('prueba.sub', public.crear_subida_celular()::text, false);
select set_config('prueba.cod', current_setting('prueba.sub')::jsonb ->> 'codigo', false);
select set_config('prueba.sid', current_setting('prueba.sub')::jsonb ->> 'id', false);
select pruebas.ok(length(current_setting('prueba.cod')) = 48 and (current_setting('prueba.sub')::jsonb ->> 'minutos')::int = 15, 'código de 48 caracteres, 15 minutos');
select pruebas.ok(public.estado_subida_celular(current_setting('prueba.sid')::bigint) ->> 'estado' = 'esperando', 'esperando la foto');
select pruebas.falla(format('select public.tomar_subida_celular(%L, 1)', current_setting('prueba.cod')), 'permission denied', 'el navegador no toma códigos');
reset role;

\echo == El celular manda las fotos (función de Supabase)
select pruebas.ok(public.revisar_subida_celular(current_setting('prueba.cod')) ->> 'estado' = 'esperando'
  and public.revisar_subida_celular(current_setting('prueba.cod')) ->> 'negocio' is not null, 'el celular ve que el código sirve y de qué negocio es');
select pruebas.falla($$select public.revisar_subida_celular('cualquiera')$$, 'ya no sirve', 'un código inventado no sirve');
select pruebas.ok((public.tomar_subida_celular(current_setting('prueba.cod'), 2) ->> 'id')::bigint = current_setting('prueba.sid')::bigint, 'toma el código');
select pruebas.falla(format('select public.tomar_subida_celular(%L, 1)', current_setting('prueba.cod')), 'Ya se está leyendo', 'no se toma dos veces a la vez');
select public.terminar_subida_celular(current_setting('prueba.sid')::bigint, null, 'La IA no pudo leer la foto');
set local role authenticated;
select pruebas.ok(public.estado_subida_celular(current_setting('prueba.sid')::bigint) ->> 'error' = 'La IA no pudo leer la foto', 'la PC ve el error');
reset role;
select public.tomar_subida_celular(current_setting('prueba.cod'), 1);
select public.terminar_subida_celular(current_setting('prueba.sid')::bigint, '{"factura": {"items": [{"descripcion": "YERBA"}]}, "uso": {"costo_usd": 0.02}}', null);
set local role authenticated;

\echo == La PC recibe la factura una sola vez
select set_config('prueba.est', public.estado_subida_celular(current_setting('prueba.sid')::bigint)::text, false);
select pruebas.ok(current_setting('prueba.est')::jsonb ->> 'estado' = 'lista' and current_setting('prueba.est')::jsonb #>> '{resultado,factura,items,0,descripcion}' = 'YERBA'
  and (current_setting('prueba.est')::jsonb ->> 'paginas')::int = 1, 'después de un error se volvió a mandar y llegó');
select pruebas.ok(public.estado_subida_celular(current_setting('prueba.sid')::bigint) ->> 'estado' = 'entregada', 'se entrega una sola vez');
reset role;
select pruebas.falla(format('select public.revisar_subida_celular(%L)', current_setting('prueba.cod')), 'ya no sirve', 'el código ya usado no sirve más');
set local role authenticated;

\echo == Cancelar y vencer
select set_config('prueba.sub2', public.crear_subida_celular()::text, false);
select public.cancelar_subida_celular((current_setting('prueba.sub2')::jsonb ->> 'id')::bigint);
reset role;
select pruebas.falla(format('select public.tomar_subida_celular(%L, 1)', current_setting('prueba.sub2')::jsonb ->> 'codigo'), 'ya no sirve', 'el código cancelado no sirve');
set local role authenticated;
select set_config('prueba.sub3', public.crear_subida_celular()::text, false);
reset role;
update public.subidas_celular set vence = now() - interval '1 minute' where id = (current_setting('prueba.sub3')::jsonb ->> 'id')::bigint;
select pruebas.falla(format('select public.tomar_subida_celular(%L, 1)', current_setting('prueba.sub3')::jsonb ->> 'codigo'), 'venció', 'el código vencido no sirve');
set local role authenticated;
select pruebas.ok(public.estado_subida_celular((current_setting('prueba.sub3')::jsonb ->> 'id')::bigint) ->> 'estado' = 'vencido', 'la PC ve que venció');
select set_config('prueba.sub4', public.crear_subida_celular()::text, false);
reset role;
select pruebas.ok(public.revisar_subida_celular(current_setting('prueba.sub4')::jsonb ->> 'codigo') ->> 'estado' = 'esperando', 'el código nuevo sirve');
select pruebas.ok(not exists (select 1 from information_schema.columns where table_name = 'subidas_celular' and column_name = 'codigo'), 'la tabla no guarda el código');
set local role authenticated;

\echo == Empleado y otro negocio
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla('select public.crear_subida_celular()', 'solo lo puede hacer el dueño', 'el empleado no pide códigos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla(format('select public.estado_subida_celular(%s)', current_setting('prueba.sid')), 'No se encontró', 'A no ve los pedidos de C');
select pruebas.falla('select * from public.subidas_celular', 'permission denied', 'nadie lee la tabla subidas_celular directo');
reset role;

\echo == Todas las pruebas de factura desde el celular dieron bien
