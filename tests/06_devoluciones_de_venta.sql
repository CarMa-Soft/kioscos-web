-- =====================================================================
-- Pruebas: devoluciones de venta (etapa 4d). Usa lo armado en 01 a 05.
-- Al llegar acá: negocio A sin turno abierto; Leche a $1000; recargos Crédito 10% y Fiado 5%; cliente Juan.
-- =====================================================================
-- ayuda: stock de un producto según el catálogo (se crea antes de pasar a usuario común)
create function pruebas.stock(p_id text) returns numeric language sql as $$
  select (p ->> 'stock')::numeric from jsonb_array_elements(public.catalogo() -> 'productos') p where p ->> 'id' = p_id;
$$;
grant execute on function pruebas.stock(text) to authenticated;
set local role authenticated;

\echo == Preparación
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select public.abrir_turno(10000);
-- 3 leches con $300 de descuento, con crédito (+10%): base 2700 + 270 = 2970 (factor 0,99)
select set_config('prueba.vd', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 3}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Crédito", "base": 2700}]', null, null, false, 300)::text, false);
select pruebas.ok((current_setting('prueba.vd')::jsonb ->> 'total')::numeric = 2970, 'venta de prueba: 2970');
select set_config('prueba.vd_item', current_setting('prueba.vd')::jsonb -> 'items' -> 0 ->> 'id', false);
select set_config('prueba.stock0', pruebas.stock(current_setting('prueba.leche'))::text, false);

\echo == El empleado necesita autorización
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": %s, "cantidad": 1}]', 'Efectivo')$$,
  current_setting('prueba.vd')::jsonb ->> 'id', current_setting('prueba.vd_item')), 'autorización del dueño', 'el empleado no devuelve sin el PIN del dueño');

\echo == Devoluciones parciales (Ana)
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select set_config('prueba.d1', public.devolver_venta((current_setting('prueba.vd')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1}]', current_setting('prueba.vd_item'))::jsonb, 'Efectivo', 'No le gustó')::text, false);
select pruebas.ok((current_setting('prueba.d1')::jsonb -> 'devolucion' ->> 'total')::numeric = 990, 'reintegra lo que pagó por eso, con descuento y recargo (990)');
select pruebas.ok(current_setting('prueba.d1')::jsonb -> 'devolucion' ->> 'etiqueta' = 'DV-0001', 'numeración propia por negocio: DV-0001');
select pruebas.ok(pruebas.stock(current_setting('prueba.leche')) = current_setting('prueba.stock0')::numeric + 1, 'vuelve al stock');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric - 990, 'sale de la caja en efectivo');
select pruebas.ok((current_setting('prueba.d1')::jsonb -> 'items' -> 0 ->> 'devuelto')::numeric = 1 and (current_setting('prueba.d1')::jsonb ->> 'devuelto')::numeric = 990,
  'la venta muestra lo devuelto');
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": %s, "cantidad": 3}]', 'Efectivo')$$,
  current_setting('prueba.vd')::jsonb ->> 'id', current_setting('prueba.vd_item')), 'hasta 2', 'no deja devolver más de lo que queda');
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": %s, "cantidad": 0.5}]', 'Efectivo')$$,
  current_setting('prueba.vd')::jsonb ->> 'id', current_setting('prueba.vd_item')), 'tiene que ser entera', 'un producto por unidad se devuelve entero');
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": %s, "cantidad": 1}]', 'Fiado')$$,
  current_setting('prueba.vd')::jsonb ->> 'id', current_setting('prueba.vd_item')), 'no tiene cliente', 'sin cliente no se deja en la cuenta');
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": 1, "cantidad": 1}]', 'Efectivo')$$,
  current_setting('prueba.vd')::jsonb ->> 'id'), 'no es de esta venta', 'solo renglones de esa venta');
