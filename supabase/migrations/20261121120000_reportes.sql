-- =====================================================================
-- Etapa 4e: Inicio y Reportes
--
-- Mismas cuentas que la app local:
--   - Las devoluciones se restan en la fecha de la devolución (las de ventas anuladas no: la venta ya no cuenta).
--   - Costo = costo de lo vendido − costo de lo que volvió al stock; lo roto o vencido sigue como costo (es pérdida).
--   - El descuento general y los recargos de cada venta se reparten entre sus renglones (importe × total / subtotal).
-- Los días son los de la hora local del negocio (config 'zona_horaria', por defecto Argentina).
-- Reportes: solo el dueño. Inicio: el empleado ve solo sus ventas y no ve costos ni ganancia.
-- =====================================================================

create or replace function public.zona_horaria(p_neg uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select c.valor #>> '{}' from public.config c where c.negocio_id = p_neg and c.clave = 'zona_horaria'
                   and jsonb_typeof(c.valor) = 'string'), 'America/Argentina/Buenos_Aires');
$$;

-- Fiado pendiente: lo que deben los clientes (solo saldos a favor del negocio)
create or replace function public.fiado_pendiente(p_neg uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(s), 0) from (select sum(monto) as s from public.cc where negocio_id = p_neg group by cliente_id) x where s > 0;
$$;

-- ---------------------------------------------------------------------
-- Reportes (solo dueño): del día p_desde al día p_hasta inclusive
-- ---------------------------------------------------------------------
create or replace function public.reporte(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_tz text; v_d1 timestamptz; v_d2 timestamptz; r jsonb;
begin
  perform public.requiere_admin();
  if p_desde is null or p_hasta is null or p_hasta < p_desde then raise exception 'Rango de fechas inválido' using errcode = '22023'; end if;
  if p_hasta - p_desde > 400 then raise exception 'El período no puede pasar de 400 días' using errcode = '22023'; end if;
  v_tz := public.zona_horaria(v_neg);
  v_d1 := p_desde::timestamp at time zone v_tz;
  v_d2 := (p_hasta + 1)::timestamp at time zone v_tz;

  with
  vs as (select * from public.ventas where negocio_id = v_neg and not anulada and fecha >= v_d1 and fecha < v_d2),
  ds as (select dv.*, vv.usuario_id as vendedor from public.devoluciones dv join public.ventas vv on vv.id = dv.venta_id
         where dv.negocio_id = v_neg and not vv.anulada and dv.fecha >= v_d1 and dv.fecha < v_d2),
  vis as (select i.*, case when vs.subtotal > 0 then i.importe * vs.total / vs.subtotal else i.importe end as imp
          from public.venta_items i join vs on vs.id = i.venta_id),
  dis as (select x.*, case when x.vuelve_stock then x.cantidad * x.costo else 0 end as costo_rec
          from public.devolucion_items x join ds on ds.id = x.devolucion_id),
  -- ventas (+) y devoluciones (−) juntas, para agrupar
  mov as (select fecha, total, usuario_id as vendedor from vs union all select fecha, -total, vendedor from ds)
  select jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'tickets', (select count(*) from vs),
    'vendido', (select coalesce(sum(total), 0) from vs),
    'total', (select coalesce(sum(total), 0) from mov),
    'costo', round((select coalesce(sum(cantidad * costo), 0) from vis) - (select coalesce(sum(costo_rec), 0) from dis), 2),
    'devoluciones', jsonb_build_object('total', (select coalesce(sum(total), 0) from ds), 'cantidad', (select count(*) from ds),
      'perdidas', round((select coalesce(sum(cantidad * costo), 0) from dis where not vuelve_stock), 2)),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'total', t) order by dia), '[]'::jsonb)
                from (select (fecha at time zone v_tz)::date as dia, sum(total) as t from mov group by 1) x),
    'por_hora', (select coalesce(jsonb_agg(jsonb_build_object('hora', h, 'total', t) order by h), '[]'::jsonb)
                 from (select extract(hour from fecha at time zone v_tz)::int as h, sum(total) as t from mov group by 1) x),
    'por_forma', (select coalesce(jsonb_agg(jsonb_build_object('forma', forma, 'total', t) order by t desc), '[]'::jsonb)
                  from (select forma, sum(m) as t from (
                          select p.forma, p.monto as m from public.venta_pagos p join vs on vs.id = p.venta_id
                          union all select forma, -total from ds) y group by forma) x),
    'por_usuario', (select coalesce(jsonb_agg(jsonb_build_object('nombre', public.nombre_usuario(vendedor), 'total', t) order by t desc), '[]'::jsonb)
                    from (select vendedor, sum(total) as t from mov group by vendedor) x),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'por_peso', por_peso, 'cantidad', cantidad,
                    'importe', round(importe, 2), 'costo', round(costo, 2)) order by importe desc), '[]'::jsonb)
                  from (select max(nombre) as nombre, bool_or(por_peso) as por_peso, sum(c) as cantidad, sum(i) as importe, sum(k) as costo
                        from (select coalesce(producto_id::text, 'v:' || nombre) as clave, nombre, por_peso, cantidad as c, imp as i, cantidad * costo as k from vis
                              union all
                              select coalesce(producto_id::text, 'v:' || nombre), nombre, por_peso, -cantidad, -importe, -costo_rec from dis) y
                        group by clave order by sum(i) desc limit 100) x),
    'por_categoria', (select coalesce(jsonb_agg(jsonb_build_object('categoria', coalesce(c.nombre, 'Sin categoría'), 'importe', round(x.importe, 2),
                        'costo', round(x.costo, 2)) order by x.importe desc), '[]'::jsonb)
                      from (select categoria_id, sum(i) as importe, sum(k) as costo
                            from (select categoria_id, imp as i, cantidad * costo as k from vis
                                  union all select categoria_id, -importe, -costo_rec from dis) y group by categoria_id) x
                      left join public.categorias c on c.id = x.categoria_id),
    'descuentos', (select jsonb_build_object('general', coalesce(sum(descuento), 0), 'renglones', coalesce(sum(descuento_renglones), 0),
                     'recargo', coalesce(sum(recargo), 0),
                     'ventas_con_descuento', count(*) filter (where descuento > 0 or descuento_renglones > 0),
                     'autorizadas', count(*) filter (where autorizo_id is not null)) from vs),
    'recargos_por_forma', (select coalesce(jsonb_agg(jsonb_build_object('forma', forma, 'recargo', t) order by t desc), '[]'::jsonb)
                           from (select p.forma, sum(p.recargo) as t from public.venta_pagos p join vs on vs.id = p.venta_id
                                 where p.recargo > 0 group by p.forma) x),
    'descuentos_por_usuario', (select coalesce(jsonb_agg(jsonb_build_object('nombre', public.nombre_usuario(usuario_id), 'general', g, 'renglones', rg,
                                 'ventas', n) order by g + rg desc), '[]'::jsonb)
                               from (select usuario_id, sum(descuento) as g, sum(descuento_renglones) as rg, count(*) as n from vs
                                     where descuento > 0 or descuento_renglones > 0 group by usuario_id) x),
    'autorizaciones', (select coalesce(jsonb_agg(jsonb_build_object('numero', numero, 'fecha', fecha, 'vendio', public.nombre_usuario(usuario_id),
                         'autorizo', public.nombre_usuario(autorizo_id), 'descuento', descuento + descuento_renglones, 'subtotal', subtotal) order by id desc), '[]'::jsonb)
                       from (select * from vs where autorizo_id is not null order by id desc limit 100) x),
    'mercaderia', (select jsonb_build_object('costo', round(coalesce(sum(greatest(stock, 0) * costo), 0), 2),
                     'venta', round(coalesce(sum(greatest(stock, 0) * precio), 0), 2))
                   from public.productos where negocio_id = v_neg and activo),
    'fiado_pendiente', public.fiado_pendiente(v_neg)
  ) into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------
