-- =====================================================================
-- Pruebas: las promociones en Reportes. Usa las ventas con promociones del negocio C (37).
-- =====================================================================
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_carla'));
select set_config('prueba.rp', public.reporte_promos((public.promociones() ->> 'hoy')::date, (public.promociones() ->> 'hoy')::date)::text, false);
reset role;

\echo == Lo descontado en el período
select pruebas.ok((current_setting('prueba.rp')::jsonb ->> 'total')::numeric = (select sum(descuento_promos) from public.ventas
    where negocio_id = (select negocio_id from public.productos where id = current_setting('prueba.alf1')::bigint) and not anulada),
  'el total es lo descontado en las ventas del día');
select pruebas.ok((select (x ->> 'descuento')::numeric = 2400 and (x ->> 'ventas')::int = 2 and (x ->> 'unidades')::numeric = 8
    from jsonb_array_elements(current_setting('prueba.rp')::jsonb -> 'por_promo') x where x ->> 'nombre' = '3x2 alfajores'),
  'por promoción, con su nombre aunque se haya borrado: 1400 + 1000 en 2 ventas, 4 + 4 unidades con descuento');

\echo == Solo el dueño
set local role authenticated;
select pruebas.como('d0000000-0000-4000-8000-0000000000c3', current_setting('prueba.t_cami'));
select pruebas.falla('select public.reporte_promos(current_date, current_date)', 'dueño', 'el empleado no ve el reporte');
reset role;

\echo == Todas las pruebas del reporte de promociones dieron bien
