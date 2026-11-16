-- =====================================================================
-- Pruebas: etiquetas de balanza, cierre por billetes y turnos anteriores (etapa 4c). Usa lo armado en 01 a 04.
-- Al llegar acá: negocio A con el turno de Eva abierto; Queso por kilo a $8000; Ana dueña, Eva y Teo empleados.
-- =====================================================================
set local role authenticated;

\echo == Ajustes de balanza y billetes
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select pruebas.falla($$select public.guardar_ajustes_caja('{"activa": true}', '[1000]')$$, 'solo lo puede hacer el dueño', 'el empleado no cambia la balanza ni los billetes');
select pruebas.ok(public.estado_caja() -> 'balanza' ->> 'activa' = 'false' and jsonb_array_length(public.estado_caja() -> 'billetes') = 10,
  'por defecto: balanza apagada y la lista de billetes de la app local');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(public.guardar_ajustes_caja('{"activa": true, "prefijo": "2a0", "tipo": "importe"}', '["10000", "1000", 500, "500", "0"]')
  = '{"balanza": {"activa": true, "prefijo": "20", "tipo": "importe"}, "billetes": [10000, 1000, 500]}', 'limpia el prefijo y ordena los billetes sin repetir');
select pruebas.falla($$select public.guardar_ajustes_caja('{}', '["x"]')$$, 'Billete: valor inválido', 'un billete tiene que ser un número');
select pruebas.falla($$select public.guardar_ajustes_caja('{"tipo": "otro"}', '[1000]')$$, 'Tipo de etiqueta inválido', 'tipo de etiqueta inválido');
select pruebas.falla($$select public.guardar_ajustes_caja('{}', '[0, -5]')$$, 'al menos un billete|inválido', 'hace falta al menos un billete');
select public.guardar_ajustes_caja('{"activa": true, "prefijo": "20", "tipo": "importe"}', '[10000, 1000, 500, 100]');
select pruebas.ok(public.estado_caja() -> 'balanza' = '{"activa": true, "prefijo": "20", "tipo": "importe"}'
  and public.estado_caja() -> 'billetes' = '[10000, 1000, 500, 100]', 'la caja informa balanza y billetes');

\echo == Etiqueta con importe
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
-- 0,437 kg de queso a $8000 = $3496: la etiqueta trae $3496
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 0.437, "importe": 3496}]', current_setting('prueba.queso'))::jsonb,
  '[{"forma": "Efectivo", "base": 3496}]') ->> 'total')::numeric = 3496, 'cobra el importe de la etiqueta');
-- la etiqueta dice $3499 por 0,437 kg (redondeo de medio gramo: hasta $4 de diferencia)
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 0.437, "importe": 3499}]', current_setting('prueba.queso'))::jsonb,
  '[{"forma": "Efectivo", "base": 3499}]') ->> 'total')::numeric = 3499, 'acepta la diferencia del redondeo de los kilos');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 0.437, "importe": 1000}]', '[{"forma": "Efectivo", "base": 1000}]')$$,
  current_setting('prueba.queso')), 'no coincide con el peso', 'no sirve para cobrar menos');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1, "importe": 1}]', '[{"forma": "Efectivo", "base": 1}]')$$,
  current_setting('prueba.leche')), 'Solo un producto por peso', 'un producto por unidad no lleva importe');

\echo == Cierre por billetes
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select pruebas.falla($$select public.cerrar_turno(null, 0, null, '{"1000": 2.5}')$$, 'no es válido', 'las cantidades de billetes son enteras');
select pruebas.falla($$select public.cerrar_turno(null, 0, null, '{"abc": 2}')$$, 'no es válido', 'los valores de billetes son números');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_teo'));
select pruebas.falla($$select public.cerrar_turno(null, 0, null, '{"1000": 1}')$$, 'Solo quien abrió', 'otro empleado no cierra el turno de Eva');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
-- se cuentan $100 menos que lo esperado
select set_config('prueba.cierre', public.cerrar_turno(null, 0, 'cajón trabado', jsonb_build_object('1000', floor((current_setting('prueba.esp')::numeric - 100) / 1000)),
  (current_setting('prueba.esp')::numeric - 100) - floor((current_setting('prueba.esp')::numeric - 100) / 1000) * 1000, true)::text, false);
select pruebas.ok((current_setting('prueba.cierre')::jsonb ->> 'diferencia')::numeric = -100, 'el contado lo calcula la base: faltan 100');
select pruebas.ok(current_setting('prueba.cierre')::jsonb -> 'billetes' -> 'detalle' ? '1000', 'guarda el detalle de billetes');
select pruebas.ok(exists (select 1 from jsonb_array_elements(current_setting('prueba.cierre')::jsonb -> 'movimientos') m
  where m ->> 'concepto' = 'Faltante de caja al cierre — cajón trabado' and (m ->> 'monto')::numeric = 100 and (m ->> 'ajuste')::boolean),
  'el faltante queda en los movimientos, marcado como ajuste');
select pruebas.ok((current_setting('prueba.cierre')::jsonb ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric, 'el esperado guardado no cambia');

\echo == Turnos anteriores
select pruebas.ok(jsonb_array_length(public.turnos_anteriores()) >= 1
  and not exists (select 1 from jsonb_array_elements(public.turnos_anteriores()) x where x ->> 'usuario' <> 'Eva'), 'el empleado ve solo sus turnos');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_teo'));
select pruebas.falla(format('select public.turno(%s)', current_setting('prueba.cierre')::jsonb ->> 'id'), 'Turno no encontrado', 'otro empleado no ve un turno ajeno');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(exists (select 1 from jsonb_array_elements(public.turnos_anteriores()) x where x ->> 'usuario' = 'Ana')
  and exists (select 1 from jsonb_array_elements(public.turnos_anteriores()) x where x ->> 'usuario' = 'Eva'), 'el dueño ve todos los turnos');
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.t_beto'));
select pruebas.ok(not exists (select 1 from jsonb_array_elements(public.turnos_anteriores()) x where x ->> 'usuario' in ('Ana', 'Eva')), 'B no ve los turnos de A');
select pruebas.falla(format('select public.turno(%s)', current_setting('prueba.cierre')::jsonb ->> 'id'), 'Turno no encontrado', 'B no ve un turno de A');
reset role;

\echo == Todas las pruebas de balanza y billetes dieron bien
