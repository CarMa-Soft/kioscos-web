-- =====================================================================
-- Pruebas: descuentos, recargos y autorización del dueño (etapa 4b). Usa lo armado en 01 a 03.
-- Al llegar acá: negocio A con el turno de Ana abierto; Leche a $1000; Eva y Teo empleados (PIN 5555 y 6666).
-- =====================================================================
set local role authenticated;

\echo == Ajustes del cobro
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select pruebas.falla($$select public.guardar_ajustes_cobro('["Efectivo"]', '{}', 10)$$, 'solo lo puede hacer el dueño', 'el empleado no cambia los ajustes del cobro');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.falla($$select public.guardar_ajustes_cobro('["Crédito"]', '{"Crédito": 150}', 10)$$, 'entre 0 y 100', 'el recargo no pasa del 100%');
select pruebas.ok(public.guardar_ajustes_cobro('["Crédito", "Débito", "Fiado", " Débito "]', '{"Crédito": "10", "Fiado": 5, "Efectivo": 20}', 10)
  = '{"formas_pago": ["Efectivo", "Crédito", "Débito"], "recargos": {"Crédito": 10, "Fiado": 5}, "tope_descuento": 10}',
  'Efectivo siempre primero, sin repetidos ni Fiado en la lista; Efectivo nunca lleva recargo');
select pruebas.ok(public.estado_caja() -> 'recargos' = '{"Crédito": 10, "Fiado": 5}' and (public.estado_caja() ->> 'tope_descuento')::numeric = 10,
  'la caja informa recargos y tope');

\echo == Recargos (Ana)
select set_config('prueba.vr', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Crédito", "base": 1000}]')::text, false);
select pruebas.ok((current_setting('prueba.vr')::jsonb ->> 'total')::numeric = 1100 and (current_setting('prueba.vr')::jsonb ->> 'recargo')::numeric = 100,
  'crédito con 10%: 1000 + 100');
select pruebas.ok((current_setting('prueba.vr')::jsonb -> 'pagos' -> 0 ->> 'monto')::numeric = 1100, 'el pago queda con el recargo');
select set_config('prueba.vm', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Efectivo", "base": 333}, {"forma": "Crédito", "base": 667}]')::text, false);
select pruebas.ok((current_setting('prueba.vm')::jsonb ->> 'total')::numeric = 1067, 'dos medios: el recargo solo sobre la parte con crédito, redondeado a pesos');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Crédito", "base": 1100}]')$$,
  current_setting('prueba.leche')), 'no suman el total', 'las bases suman la venta sin recargo');
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select public.anular_venta((current_setting('prueba.vr')::jsonb ->> 'id')::bigint);
select pruebas.ok((public.estado_caja() -> 'por_forma' ->> 'Crédito')::numeric = 667 + 67, 'anular devuelve el pago con su recargo');

\echo == Descuentos del dueño (sin tope)
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 2, "precio": 700}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Efectivo", "base": 1300}]', null, null, false, 100) ->> 'total')::numeric = 1300, 'el dueño rebaja el renglón y hace descuento general sin autorización');

\echo == Tope del empleado
select public.cerrar_turno(0);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select public.abrir_turno(0);
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Efectivo", "base": 950}]', null, null, false, 50) ->> 'descuento')::numeric = 50, 'dentro del tope (5%) no hace falta autorización');
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1, "precio": 1500}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Efectivo", "base": 1500}]') ->> 'descuento_renglones')::numeric = 0, 'cobrar más caro no cuenta como descuento');
select set_config('prueba.items_desc', format('[{"producto_id": %s, "cantidad": 1, "precio": 800}]', current_setting('prueba.leche')), false);
select pruebas.falla($$select public.registrar_venta(gen_random_uuid(), current_setting('prueba.items_desc')::jsonb, '[{"forma": "Efectivo", "base": 800}]')$$,
  'del 20.0% y tu tope es 10%', 'pasado el tope pide autorización (rebaja en el renglón)');
select pruebas.falla($$select public.registrar_venta(gen_random_uuid(), current_setting('prueba.items_desc')::jsonb, '[{"forma": "Efectivo", "base": 800}]', null, null, false, 0, gen_random_uuid())$$,
  'autorización del dueño', 'un permiso inventado no sirve');
select pruebas.ok(public.autorizar_dueno(current_setting('prueba.ana')::bigint, '0000') ->> 'error' = 'PIN incorrecto', 'PIN del dueño incorrecto');
select pruebas.ok(public.autorizar_dueno(current_setting('prueba.eva')::bigint, '5555') ->> 'error' = 'Dueño no encontrado', 'un empleado no autoriza');
select set_config('prueba.aut', public.autorizar_dueno(current_setting('prueba.ana')::bigint, '1111') ->> 'token', false);
select set_config('prueba.vd', public.registrar_venta(gen_random_uuid(), current_setting('prueba.items_desc')::jsonb, '[{"forma": "Efectivo", "base": 800}]',
  null, null, false, 0, current_setting('prueba.aut')::uuid)::text, false);
select pruebas.ok(current_setting('prueba.vd')::jsonb ->> 'autorizo' = 'Ana', 'con la autorización se registra y queda quién autorizó');
select pruebas.falla($$select public.registrar_venta(gen_random_uuid(), current_setting('prueba.items_desc')::jsonb, '[{"forma": "Efectivo", "base": 800}]', null, null, false, 0, current_setting('prueba.aut')::uuid)$$,
  'autorización del dueño', 'el permiso sirve una sola vez');

\echo == El permiso es de quien lo pidió
select set_config('prueba.aut2', public.autorizar_dueno(current_setting('prueba.ana')::bigint, '1111') ->> 'token', false);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_teo'));
select pruebas.falla($$select public.registrar_venta(gen_random_uuid(), current_setting('prueba.items_desc')::jsonb, '[{"forma": "Efectivo", "base": 800}]', null, null, false, 0, current_setting('prueba.aut2')::uuid)$$,
  'autorización del dueño|turno abierto es de Eva', 'otro empleado no usa el permiso de Eva');
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.t_beto'));
select pruebas.ok(public.autorizar_dueno(current_setting('prueba.ana')::bigint, '1111') ->> 'error' = 'Dueño no encontrado', 'B no usa al dueño de A');

\echo == Cinco PIN incorrectos bloquean al dueño
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
do $$ begin
  for i in 1..5 loop perform public.autorizar_dueno(current_setting('prueba.ana')::bigint, '0000'); end loop;
end $$;
select pruebas.ok(public.autorizar_dueno(current_setting('prueba.ana')::bigint, '1111') ->> 'error' ~ '^Demasiados intentos', 'adivinar el PIN del dueño se bloquea');
reset role;
update public.usuarios set bloqueado_hasta = null, intentos = 0 where id = current_setting('prueba.ana')::bigint;

\echo == Todas las pruebas de descuentos y recargos dieron bien
