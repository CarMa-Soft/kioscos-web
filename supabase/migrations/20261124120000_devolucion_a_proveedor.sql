-- =====================================================================
-- Etapa 5c: devolución a proveedor (como la app local, #7 etapa 2)
--
-- Desde la compra se devuelve parte o toda: DP-0001, numeración propia por negocio. Siempre sale el stock de lo devuelto
-- (aunque quede negativo). Importe = costo de la compra × cantidad, editable (el proveedor puede acreditar otro monto).
-- Qué pasa con la plata (forma):
--   'Cuenta'        = a cuenta del proveedor: baja lo que se le debe (se aplica sola a esa factura) o queda a favor.
--   forma de pago   = devolvió la plata: entra a la caja; en la cuenta va la devolución y un 'reintegro' que la compensa.
--   'Sin reintegro' = solo para compras sin proveedor.
-- Anular una compra con devoluciones anula solo lo que quedó.
-- =====================================================================

alter table public.cc_prov drop constraint cc_prov_tipo_check;
alter table public.cc_prov add constraint cc_prov_tipo_check check (tipo in ('compra', 'pago', 'ajuste', 'anulacion', 'devolucion', 'reintegro'));
alter table public.cc_prov add column par_id bigint;     -- el reintegro apunta a su devolución (se compensan)

create table public.devoluciones_compra (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  numero integer not null,
  compra_id bigint not null,
  fecha timestamptz not null default now(),
  usuario_id bigint not null,
  turno_id bigint,
  forma text not null,
  total numeric(14, 2) not null check (total >= 0),
  motivo text,
  unique (id, negocio_id),
  unique (negocio_id, numero),
  foreign key (compra_id, negocio_id) references public.compras (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id)
);
create index devoluciones_compra_compra on public.devoluciones_compra (compra_id);

create table public.devolucion_compra_items (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  devolucion_id bigint not null,
  compra_item_id bigint not null,
  producto_id bigint not null,
  nombre text not null,
  cantidad numeric(14, 3) not null check (cantidad > 0),
  costo numeric(14, 2) not null,
  importe numeric(14, 2) not null,
  foreign key (devolucion_id, negocio_id) references public.devoluciones_compra (id, negocio_id) on delete cascade,
  foreign key (compra_item_id, negocio_id) references public.compra_items (id, negocio_id)
);
create index devolucion_compra_items_compra_item on public.devolucion_compra_items (compra_item_id);

alter table public.devoluciones_compra enable row level security;
alter table public.devolucion_compra_items enable row level security;
revoke all on public.devoluciones_compra, public.devolucion_compra_items from anon, authenticated;

create or replace function public.devuelto_compra_item(p_item bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(cantidad), 0) from public.devolucion_compra_items where compra_item_id = p_item;
$$;

-- Créditos: ahora también las devoluciones a cuenta (las que el proveedor pagó en plata se compensan con su reintegro)
create or replace function public.creditos_proveedor(p_proveedor bigint)
returns table (id bigint, compra_id bigint, fecha timestamptz, importe numeric, aplicado numeric, libre numeric)
language sql stable security definer set search_path = '' as $$
  select m.id, m.compra_id, m.fecha, -m.monto,
    (select coalesce(sum(a.monto), 0) from public.aplicaciones_prov a where a.credito_id = m.id),
    -m.monto - (select coalesce(sum(a.monto), 0) from public.aplicaciones_prov a where a.credito_id = m.id)
  from public.cc_prov m
  where m.proveedor_id = p_proveedor and not m.anulado and m.monto < 0
    and (m.tipo = 'pago' or (m.tipo = 'ajuste' and m.compra_id is null)
         or (m.tipo = 'devolucion' and not exists (select 1 from public.cc_prov r where r.par_id = m.id)))
    and (m.compra_id is null or not (select c.anulada from public.compras c where c.id = m.compra_id))
  order by m.id;
$$;

create or replace function public.compra_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'fecha', c.fecha, 'proveedor_id', c.proveedor_id,
    'proveedor', (select p.nombre from public.proveedores p where p.id = c.proveedor_id),
    'comprobante', c.comprobante, 'remito', c.remito, 'factura_pendiente', c.factura_pendiente, 'fecha_factura', c.fecha_factura,
    'vencimiento', c.vencimiento, 'factura_fecha', c.factura_fecha, 'factura_por', case when c.factura_por is not null then public.nombre_usuario(c.factura_por) end,
    'notas', c.notas, 'total', c.total, 'pagada_caja', c.pagada_caja, 'forma', c.forma,
    'usuario', public.nombre_usuario(c.usuario_id), 'anulada', c.anulada, 'anulada_fecha', c.anulada_fecha,
    'anulada_por', case when c.anulada then public.nombre_usuario(c.anulada_por) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'costo', i.costo, 'costo_remito', i.costo_remito, 'precio_nuevo', i.precio_nuevo, 'costo_anterior', i.costo_anterior,
                         'precio_anterior', i.precio_anterior, 'devuelto', public.devuelto_compra_item(i.id)) order by i.id)
                       from public.compra_items i where i.compra_id = c.id), '[]'::jsonb),
    'devuelto', (select coalesce(sum(d.total), 0) from public.devoluciones_compra d where d.compra_id = c.id),
    'devoluciones', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'etiqueta', 'DP-' || lpad(d.numero::text, 4, '0'), 'fecha', d.fecha,
        'usuario', public.nombre_usuario(d.usuario_id), 'forma', d.forma, 'total', d.total, 'motivo', d.motivo,
        'items', (select jsonb_agg(jsonb_build_object('nombre', x.nombre, 'cantidad', x.cantidad, 'importe', x.importe) order by x.id)
                  from public.devolucion_compra_items x where x.devolucion_id = d.id)) order by d.id)
      from public.devoluciones_compra d where d.compra_id = c.id), '[]'::jsonb))
  from public.compras c where c.id = p_id;
