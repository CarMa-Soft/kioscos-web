-- =====================================================================
-- Etapa 4d: devoluciones de venta (como en la app local, #7)
--
-- El cliente devuelve parte o toda una venta: DV-0001, con numeración propia por negocio.
-- Se le reintegra lo que pagó por eso: importe del renglón × total / subtotal de la venta (incluye el descuento general
-- y los recargos); si con esta devolución vuelve todo lo que quedaba, justo lo que falta (sin diferencias de redondeo).
-- Cómo: una forma de pago (sale de la caja del turno) o 'Fiado' (se descuenta de su cuenta o queda a favor).
-- Cada renglón: si vuelve al stock (si no, roto o vencido: pérdida). El empleado necesita la autorización del dueño.
-- Anular una venta con devoluciones anula solo lo que quedó.
-- =====================================================================

alter table public.venta_items add constraint venta_items_id_negocio unique (id, negocio_id);

create table public.devoluciones (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  numero integer not null,
  venta_id bigint not null,
  fecha timestamptz not null default now(),
  usuario_id bigint not null,
  autorizo_id bigint,
  turno_id bigint,
  forma text not null,
  total numeric(14, 2) not null default 0 check (total >= 0),
  motivo text,
  unique (id, negocio_id),
  unique (negocio_id, numero),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (autorizo_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id)
);
create index devoluciones_venta on public.devoluciones (venta_id);
create index devoluciones_fecha on public.devoluciones (negocio_id, fecha);

create table public.devolucion_items (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  devolucion_id bigint not null,
  venta_item_id bigint not null,
  producto_id bigint,
  nombre text not null,
  cantidad numeric(14, 3) not null check (cantidad > 0),
  importe numeric(14, 2) not null,
  costo numeric(14, 2) not null default 0,
  vuelve_stock boolean not null default true,
  por_peso boolean not null default false,
  categoria_id bigint,
  foreign key (devolucion_id, negocio_id) references public.devoluciones (id, negocio_id) on delete cascade,
  foreign key (venta_item_id, negocio_id) references public.venta_items (id, negocio_id)
);
create index devolucion_items_devolucion on public.devolucion_items (devolucion_id);
create index devolucion_items_venta_item on public.devolucion_items (venta_item_id);

alter table public.devoluciones enable row level security;
alter table public.devolucion_items enable row level security;
revoke all on public.devoluciones, public.devolucion_items from anon, authenticated;

-- ---------------------------------------------------------------------
-- Ayudas
-- ---------------------------------------------------------------------
create or replace function public.devuelto_item(p_venta_item bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(cantidad), 0) from public.devolucion_items where venta_item_id = p_venta_item;
$$;

create or replace function public.devuelto_venta(p_venta bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(total), 0) from public.devoluciones where venta_id = p_venta;
$$;

create or replace function public.etiqueta_devolucion(p_numero integer)
returns text language sql immutable set search_path = '' as $$
  select 'DV-' || lpad(p_numero::text, 4, '0');
$$;

-- Venta completa: ahora con el id de cada renglón, cuánto se devolvió de cada uno y las devoluciones
create or replace function public.venta_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'usuario', public.nombre_usuario(v.usuario_id),
    'turno_id', v.turno_id, 'subtotal', v.subtotal, 'descuento', v.descuento, 'descuento_renglones', v.descuento_renglones,
    'recargo', v.recargo, 'total', v.total, 'paga_con', v.paga_con,
    'autorizo', case when v.autorizo_id is not null then public.nombre_usuario(v.autorizo_id) end,
    'cliente', (select jsonb_build_object('id', c.id, 'nombre', c.nombre) from public.clientes c where c.id = v.cliente_id),
    'anulada', v.anulada, 'anulada_fecha', v.anulada_fecha, 'anulada_por', case when v.anulada then public.nombre_usuario(v.anulada_por) end,
    'motivo_anulacion', v.motivo_anulacion,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'precio', i.precio, 'precio_lista', i.precio_lista, 'importe', i.importe, 'por_peso', i.por_peso,
                         'devuelto', public.devuelto_item(i.id)) order by i.id)
                       from public.venta_items i where i.venta_id = v.id), '[]'::jsonb),
    'pagos', coalesce((select jsonb_agg(jsonb_build_object('forma', p.forma, 'monto', p.monto, 'recargo', p.recargo, 'pct_recargo', p.pct_recargo) order by p.id)
                       from public.venta_pagos p where p.venta_id = v.id), '[]'::jsonb),
    'devuelto', public.devuelto_venta(v.id),
    'devoluciones', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero, 'etiqueta', public.etiqueta_devolucion(d.numero),
        'fecha', d.fecha, 'usuario', public.nombre_usuario(d.usuario_id),
        'autorizo', case when d.autorizo_id is not null then public.nombre_usuario(d.autorizo_id) end,
        'forma', d.forma, 'total', d.total, 'motivo', d.motivo,
        'items', (select jsonb_agg(jsonb_build_object('nombre', x.nombre, 'cantidad', x.cantidad, 'importe', x.importe, 'vuelve_stock', x.vuelve_stock,
                    'por_peso', x.por_peso) order by x.id) from public.devolucion_items x where x.devolucion_id = d.id)) order by d.id)
      from public.devoluciones d where d.venta_id = v.id), '[]'::jsonb))
  from public.ventas v where v.id = p_id;
