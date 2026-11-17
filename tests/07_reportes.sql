-- =====================================================================
-- Pruebas: Inicio y Reportes (etapa 4e). Usa un negocio nuevo (C) para poder controlar los números exactos.
-- =====================================================================

\echo == Negocio C, solo para estas pruebas
insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('d0000000-0000-4000-8000-0000000000c3', 'authenticated', 'authenticated', 'local.c@prueba.test', now(), now()),
  ('d0000000-0000-4000-8000-0000000000d3', 'authenticated', 'authenticated', 'dueno.c@prueba.test', now(), now());
select set_config('prueba.neg_c', public.admin_alta_negocio('Prueba C', 'dueno.c@prueba.test', 'local.c@prueba.test', 'Carla', '3333')::text, false);
select set_config('prueba.carla', (select id from public.usuarios where nombre = 'Carla' and negocio_id = current_setting('prueba.neg_c')::uuid)::text, false);
select set_config('prueba.hoy', ((now() at time zone 'America/Argentina/Buenos_Aires')::date)::text, false);
set local role authenticated;

select pruebas.como('d0000000-0000-4000-8000-0000000000c3');
select set_config('prueba.t_carla', public.iniciar_usuario(current_setting('prueba.carla')::bigint, '3333') ->> 'token', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.cami', public.guardar_usuario(null, 'Cami', 'empleado', true, '4444') ->> 'id', false);
select set_config('prueba.cat_c', public.guardar_categoria(null, 'Almacén') ->> 'id', false);
select set_config('prueba.p1', public.guardar_producto(jsonb_build_object('nombre', 'Yerba', 'categoria_id', current_setting('prueba.cat_c'),
  'costo', 600, 'precio', 1000, 'stock', 10)) ->> 'id', false);
select set_config('prueba.p2', public.guardar_producto('{"nombre": "Galletitas", "costo": 200, "precio": 500, "stock": 5}') ->> 'id', false);
select public.abrir_turno(0);
-- venta 1: 2 yerbas en efectivo (2000); venta 2: yerba + galletitas con débito (1500); venta 3: yerba, anulada
select set_config('prueba.c1', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 2}]', current_setting('prueba.p1'))::jsonb,
  '[{"forma": "Efectivo", "base": 2000}]')::text, false);
select set_config('prueba.c2', public.registrar_venta(gen_random_uuid(),
  format('[{"producto_id": %s, "cantidad": 1}, {"producto_id": %s, "cantidad": 1}]', current_setting('prueba.p1'), current_setting('prueba.p2'))::jsonb,
  '[{"forma": "Débito", "base": 1500}]')::text, false);
select set_config('prueba.c3', public.registrar_venta(gen_random_uuid(), format('[{"producto_id": %s, "cantidad": 1}]', current_setting('prueba.p1'))::jsonb,
  '[{"forma": "Efectivo", "base": 1000}]')::text, false);
select public.anular_venta((current_setting('prueba.c3')::jsonb ->> 'id')::bigint);
-- devolución 1: una yerba de la venta 1, vuelve al stock (1000); devolución 2: las galletitas de la venta 2, rotas (500)
select public.devolver_venta((current_setting('prueba.c1')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1}]', current_setting('prueba.c1')::jsonb -> 'items' -> 0 ->> 'id')::jsonb, 'Efectivo');
select public.devolver_venta((current_setting('prueba.c2')::jsonb ->> 'id')::bigint,
  format('[{"id": %s, "cantidad": 1, "vuelve_stock": false}]', current_setting('prueba.c2')::jsonb -> 'items' -> 1 ->> 'id')::jsonb, 'Débito');