$$;

-- p: { compra_id, items: [{ id (renglón de la compra), cantidad }], total? (si no, costo × cantidad), forma, motivo }
create or replace function public.devolver_compra(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); c public.compras; r public.proveedores; t public.turnos;
  x jsonb; i public.compra_items; v_cant numeric; v_queda numeric; v_suma numeric := 0; v_n integer := 0; v_total numeric;
  v_forma text := coalesce(p ->> 'forma', ''); v_plata boolean; v_dev bigint; v_num integer; v_etq text; v_mov bigint; v_pend numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into c from public.compras where id = nullif(p ->> 'compra_id', '')::bigint and negocio_id = v_neg for update;
  if not found then raise exception 'Compra no encontrada' using errcode = 'P0002'; end if;
  if c.anulada then raise exception 'La compra está anulada' using errcode = 'P0001'; end if;
  if c.proveedor_id is not null then r := public.requiere_proveedor(c.proveedor_id); end if;
  if v_forma = 'Cuenta' then
    if r.id is null then raise exception 'La compra no tiene proveedor: no hay cuenta a la que acreditarlo' using errcode = '22023'; end if;
  elsif v_forma = 'Sin reintegro' then
    if r.id is not null then raise exception 'Con proveedor, la devolución va a su cuenta o devuelve la plata' using errcode = '22023'; end if;
  elsif not (v_forma = any (public.formas_pago(v_neg))) then
    raise exception 'Elegí qué pasa con la plata' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' then raise exception 'Elegí qué productos devolvés' using errcode = '22023'; end if;
  v_num := coalesce((select max(numero) from public.devoluciones_compra where negocio_id = v_neg), 0) + 1;
  v_etq := 'Devolución DP-' || lpad(v_num::text, 4, '0') || coalesce(' a ' || r.nombre, '');
  insert into public.devoluciones_compra (negocio_id, numero, compra_id, usuario_id, forma, total, motivo)
    values (v_neg, v_num, c.id, v_u, v_forma, 0, nullif(left(btrim(coalesce(p ->> 'motivo', '')), 200), '')) returning id into v_dev;
  for x in select value from jsonb_array_elements(p -> 'items') loop
    select * into i from public.compra_items where id = nullif(x ->> 'id', '')::bigint and compra_id = c.id;
    if not found then raise exception 'Hay un producto que no es de esta compra' using errcode = 'P0002'; end if;
    v_cant := round(public.num(x, 'cantidad', 'Cantidad de ' || i.nombre), 3);
    if v_cant is null or v_cant <= 0 then continue; end if;
    v_queda := i.cantidad - public.devuelto_compra_item(i.id);
    if v_cant > v_queda + 0.0005 then
      if v_queda > 0 then raise exception 'De % se pueden devolver hasta %', i.nombre, trim_scale(v_queda) using errcode = '22023';
      else raise exception '% ya se devolvió completo', i.nombre using errcode = '22023'; end if;
    end if;
    insert into public.devolucion_compra_items (negocio_id, devolucion_id, compra_item_id, producto_id, nombre, cantidad, costo, importe)
      values (v_neg, v_dev, i.id, i.producto_id, i.nombre, v_cant, i.costo, round(i.costo * v_cant, 2));
    update public.productos set stock = stock - v_cant where id = i.producto_id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, i.producto_id, -v_cant, v_etq, v_u);
    v_suma := v_suma + round(i.costo * v_cant, 2); v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Elegí qué productos devolvés' using errcode = '22023'; end if;
  v_total := round(coalesce(public.num(p, 'total', 'Total'), v_suma), 2);
  if v_total < 0 then raise exception 'El total no puede ser negativo' using errcode = '22023'; end if;
  v_plata := v_forma not in ('Cuenta', 'Sin reintegro') and v_total > 0;
  if v_plata then t := public.requiere_turno(); else select * into t from public.turnos where negocio_id = v_neg and cierre is null; end if;
  update public.devoluciones_compra set total = v_total, turno_id = t.id where id = v_dev;
  -- en la cuenta: la devolución baja lo que se le debe; si devolvió la plata, el reintegro la compensa y la plata entra a la caja
  if r.id is not null and v_total > 0 then
    insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
      values (v_neg, r.id, 'devolucion', -v_total, v_etq, c.id, v_u) returning id into v_mov;
    if v_plata then
      insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, compra_id, turno_id, usuario_id, par_id)
        values (v_neg, r.id, 'reintegro', v_total, v_etq || ': devolvió la plata', v_forma, true, c.id, t.id, v_u, v_mov);
    else
      -- a cuenta: se aplica sola a esta factura; si ya estaba pagada, queda a cuenta, sin aplicar
      select d.pendiente into v_pend from public.deudas_proveedor(r.id) d where d.compra_id = c.id;
      if coalesce(v_pend, 0) > 0.004 then perform public.aplicar(v_neg, r.id, v_mov, c.id, null, least(v_total, v_pend), v_u); end if;
    end if;
  end if;
  if v_plata then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, compra_id)
      values (v_neg, t.id, v_u, 'ingreso', v_etq, v_total, v_forma, c.id);
  end if;
  return public.compra_json(c.id) || jsonb_build_object('devolucion', jsonb_build_object('etiqueta', 'DP-' || lpad(v_num::text, 4, '0'), 'total', v_total,
    'stock_negativo', (select coalesce(jsonb_agg(x.nombre), '[]'::jsonb) from public.productos x
                       where x.id in (select producto_id from public.devolucion_compra_items where devolucion_id = v_dev) and x.stock < 0)));
