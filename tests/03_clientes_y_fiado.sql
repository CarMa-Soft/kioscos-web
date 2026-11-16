-- =====================================================================
-- Pruebas: clientes y fiado (etapa 4a). Usa lo armado en 01 y 02 (misma transacción).
-- Al llegar acá: negocio A con turno abierto por Ana, productos Coca (dado de baja), Queso; Eva y Teo empleados.
-- =====================================================================

\echo == Clientes (Eva, empleada de A)
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select set_config('prueba.leche', public.guardar_producto('{"nombre": "Leche", "precio": "1000", "stock": "20"}') ->> 'id', false);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select set_config('prueba.juan', public.guardar_cliente('{"nombre": "Juan Pérez", "telefono": "1155"}') ->> 'id', false);
select pruebas.falla($$select public.guardar_cliente('{"nombre": " juan pérez "}')$$, 'Ya hay un cliente', 'no repite nombres');
select pruebas.falla($$select public.guardar_cliente('{"nombre": "Con límite", "limite": "5000"}')$$, 'solo el dueño', 'el empleado no pone límites de fiado');
select pruebas.ok(jsonb_array_length(public.clientes()) = 1 and (public.clientes() -> 0 ->> 'saldo')::numeric = 0, 'lista con saldo');

\echo == Venta fiada
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select public.guardar_cliente(jsonb_build_object('id', current_setting('prueba.juan'), 'nombre', 'Juan Pérez', 'limite', '2500'));
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Fiado", "monto": 1000}]')$$,
  current_setting('prueba.leche')), 'elegir el cliente', 'para fiar hace falta el cliente');
select set_config('prueba.vf', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 2}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Fiado", "monto": 1500}, {"forma": "Efectivo", "monto": 500}]', null, current_setting('prueba.juan')::bigint)::text, false);
select pruebas.ok(current_setting('prueba.vf')::jsonb -> 'cliente' ->> 'nombre' = 'Juan Pérez', 'la venta queda con el cliente');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = 1500, 'lo fiado queda en su cuenta');
select pruebas.ok((public.estado_caja() ->> 'fiado')::numeric = 1500, 'la caja muestra lo fiado del turno');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 2}]', '[{"forma": "Fiado", "monto": 2000}]', null, %s)$$,
  current_setting('prueba.leche'), current_setting('prueba.juan')), 'pasaría su límite', 'avisa si pasa el límite');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = 1500, 'si pasa el límite no se registra nada');
select pruebas.ok((public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 2}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Fiado", "monto": 2000}]', null, current_setting('prueba.juan')::bigint, true) ->> 'total')::numeric = 2000, 'confirmado, se puede pasar el límite');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = 3500, 'el saldo suma las dos');

\echo == Cobrar y ajustar
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select public.cobrar_cliente(current_setting('prueba.juan')::bigint, 1000, 'Efectivo');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = 2500, 'cobrar baja la deuda');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric + 1000, 'y entra a la caja');
select public.ajuste_cliente(current_setting('prueba.juan')::bigint, -500, 'Redondeo');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = 2000, 'el ajuste no mueve plata');
select pruebas.falla(format('select public.eliminar_cliente(%s)', current_setting('prueba.juan')), 'saldo pendiente', 'no se borra un cliente con deuda');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select pruebas.falla(format('select public.ajuste_cliente(%s, 100)', current_setting('prueba.juan')), 'solo lo puede hacer el dueño', 'el empleado no hace ajustes');
select pruebas.falla(format('select public.eliminar_cliente(%s)', current_setting('prueba.juan')), 'solo lo puede hacer el dueño', 'el empleado no borra clientes');

\echo == Anular una venta fiada
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select public.anular_venta((current_setting('prueba.vf')::jsonb ->> 'id')::bigint);
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = 500, 'anular devuelve lo fiado a la cuenta');

\echo == El otro negocio no ve ni toca clientes de A
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.t_beto'));
select pruebas.ok(jsonb_array_length(public.clientes()) = 0, 'B no ve los clientes de A');
select pruebas.falla(format('select public.cuenta_cliente(%s)', current_setting('prueba.juan')), 'Cliente no encontrado', 'B no ve la cuenta de un cliente de A');
select pruebas.falla(format($$select public.guardar_cliente('{"id": %s, "nombre": "Hackeado"}')$$, current_setting('prueba.juan')), 'Cliente no encontrado', 'B no edita un cliente de A');
select pruebas.falla(format($$select public.cobrar_cliente(%s, 10, 'Efectivo')$$, current_setting('prueba.juan')), 'Cliente no encontrado', 'B no cobra a un cliente de A');
select pruebas.falla(format($$select public.registrar_venta(gen_random_uuid(), '[{"producto_id": %s, "cantidad": 1}]', '[{"forma": "Fiado", "monto": 900}]', null, %s)$$,
  current_setting('prueba.coca_b'), current_setting('prueba.juan')), 'Cliente no encontrado', 'B no le fía a un cliente de A');
select pruebas.falla('select * from public.clientes', 'permission denied', 'nadie lee la tabla clientes directo');
select pruebas.falla('select * from public.cc', 'permission denied', 'nadie lee la tabla cc directo');

\echo == Todas las pruebas de clientes y fiado dieron bien