\echo == Reporte del día (Carla, dueña)
select set_config('prueba.rep', public.reporte(current_setting('prueba.hoy')::date, current_setting('prueba.hoy')::date)::text, false);
select pruebas.ok((current_setting('prueba.rep')::jsonb ->> 'tickets')::int = 2, 'cuenta las ventas, sin la anulada');
select pruebas.ok((current_setting('prueba.rep')::jsonb ->> 'vendido')::numeric = 3500, 'vendido: 3500');
select pruebas.ok((current_setting('prueba.rep')::jsonb ->> 'total')::numeric = 2000, 'total: lo vendido menos las devoluciones (2000)');
select pruebas.ok((current_setting('prueba.rep')::jsonb ->> 'costo')::numeric = 1400, 'costo: recupera lo que volvió al stock, no lo roto (1400)');
select pruebas.ok(current_setting('prueba.rep')::jsonb -> 'devoluciones' = '{"total": 1500, "cantidad": 2, "perdidas": 200}'::jsonb, 'devoluciones y pérdidas');
select pruebas.ok(current_setting('prueba.rep')::jsonb -> 'por_forma' @> '[{"forma": "Efectivo", "total": 1000}, {"forma": "Débito", "total": 1000}]',
  'por forma de pago, con las devoluciones restadas');
select pruebas.ok(current_setting('prueba.rep')::jsonb -> 'productos' @> '[{"nombre": "Yerba", "cantidad": 2, "importe": 2000, "costo": 1200}]',
  'por producto: lo que quedó vendido');
select pruebas.ok(current_setting('prueba.rep')::jsonb -> 'por_categoria' @> '[{"categoria": "Almacén", "importe": 2000}, {"categoria": "Sin categoría", "costo": 200}]',
  'por categoría');
select pruebas.ok(current_setting('prueba.rep')::jsonb -> 'por_usuario' = '[{"nombre": "Carla", "total": 2000}]'::jsonb, 'por vendedor');
select pruebas.ok((select sum((x ->> 'total')::numeric) from jsonb_array_elements(current_setting('prueba.rep')::jsonb -> 'por_dia') x) = 2000
  and (select sum((x ->> 'total')::numeric) from jsonb_array_elements(current_setting('prueba.rep')::jsonb -> 'por_hora') x) = 2000, 'por día y por hora suman el total');
select pruebas.ok(current_setting('prueba.rep')::jsonb -> 'mercaderia' = '{"costo": 5600, "venta": 10000}'::jsonb, 'mercadería valorizada al costo y a precio de venta');
select pruebas.ok((current_setting('prueba.rep')::jsonb ->> 'fiado_pendiente')::numeric = 0, 'fiado pendiente');
select pruebas.falla($$select public.reporte('2026-01-10', '2026-01-01')$$, 'Rango de fechas inválido', 'rango al revés');
select pruebas.falla($$select public.reporte('2024-01-01', '2026-01-01')$$, 'no puede pasar de 400 días', 'período demasiado largo');
select pruebas.ok((public.reporte(current_setting('prueba.hoy')::date - 10, current_setting('prueba.hoy')::date - 1) ->> 'tickets')::int = 0, 'otros días no tienen estas ventas');

\echo == Inicio
select set_config('prueba.ini', public.inicio()::text, false);
select pruebas.ok((current_setting('prueba.ini')::jsonb ->> 'tickets')::int = 2 and (current_setting('prueba.ini')::jsonb ->> 'total')::numeric = 2000
  and (current_setting('prueba.ini')::jsonb ->> 'ganancia')::numeric = 600, 'la dueña ve las ventas de hoy y la ganancia (600)');
select pruebas.ok(jsonb_array_length(current_setting('prueba.ini')::jsonb -> 'ultimas') = 2, 'últimas ventas, sin la anulada');
select pruebas.como('d0000000-0000-4000-8000-0000000000c3');
select set_config('prueba.t_cami', public.iniciar_usuario(current_setting('prueba.cami')::bigint, '4444') ->> 'token', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.ok((public.inicio() ->> 'tickets')::int = 0 and jsonb_typeof(public.inicio() -> 'ganancia') = 'null' and (public.inicio() ->> 'propias')::boolean,
  'el empleado ve solo sus ventas y no ve la ganancia');
select pruebas.falla($$select public.reporte(current_date, current_date)$$, 'solo lo puede hacer el dueño', 'el empleado no ve los reportes');

\echo == Cada negocio ve lo suyo
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.t_ana'));
select pruebas.ok(not (public.reporte(current_setting('prueba.hoy')::date, current_setting('prueba.hoy')::date) -> 'productos' @> '[{"nombre": "Yerba"}]'),
  'A no ve los productos vendidos por C');
reset role;

\echo == Todas las pruebas de reportes dieron bien
