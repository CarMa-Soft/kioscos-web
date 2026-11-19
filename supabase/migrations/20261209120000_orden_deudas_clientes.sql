-- Cuenta de clientes: con el mismo vencimiento y la misma fecha (por ejemplo, cargadas en el mismo momento), las deudas
-- se ordenan por cómo se cargaron (el primer movimiento de cada una). Antes el orden quedaba al azar.
create or replace function public.deudas_cliente(p_cliente bigint)
returns table (venta_id bigint, deuda_id bigint, numero integer, concepto text, fecha timestamptz, vencimiento date,
               importe numeric, aplicado numeric, pendiente numeric, pagada timestamptz)
language sql stable security definer set search_path = '' as $$
  with cl as (select coalesce(c.plazo, public.plazo_clientes(c.negocio_id)) as plazo, public.zona_horaria(c.negocio_id) as z
              from public.clientes c where c.id = p_cliente),
  v as (select m.venta_id, sum(m.monto) as s, min(m.id) as primero from public.cc m where m.cliente_id = p_cliente and m.venta_id is not null group by m.venta_id),
  d as (
    select v.venta_id, null::bigint as deuda_id, ve.numero, 'Compra #' || ve.numero as concepto, ve.fecha, v.s as importe, v.primero as orden
      from v join public.ventas ve on ve.id = v.venta_id where v.s > 0
    union all
    select null, m.id, null, m.concepto, m.fecha, m.monto, m.id
      from public.cc m where m.cliente_id = p_cliente and m.venta_id is null and m.tipo = 'ajuste' and m.monto > 0)
  select d.venta_id, d.deuda_id, d.numero, d.concepto, d.fecha,
    (d.fecha at time zone (select z from cl))::date + (select plazo from cl) as vencimiento,
    d.importe, x.aplicado, d.importe - x.aplicado, case when d.importe - x.aplicado <= 0.004 then x.ultima end
  from d cross join lateral (
    select coalesce(sum(a.monto), 0) as aplicado, max(a.fecha) as ultima from public.aplicaciones_cli a
    where (d.venta_id is not null and a.venta_id = d.venta_id) or (d.deuda_id is not null and a.deuda_id = d.deuda_id)) x
  order by 6, d.fecha, d.orden;   -- con la misma fecha, en el orden en que se cargaron
$$;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 26, 'hora', now());
$$;