$$;

-- ---------------------------------------------------------------------
-- Devolver
-- ---------------------------------------------------------------------
-- p_items: [{ id (renglón de la venta), cantidad, vuelve_stock }]. p_forma: forma de pago del reintegro o 'Fiado'.
create or replace function public.devolver_venta(p_venta_id bigint, p_items jsonb, p_forma text, p_motivo text default null, p_autorizacion uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); v public.ventas; t public.turnos;
  v_aut bigint; v_factor numeric; v_dev bigint; v_num integer; x jsonb; vi public.venta_items; v_cant numeric; v_queda numeric;
  v_imp numeric; v_total numeric := 0; v_n integer := 0; v_vuelve boolean; v_etq text; v_previo numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into v from public.ventas where id = p_venta_id and negocio_id = v_neg for update;
  if not found then raise exception 'Venta no encontrada' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'La venta está anulada' using errcode = 'P0001'; end if;
  if not public.es_admin() then
    if p_autorizacion is not null then v_aut := public.usar_autorizacion(p_autorizacion); end if;
    if v_aut is null then
      raise exception 'Devolver productos necesita la autorización del dueño' using errcode = 'P0001', hint = 'autorizacion';
    end if;
  end if;
  if coalesce(p_forma, '') = 'Fiado' then
    if v.cliente_id is null then raise exception 'La venta no tiene cliente: no se puede dejar en su cuenta' using errcode = '22023'; end if;
    select * into t from public.turnos where negocio_id = v_neg and cierre is null;   -- no hace falta, pero si hay queda anotado
  else
    if not (coalesce(p_forma, '') = any (public.formas_pago(v_neg))) then raise exception 'Elegí cómo se le devuelve la plata' using errcode = '22023'; end if;
    t := public.requiere_turno();
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Elegí qué productos devuelve' using errcode = '22023'; end if;

  v_factor := case when v.subtotal > 0 then v.total / v.subtotal else 1 end;
  v_previo := public.devuelto_venta(v.id);
  v_num := coalesce((select max(numero) from public.devoluciones where negocio_id = v_neg), 0) + 1;
  v_etq := 'Devolución ' || public.etiqueta_devolucion(v_num) || ' (venta #' || v.numero || ')';
  insert into public.devoluciones (negocio_id, numero, venta_id, usuario_id, autorizo_id, turno_id, forma, motivo)
    values (v_neg, v_num, v.id, v_u, v_aut, t.id, p_forma, nullif(left(btrim(coalesce(p_motivo, '')), 200), ''))
    returning id into v_dev;

  for x in select value from jsonb_array_elements(p_items) loop
    select * into vi from public.venta_items where id = nullif(x ->> 'id', '')::bigint and venta_id = v.id;
    if not found then raise exception 'Hay un producto que no es de esta venta' using errcode = 'P0002'; end if;
    v_cant := round(public.num(x, 'cantidad', 'Cantidad de ' || vi.nombre), 3);
    if v_cant is null or v_cant <= 0 then continue; end if;
    if not vi.por_peso and v_cant <> trunc(v_cant) then raise exception 'La cantidad de "%" tiene que ser entera', vi.nombre using errcode = '22023'; end if;
    v_queda := vi.cantidad - public.devuelto_item(vi.id);
    if v_cant > v_queda + 0.0005 then
      if v_queda > 0 then raise exception 'De % se pueden devolver hasta %', vi.nombre, trim_scale(v_queda) using errcode = '22023';
      else raise exception '% ya se devolvió completo', vi.nombre using errcode = '22023'; end if;
    end if;
    v_imp := round(vi.importe / vi.cantidad * v_cant * v_factor, 2);
    v_vuelve := coalesce((x ->> 'vuelve_stock')::boolean, true);
    insert into public.devolucion_items (negocio_id, devolucion_id, venta_item_id, producto_id, nombre, cantidad, importe, costo, vuelve_stock, por_peso, categoria_id)
      values (v_neg, v_dev, vi.id, vi.producto_id, vi.nombre, v_cant, v_imp, vi.costo, v_vuelve, vi.por_peso, vi.categoria_id);
    if v_vuelve and vi.producto_id is not null then
      update public.productos set stock = stock + v_cant where id = vi.producto_id;
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, vi.producto_id, v_cant, v_etq, v_u);
    end if;
    v_total := v_total + v_imp; v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Elegí qué productos devuelve' using errcode = '22023'; end if;
  -- si vuelve todo lo que quedaba, se reintegra justo lo que falta
  if not exists (select 1 from public.venta_items i where i.venta_id = v.id and i.cantidad - public.devuelto_item(i.id) > 0.0005) then
    v_total := v.total - v_previo;
  end if;
  update public.devoluciones set total = v_total where id = v_dev;
  if v_total > 0 then
    if p_forma = 'Fiado' then
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id, turno_id)
        values (v_neg, v.cliente_id, 'ajuste', -v_total, v_etq, v.id, v_u, t.id);
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'egreso', v_etq, v_total, p_forma, v.id);
    end if;
  end if;
  return public.venta_json(v.id) || jsonb_build_object('devolucion', jsonb_build_object('numero', v_num, 'etiqueta', public.etiqueta_devolucion(v_num), 'total', v_total));