end;
$$;

-- Anular: solo lo que quedó después de las devoluciones (el stock no devuelto; de la caja vuelve lo pagado menos la plata
-- que el proveedor ya devolvió)
create or replace function public.anular_compra(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); c public.compras; t public.turnos; i record; v_neto numeric;
  v_plata_dev numeric; v_vuelve numeric := 0; v_queda numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into c from public.compras where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Compra no encontrada' using errcode = 'P0002'; end if;
  if c.anulada then raise exception 'La compra ya estaba anulada' using errcode = 'P0001'; end if;
  select coalesce(sum(total), 0) into v_plata_dev from public.devoluciones_compra where compra_id = c.id and forma not in ('Cuenta', 'Sin reintegro');
  if c.pagada_caja then v_vuelve := c.total - v_plata_dev; end if;
  if v_vuelve > 0.004 then t := public.requiere_turno(); end if;
  for i in select * from public.compra_items where compra_id = c.id loop
    v_queda := i.cantidad - public.devuelto_compra_item(i.id);
    if v_queda > 0 then
      update public.productos set stock = stock - v_queda where id = i.producto_id;
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, i.producto_id, -v_queda, 'Anulación de compra', v_u);
    end if;
  end loop;
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, compra_id)
      values (v_neg, t.id, v_u, 'ingreso', 'Anulación de compra', v_vuelve, coalesce(nullif(c.forma, ''), 'Efectivo'), c.id);
  end if;
  if c.proveedor_id is not null then
    select coalesce(sum(monto), 0) into v_neto from public.cc_prov where compra_id = c.id;
    if v_neto <> 0 then
      insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
        values (v_neg, c.proveedor_id, 'anulacion', -v_neto, 'Anulación de compra' || case when c.comprobante <> '' then ' ' || c.comprobante else '' end, c.id, v_u);
    end if;
  end if;
  delete from public.aplicaciones_prov where compra_id = c.id or credito_id in (select id from public.cc_prov where compra_id = c.id);
  update public.compras set anulada = true, anulada_fecha = now(), anulada_por = v_u where id = c.id;
  return public.compra_json(c.id);
end;
$$;

-- La lista muestra lo devuelto
create or replace function public.compras()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_tz text;
begin
  perform public.requiere_admin();
  v_tz := public.zona_horaria(v_neg);
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.fecha, 'proveedor_id', c.proveedor_id,
      'proveedor', (select p.nombre from public.proveedores p where p.id = c.proveedor_id),
      'comprobante', c.comprobante, 'remito', c.remito, 'factura_pendiente', c.factura_pendiente, 'fecha_factura', c.fecha_factura,
      'vencimiento', c.vencimiento, 'total', c.total, 'pagada_caja', c.pagada_caja, 'forma', c.forma, 'anulada', c.anulada,
      'devuelto', (select coalesce(sum(d.total), 0) from public.devoluciones_compra d where d.compra_id = c.id),
      'items', (select count(*) from public.compra_items i where i.compra_id = c.id))
      order by coalesce(c.fecha_factura, (c.fecha at time zone v_tz)::date) desc, c.id desc)
    from public.compras c where c.negocio_id = v_neg
      and (c.id >= coalesce((select id from public.compras where negocio_id = v_neg order by id desc offset 299 limit 1), 0)
           or (c.factura_pendiente and not c.anulada))), '[]'::jsonb);
end;
$$;

revoke all on function public.devuelto_compra_item(bigint), public.devolver_compra(jsonb) from public, anon, authenticated;
grant execute on function public.devolver_compra(jsonb) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 11, 'hora', now());
$$;
