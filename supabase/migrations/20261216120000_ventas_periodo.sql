-- =====================================================================
-- Descargar mis datos (Ajustes, solo el dueño): las ventas de un período, una por fila, para la planilla.
-- Hasta un año por vez. Fechas en la zona horaria del negocio.
-- =====================================================================
create or replace function public.ventas_periodo(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_tz text; v_d1 timestamptz; v_d2 timestamptz;
begin
  perform public.requiere_admin();
  if p_desde is null or p_hasta is null or p_hasta < p_desde then raise exception 'Revisá las fechas' using errcode = '22023'; end if;
  if p_hasta - p_desde > 366 then raise exception 'De a un año como máximo' using errcode = '22023'; end if;
  v_tz := public.zona_horaria(v_neg);
  v_d1 := p_desde::timestamp at time zone v_tz;
  v_d2 := (p_hasta + 1)::timestamp at time zone v_tz;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'numero', v.numero, 'fecha', v.fecha, 'total', v.total, 'devuelto', public.devuelto_venta(v.id), 'anulada', v.anulada,
      'vendio', public.nombre_usuario(v.usuario_id),
      'cliente', (select c.nombre from public.clientes c where c.id = v.cliente_id),
      'formas', (select string_agg(p.forma || ' $' || replace(p.monto::text, '.', ','), ' + ' order by p.id) from public.venta_pagos p where p.venta_id = v.id),
      'productos', (select string_agg(case when i.cantidad <> 1 then trim_scale(i.cantidad) || ' x ' else '' end || i.nombre, ', ' order by i.id)
                    from public.venta_items i where i.venta_id = v.id)) order by v.id)
    from public.ventas v where v.negocio_id = v_neg and v.fecha >= v_d1 and v.fecha < v_d2), '[]'::jsonb);
end;
$$;
revoke all on function public.ventas_periodo(date, date) from public, anon, authenticated;
grant execute on function public.ventas_periodo(date, date) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 33, 'hora', now());
$$;