-- Inicio: lo de hoy. El empleado ve solo sus ventas; la ganancia, solo el dueño.
-- ---------------------------------------------------------------------
create or replace function public.inicio()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); v_admin boolean := public.es_admin();
  v_tz text; v_d1 timestamptz; v_d2 timestamptz; t public.turnos; r jsonb;
begin
  v_tz := public.zona_horaria(v_neg);
  v_d1 := (now() at time zone v_tz)::date::timestamp at time zone v_tz;
  v_d2 := v_d1 + interval '1 day';
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  with
  vs as (select * from public.ventas where negocio_id = v_neg and not anulada and fecha >= v_d1 and fecha < v_d2 and (v_admin or usuario_id = v_u)),
  ds as (select dv.* from public.devoluciones dv join public.ventas vv on vv.id = dv.venta_id
         where dv.negocio_id = v_neg and not vv.anulada and dv.fecha >= v_d1 and dv.fecha < v_d2 and (v_admin or vv.usuario_id = v_u))
  select jsonb_build_object(
    'propias', not v_admin,
    'tickets', (select count(*) from vs),
    'devuelto', (select coalesce(sum(total), 0) from ds),
    'total', (select coalesce(sum(total), 0) from vs) - (select coalesce(sum(total), 0) from ds),
    'ganancia', case when v_admin then
        (select coalesce(sum(total), 0) from vs) - (select coalesce(sum(total), 0) from ds)
        - (select coalesce(sum(i.cantidad * i.costo), 0) from public.venta_items i join vs on vs.id = i.venta_id)
        + (select coalesce(sum(x.cantidad * x.costo), 0) from public.devolucion_items x join ds on ds.id = x.devolucion_id where x.vuelve_stock)
      end,
    'ultimas', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'numero', numero, 'fecha', fecha, 'total', total,
        'devuelto', public.devuelto_venta(id), 'usuario', public.nombre_usuario(usuario_id),
        'resumen', (select string_agg(i.nombre, ', ' order by i.id) from public.venta_items i where i.venta_id = x.id)) order by id desc), '[]'::jsonb)
      from (select * from vs order by id desc limit 8) x),
    'turno', case when t.id is null then null else jsonb_build_object('usuario', public.nombre_usuario(t.usuario_id), 'apertura', t.apertura,
        'esperado', public.efectivo_esperado(t.id)) end,
    'fiado_pendiente', public.fiado_pendiente(v_neg)
  ) into r;
  return r;
end;
$$;

revoke all on function public.zona_horaria(uuid), public.fiado_pendiente(uuid), public.reporte(date, date), public.inicio()
  from public, anon, authenticated;
grant execute on function public.reporte(date, date), public.inicio() to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 8, 'hora', now());
$$;
