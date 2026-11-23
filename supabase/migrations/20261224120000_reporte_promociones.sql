-- =====================================================================
-- Reportes: las promociones del período (lo descontado, en cuántas ventas y cuántas unidades, por promoción).
-- Aparte de reporte() para no tocarla: Reportes pide las dos. Lo descontado está en venta_items.promo (por renglón) y se
-- agrupa por el nombre que tenía la promoción al vender (sigue apareciendo aunque después se haya borrado o cambiado).
-- Ventas anuladas, no. Las devoluciones no restan lo descontado (el cliente sí tuvo la promoción al comprar).
-- =====================================================================
create or replace function public.reporte_promos(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_tz text; v_d1 timestamptz; v_d2 timestamptz;
begin
  perform public.requiere_admin();
  if p_desde is null or p_hasta is null or p_hasta < p_desde then raise exception 'Rango de fechas inválido' using errcode = '22023'; end if;
  if p_hasta - p_desde > 400 then raise exception 'El período no puede pasar de 400 días' using errcode = '22023'; end if;
  v_tz := public.zona_horaria(v_neg);
  v_d1 := p_desde::timestamp at time zone v_tz;
  v_d2 := (p_hasta + 1)::timestamp at time zone v_tz;
  return (
    with its as (
      select i.venta_id, i.cantidad, i.promo, coalesce(i.promo_nombre, 'Promoción') as nombre
      from public.venta_items i join public.ventas v on v.id = i.venta_id
      where v.negocio_id = v_neg and not v.anulada and v.fecha >= v_d1 and v.fecha < v_d2 and i.promo > 0
    )
    select jsonb_build_object(
      'total', (select coalesce(sum(promo), 0) from its),
      'ventas', (select count(distinct venta_id) from its),
      'por_promo', coalesce((select jsonb_agg(jsonb_build_object('nombre', nombre, 'ventas', ventas, 'unidades', unidades, 'descuento', descuento)
                                              order by descuento desc, nombre)
        from (select nombre, count(distinct venta_id) as ventas, sum(cantidad) as unidades, sum(promo) as descuento from its group by nombre) x), '[]'::jsonb)));
end;
$$;

revoke all on function public.reporte_promos(date, date) from public, anon, authenticated;
grant execute on function public.reporte_promos(date, date) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 41, 'hora', now());
$$;
