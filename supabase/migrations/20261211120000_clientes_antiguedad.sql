-- =====================================================================
-- Clientes: para ordenar la lista por antigüedad de la deuda. clientes() suma a cada cliente:
--   deuda_desde: la fecha de la compra (o deuda) pendiente más vieja; null si no debe nada
--   vence:       el vencimiento más próximo (o más vencido) de lo pendiente; null si no debe nada
--   ultimo:      la fecha del último movimiento de su cuenta (compra fiada, pago o ajuste)
-- =====================================================================
create or replace function public.clientes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_usuario();
  return coalesce((select jsonb_agg(public.cliente_json(c) || jsonb_build_object('deuda_desde', d.desde, 'vence', d.vence, 'ultimo', d.ultimo)
      order by lower(c.nombre))
    from public.clientes c
    cross join lateral (
      select (select max(m.fecha) from public.cc m where m.cliente_id = c.id) as ultimo,
             x.desde, x.vence
      from (select min(p.fecha) as desde, min(p.vencimiento) as vence from public.deudas_cliente(c.id) p where p.pendiente > 0.004) x) d
    where c.negocio_id = v_neg and (c.activo or public.saldo_cliente(c.id) <> 0)), '[]'::jsonb);
end;
$$;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 28, 'hora', now());
$$;