end;
$$;

-- ---------------------------------------------------------------------
-- Anular: solo lo que quedó después de las devoluciones
-- ---------------------------------------------------------------------
create or replace function public.anular_venta(p_id bigint, p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v public.ventas; t public.turnos; i record; pg record;
  v_devuelto numeric; v_resto numeric; v_factor numeric; v_monto numeric; v_acum numeric := 0; v_n integer; v_k integer := 0; v_queda numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into v from public.ventas where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Venta no encontrada' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'La venta ya estaba anulada' using errcode = 'P0001'; end if;
  v_devuelto := public.devuelto_venta(v.id);
  v_resto := v.total - v_devuelto;
  v_factor := case when v.total > 0 then v_resto / v.total else 0 end;
  if v_resto > 0 and exists (select 1 from public.venta_pagos where venta_id = v.id and forma <> 'Fiado') then t := public.requiere_turno(); end if;
  for i in select * from public.venta_items where venta_id = v.id and producto_id is not null loop
    v_queda := i.cantidad - public.devuelto_item(i.id);
    if v_queda > 0 then
      update public.productos set stock = stock + v_queda where id = i.producto_id;
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
        values (v_neg, i.producto_id, v_queda, 'Anulación venta #' || v.numero, v_u);
    end if;
  end loop;
  -- la plata que quedaba, repartida entre los pagos en proporción a cada uno (el último, justo lo que falta)
  select count(*) into v_n from public.venta_pagos where venta_id = v.id;
  for pg in select * from public.venta_pagos where venta_id = v.id order by id loop
    v_k := v_k + 1;
    v_monto := case when v_k = v_n then v_resto - v_acum else round(pg.monto * v_factor, 2) end;
    v_acum := v_acum + v_monto;
    if v_monto <= 0 then continue; end if;
    if pg.forma = 'Fiado' then
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id)
        values (v_neg, v.cliente_id, 'ajuste', -v_monto, 'Anulación compra #' || v.numero, v.id, v_u);
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'egreso', 'Anulación venta #' || v.numero, v_monto, pg.forma, v.id);
    end if;
  end loop;
  update public.ventas set anulada = true, anulada_fecha = now(), anulada_por = v_u,
      motivo_anulacion = nullif(left(btrim(coalesce(p_motivo, '')), 200), '')
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

-- Las ventas del turno muestran lo devuelto
create or replace function public.estado_caja()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); t public.turnos;
begin
  perform public.requiere_usuario();
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then
    return public.config_cobro(v_neg) || jsonb_build_object('turno', null);
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

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.devuelto_item(bigint), public.devuelto_venta(bigint), public.etiqueta_devolucion(integer),
  public.devolver_venta(bigint, jsonb, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.devolver_venta(bigint, jsonb, text, text, uuid) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 7, 'hora', now());
$$;