-- una roto (no vuelve al stock), por crédito
select public.devolver_venta((current_setting('prueba.vd')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1, "vuelve_stock": false}]', current_setting('prueba.vd_item'))::jsonb, 'Crédito', 'Vencida');
select pruebas.ok(pruebas.stock(current_setting('prueba.leche')) = current_setting('prueba.stock0')::numeric + 1, 'lo roto no vuelve al stock');
-- la última: vuelve todo lo que quedaba, justo lo que falta
select pruebas.ok((public.devolver_venta((current_setting('prueba.vd')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1}]', current_setting('prueba.vd_item'))::jsonb, 'Efectivo') ->> 'devuelto')::numeric = 2970,
  'devuelto todo, se reintegró justo el total');
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": %s, "cantidad": 1}]', 'Efectivo')$$,
  current_setting('prueba.vd')::jsonb ->> 'id', current_setting('prueba.vd_item')), 'ya se devolvió completo', 'no se devuelve dos veces');

\echo == Anular una venta con devoluciones
select set_config('prueba.va', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 2}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Efectivo", "base": 2000}]')::text, false);
select public.devolver_venta((current_setting('prueba.va')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1}]', current_setting('prueba.va')::jsonb -> 'items' -> 0 ->> 'id')::jsonb, 'Efectivo');
select set_config('prueba.stock1', pruebas.stock(current_setting('prueba.leche'))::text, false);
select set_config('prueba.esp', public.estado_caja() -> 'turno' ->> 'esperado', false);
select public.anular_venta((current_setting('prueba.va')::jsonb ->> 'id')::bigint);
select pruebas.ok(pruebas.stock(current_setting('prueba.leche')) = current_setting('prueba.stock1')::numeric + 1, 'anular devuelve solo el stock que quedó');
select pruebas.ok((public.estado_caja() -> 'turno' ->> 'esperado')::numeric = current_setting('prueba.esp')::numeric - 1000, 'y solo la plata que quedó');
select pruebas.falla(format($$select public.devolver_venta(%s, '[{"id": %s, "cantidad": 1}]', 'Efectivo')$$,
  current_setting('prueba.va')::jsonb ->> 'id', current_setting('prueba.va')::jsonb -> 'items' -> 0 ->> 'id'), 'está anulada', 'no se devuelve de una venta anulada');

\echo == Devolución a la cuenta del cliente, por un empleado autorizado
select set_config('prueba.vf', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.leche'))::jsonb,
  '[{"forma": "Fiado", "base": 1000}]', null, current_setting('prueba.juan')::bigint, true)::text, false);
select set_config('prueba.saldo', public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo', false);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_eva'));
select set_config('prueba.aut', public.autorizar_dueno(current_setting('prueba.ana')::bigint, '1111') ->> 'token', false);
select set_config('prueba.d2', public.devolver_venta((current_setting('prueba.vf')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1}]', current_setting('prueba.vf')::jsonb -> 'items' -> 0 ->> 'id')::jsonb, 'Fiado', null, current_setting('prueba.aut')::uuid)::text, false);
select pruebas.ok(current_setting('prueba.d2')::jsonb -> 'devoluciones' -> 0 ->> 'autorizo' = 'Ana', 'con autorización devuelve y queda quién autorizó');
select pruebas.ok((public.cuenta_cliente(current_setting('prueba.juan')::bigint) ->> 'saldo')::numeric = current_setting('prueba.saldo')::numeric - 1050,
  'a la cuenta: se descuenta lo que pagó (con el recargo de fiado)');

\echo == El otro negocio no toca devoluciones de A
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.t_beto'));
select pruebas.falla(format($$select public.devolver_venta(%s, '[]', 'Efectivo')$$, current_setting('prueba.vf')::jsonb ->> 'id'), 'Venta no encontrada', 'B no devuelve una venta de A');
select pruebas.falla('select * from public.devoluciones', 'permission denied', 'nadie lee la tabla devoluciones directo');
reset role;

\echo == Todas las pruebas de devoluciones dieron bien
