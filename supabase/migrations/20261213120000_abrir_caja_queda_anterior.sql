-- =====================================================================
-- Abrir la caja desde Vender: estado_caja(), con la caja cerrada, trae queda_anterior (el efectivo que quedó al cerrar el
-- último turno: contado − retiro) para proponerlo como efectivo inicial.
-- =====================================================================
create or replace function public.estado_caja()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); t public.turnos;
begin
  perform public.requiere_usuario();
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then
    -- queda_anterior: el efectivo que quedó en la caja al cerrar el último turno (contado − retiro), para proponerlo al abrir
    return public.config_cobro(v_neg) || jsonb_build_object('turno', null, 'queda_anterior',
      (select greatest(t2.contado - coalesce(t2.retiro, 0), 0) from public.turnos t2
        where t2.negocio_id = v_neg and t2.cierre is not null and t2.contado is not null order by t2.cierre desc limit 1));
  end if;
  return public.config_cobro(v_neg) || jsonb_build_object(
    'turno', jsonb_build_object('id', t.id, 'usuario_id', t.usuario_id, 'usuario', public.nombre_usuario(t.usuario_id),
      'apertura', t.apertura, 'inicial', t.inicial, 'esperado', public.efectivo_esperado(t.id)),
    'por_forma', coalesce((select jsonb_object_agg(forma, total) from (
        select c.forma, sum(case when c.tipo = 'ingreso' then c.monto else -c.monto end) as total
        from public.caja c where c.turno_id = t.id group by c.forma) x), '{}'::jsonb),
    'fiado', coalesce((select sum(p.monto) from public.venta_pagos p join public.ventas v on v.id = p.venta_id
        where v.turno_id = t.id and not v.anulada and p.forma = 'Fiado'), 0),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.fecha, 'tipo', c.tipo, 'concepto', c.concepto,
        'monto', c.monto, 'forma', c.forma, 'venta_id', c.venta_id, 'manual', c.manual, 'usuario', public.nombre_usuario(c.usuario_id)) order by c.id desc)
      from public.caja c where c.turno_id = t.id), '[]'::jsonb),
    'ventas', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'total', v.total,
        'devuelto', public.devuelto_venta(v.id),
        'anulada', v.anulada, 'usuario', public.nombre_usuario(v.usuario_id),
        'cliente', (select c.nombre from public.clientes c where c.id = v.cliente_id),
        'fiado', exists (select 1 from public.venta_pagos p where p.venta_id = v.id and p.forma = 'Fiado'),
        'descuento', v.descuento + v.descuento_renglones, 'recargo', v.recargo,
        'resumen', (select string_agg(i.nombre, ', ' order by i.id) from public.venta_items i where i.venta_id = v.id)) order by v.id desc)
      from public.ventas v where v.turno_id = t.id), '[]'::jsonb));
end;
$$;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 30, 'hora', now());
$$;
