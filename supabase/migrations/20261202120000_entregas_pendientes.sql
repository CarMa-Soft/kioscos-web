-- =====================================================================
-- Entregas pendientes: vender más de lo que hay en stock, cobrando todo y entregando lo que falta cuando llega
-- Al cobrar, si se vende más de lo que hay, Vender pregunta por cada producto: o se entrega todo ahora (el stock estaba
-- mal) o se entrega lo que hay y el resto queda pendiente, a nombre del cliente o de un nombre (y teléfono).
-- - De lo pendiente no se descuenta stock (no salió): queda en entregas_pendientes y cuenta como comprometido.
-- - Pedidos lo suma a lo que hay que pedir, con la nota de a quién se le debe.
-- - Cuando la mercadería llega (se carga la compra), Vender avisa y "Entregar" descuenta el stock (sin plata: ya se cobró).
-- - Una devolución descuenta primero de lo pendiente (eso no vuelve al stock); anular la venta cancela lo pendiente y
--   devuelve al stock solo lo entregado.
-- =====================================================================

create table public.entregas_pendientes (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  venta_id bigint not null,
  venta_item_id bigint not null,
  producto_id bigint not null,
  nombre text not null,                        -- el producto, como se vendió
  cantidad numeric(14, 3) not null check (cantidad >= 0),
  cliente_id bigint,
  a_nombre text not null,
  telefono text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'entregada', 'cancelada')),
  creado timestamptz not null default now(),
  usuario_id bigint not null,
  entregada timestamptz,
  entrego_id bigint,
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id),
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id),
  foreign key (cliente_id, negocio_id) references public.clientes (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (entrego_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index entregas_pendientes_negocio on public.entregas_pendientes (negocio_id, estado);
create index entregas_pendientes_producto on public.entregas_pendientes (producto_id) where estado = 'pendiente';
create index entregas_pendientes_item on public.entregas_pendientes (venta_item_id);
alter table public.entregas_pendientes enable row level security;
revoke all on public.entregas_pendientes from anon, authenticated;

-- Cuánto de un producto está comprometido en entregas pendientes
create or replace function public.comprometido(p_producto_id bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(cantidad), 0) from public.entregas_pendientes where producto_id = p_producto_id and estado = 'pendiente';
$$;

-- Descuenta hasta p_cant de lo pendiente de un renglón (devolución o anulación). Devuelve cuánto se descontó.
create or replace function public.descontar_pendiente(p_venta_item_id bigint, p_cant numeric)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare e record; v_resta numeric := greatest(coalesce(p_cant, 0), 0); v_saca numeric; v_total numeric := 0;
begin
  for e in select * from public.entregas_pendientes where venta_item_id = p_venta_item_id and estado = 'pendiente' order by id desc for update loop
    exit when v_resta <= 0;
    v_saca := least(e.cantidad, v_resta);
    if v_saca >= e.cantidad then update public.entregas_pendientes set estado = 'cancelada' where id = e.id;
    else update public.entregas_pendientes set cantidad = cantidad - v_saca where id = e.id; end if;
    v_resta := v_resta - v_saca; v_total := v_total + v_saca;
  end loop;
  return v_total;
end;
$$;

-- Venta: p_entrega { nombre, telefono } y, por renglón, 'pendiente' (lo que se entrega después)
drop function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid);
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false, p_descuento numeric default 0, p_autorizacion uuid default null,
  p_entrega jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas; c public.clientes;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_precio numeric; v_importe numeric; v_etiqueta numeric;
  v_sub numeric := 0; v_desc_ren numeric := 0; v_desc numeric; v_base numeric; v_bases numeric := 0; v_b numeric; v_pct numeric;
  v_rec numeric; v_recargo numeric := 0; v_fiado numeric := 0; v_pid bigint; v_saldo numeric; v_forma text;
  v_manual numeric; v_alista numeric; v_pct_desc numeric; v_tope numeric; v_aut bigint;
  v_item bigint; v_pend numeric; v_ent_nombre text; v_ent_tel text;
begin
  if p_clave is null then raise exception 'Falta la clave de la venta' using errcode = '22023'; end if;
  perform 1 from public.negocios where id = v_neg for update;     -- una venta a la vez por negocio
  select * into v from public.ventas where negocio_id = v_neg and clave = p_clave;
  if found then return public.venta_json(v.id) || jsonb_build_object('repetida', true); end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene productos' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 300 then raise exception 'La venta tiene demasiados renglones' using errcode = '22023'; end if;
  if jsonb_typeof(p_pagos) is distinct from 'array' or jsonb_array_length(p_pagos) = 0 then
    raise exception 'Falta la forma de pago' using errcode = '22023';
  end if;
  if p_cliente_id is not null then
    c := public.requiere_cliente(p_cliente_id);
    if not c.activo then raise exception '"%" está dado de baja', c.nombre using errcode = 'P0001'; end if;
  end if;
  t := public.requiere_turno();
  -- a nombre de quién queda lo que se entrega después: el cliente o el nombre que se escribió al cobrar
  v_ent_nombre := coalesce(nullif(left(btrim(coalesce(p_entrega ->> 'nombre', '')), 80), ''), c.nombre);
  v_ent_tel := nullif(left(btrim(coalesce(p_entrega ->> 'telefono', '')), 40), '');

  insert into public.ventas (negocio_id, numero, clave, usuario_id, turno_id, subtotal, total, cliente_id)
    values (v_neg, coalesce((select max(numero) from public.ventas where negocio_id = v_neg), 0) + 1, p_clave, v_u, t.id, 0, 0, c.id)
    returning * into v;

  for it in select value from jsonb_array_elements(p_items) loop
    v_pid := nullif(it ->> 'producto_id', '')::bigint;
    if v_pid is not null then
      select * into p from public.productos where id = v_pid and negocio_id = v_neg for update;
      if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
      if not p.activo then raise exception '"%" está dado de baja', p.nombre using errcode = 'P0001'; end if;
      v_cant := round(public.num(it, 'cantidad', 'Cantidad'), 3);
      if v_cant is null or v_cant <= 0 then raise exception 'Hay una cantidad en 0' using errcode = '22023'; end if;
      if not p.por_peso and v_cant <> trunc(v_cant) then
        raise exception 'La cantidad de "%" tiene que ser entera', p.nombre using errcode = '22023';
      end if;
      v_precio := coalesce(round(public.num(it, 'precio', 'Precio'), 2), p.precio);
      if v_precio < 0 then raise exception 'El precio de "%" no puede ser negativo', p.nombre using errcode = '22023'; end if;
      v_importe := round(v_cant * v_precio, 2);
      -- etiqueta de balanza con importe: vale ese importe si coincide con kilos × precio (redondeo de medio gramo)
      v_etiqueta := round(public.num(it, 'importe', 'Importe'), 2);
      if v_etiqueta is not null then
        if not p.por_peso then raise exception 'Solo un producto por peso puede llevar el importe de la etiqueta' using errcode = '22023'; end if;
        if abs(v_etiqueta - v_cant * v_precio) > v_precio * 0.0005 + 0.01 then
          raise exception 'El importe de la etiqueta de "%" no coincide con el peso y el precio', p.nombre using errcode = '22023';
        end if;
        v_importe := v_etiqueta;
      end if;
      if p.precio > v_precio then v_desc_ren := v_desc_ren + round((p.precio - v_precio) * v_cant, 2); end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe, costo, por_peso, categoria_id, precio_lista)
        values (v_neg, v.id, p.id, p.nombre, v_cant, v_precio, v_importe, p.costo, p.por_peso, p.categoria_id, p.precio)
        returning id into v_item;
      -- lo que no hay en stock y se entrega después: se cobra igual, pero del stock sale solo lo que se lleva ahora
      v_pend := round(coalesce(public.num(it, 'pendiente', 'Pendiente de entrega'), 0), 3);
      if v_pend < 0 or v_pend > v_cant then raise exception 'Lo pendiente de entrega de "%" no puede pasar lo vendido', p.nombre using errcode = '22023'; end if;
      if v_pend > 0 then
        if v_ent_nombre is null then raise exception 'Falta a nombre de quién queda lo que se entrega después' using errcode = '22023'; end if;
        insert into public.entregas_pendientes (negocio_id, venta_id, venta_item_id, producto_id, nombre, cantidad, cliente_id, a_nombre, telefono, usuario_id)
          values (v_neg, v.id, v_item, p.id, p.nombre, v_pend, c.id, v_ent_nombre, v_ent_tel, v_u);
      end if;
      update public.productos set stock = stock - (v_cant - v_pend) where id = p.id;
    else
      v_importe := round(public.num(it, 'importe', 'Importe'), 2);
      if v_importe is null or v_importe <= 0 then raise exception 'El importe de "Varios" tiene que ser mayor a 0' using errcode = '22023'; end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe)
        values (v_neg, v.id, null, coalesce(nullif(left(btrim(it ->> 'nombre'), 120), ''), 'Varios'), 1, v_importe, v_importe);
    end if;
    v_sub := v_sub + v_importe;
  end loop;

  v_desc := least(round(coalesce(p_descuento, 0), 2), v_sub);
  if v_desc < 0 then raise exception 'El descuento no puede ser negativo' using errcode = '22023'; end if;
  v_base := v_sub - v_desc;
  v_manual := v_desc + v_desc_ren; v_alista := v_sub + v_desc_ren;
  if v_manual > 0.004 and v_alista > 0 and not public.es_admin() then
    v_pct_desc := round(v_manual / v_alista * 100, 1);
    v_tope := public.tope_descuento(v_neg);
    if v_pct_desc > v_tope then
      if p_autorizacion is not null then v_aut := public.usar_autorizacion(p_autorizacion); end if;
      if v_aut is null then
        raise exception '%', format('El descuento es del %s%% y tu tope es %s%%: necesita la autorización del dueño', trim_scale(v_pct_desc), trim_scale(v_tope))
          using errcode = 'P0001', hint = 'autorizacion';
      end if;
    end if;
  end if;

  v_formas := public.formas_pago(v_neg);
  for pg in select value from jsonb_array_elements(p_pagos) loop
    v_b := round(coalesce(public.num(pg, 'base', 'Monto del pago'), public.num(pg, 'monto', 'Monto del pago')), 2);
    if v_b is null or v_b <= 0 then continue; end if;
    v_forma := coalesce(pg ->> 'forma', '');
    if v_forma <> 'Fiado' and not (v_forma = any (v_formas)) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    if v_forma = 'Fiado' and c.id is null then raise exception 'Para fiar hay que elegir el cliente' using errcode = '22023'; end if;
    v_pct := public.pct_recargo(v_neg, v_forma);
    v_rec := case when v_pct > 0 then round(v_b * v_pct / 100, 0) else 0 end;
    insert into public.venta_pagos (negocio_id, venta_id, forma, monto, recargo, pct_recargo) values (v_neg, v.id, v_forma, v_b + v_rec, v_rec, v_pct);
    if v_forma = 'Fiado' then
      v_fiado := v_fiado + v_b + v_rec;
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id, turno_id)
        values (v_neg, c.id, 'cargo', v_b + v_rec, 'Compra #' || v.numero, v.id, v_u, t.id);
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_b + v_rec, v_forma, v.id);
    end if;
    v_bases := v_bases + v_b; v_recargo := v_recargo + v_rec;
  end loop;
  if abs(v_bases - v_base) > 0.005 then
    raise exception 'Los pagos (%) no suman el total (%)', v_bases, v_base using errcode = '22023';
  end if;
  if v_fiado > 0 and c.limite > 0 and not coalesce(p_forzar_limite, false) then
    v_saldo := public.saldo_cliente(c.id);
    if v_saldo > c.limite then
      raise exception '% pasaría su límite de fiado (%): quedaría debiendo %', c.nombre, c.limite, v_saldo using errcode = 'P0001', hint = 'limite';
    end if;
  end if;

  update public.ventas set subtotal = v_sub, descuento = v_desc, descuento_renglones = v_desc_ren, recargo = v_recargo,
      total = v_base + v_recargo, autorizo_id = v_aut, paga_con = case when p_paga_con > 0 then round(p_paga_con, 2) end
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;


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
    'pendientes', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'cantidad', e.cantidad, 'a_nombre', e.a_nombre) order by e.id)
      from public.entregas_pendientes e where e.venta_id = v.id and e.estado = 'pendiente'), '[]'::jsonb),
    'devoluciones', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero, 'etiqueta', public.etiqueta_devolucion(d.numero),
        'fecha', d.fecha, 'usuario', public.nombre_usuario(d.usuario_id),
        'autorizo', case when d.autorizo_id is not null then public.nombre_usuario(d.autorizo_id) end,
        'forma', d.forma, 'total', d.total, 'motivo', d.motivo,
        'items', (select jsonb_agg(jsonb_build_object('nombre', x.nombre, 'cantidad', x.cantidad, 'importe', x.importe, 'vuelve_stock', x.vuelve_stock,
                    'por_peso', x.por_peso) order by x.id) from public.devolucion_items x where x.devolucion_id = d.id)) order by d.id)
      from public.devoluciones d where d.venta_id = v.id), '[]'::jsonb))
  from public.ventas v where v.id = p_id;
$$;


create or replace function public.devolver_venta(p_venta_id bigint, p_items jsonb, p_forma text, p_motivo text default null, p_autorizacion uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); v public.ventas; t public.turnos;
  v_aut bigint; v_factor numeric; v_dev bigint; v_num integer; x jsonb; vi public.venta_items; v_cant numeric; v_queda numeric;
  v_imp numeric; v_total numeric := 0; v_n integer := 0; v_vuelve boolean; v_etq text; v_previo numeric; v_stock numeric;
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
    -- primero se descuenta de lo que todavía no se le entregó (eso nunca salió del stock)
    v_stock := v_cant - public.descontar_pendiente(vi.id, v_cant);
    if v_vuelve and vi.producto_id is not null and v_stock > 0 then
      update public.productos set stock = stock + v_stock where id = vi.producto_id;
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, vi.producto_id, v_stock, v_etq, v_u);
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
    v_queda := i.cantidad - public.devuelto_item(i.id) - public.descontar_pendiente(i.id, i.cantidad);   -- lo no entregado no vuelve
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


create or replace function public.pedidos()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_items jsonb;
begin
  perform public.requiere_admin();
  -- lo guardado de productos que ya no hace falta pedir (o dados de baja) se limpia
  delete from public.pedido_items pi using public.productos pr
    where pi.negocio_id = v_neg and pr.id = pi.producto_id and (not pr.activo or pr.stock - public.comprometido(pr.id) > greatest(pr.stock_min, 0));
  with faltan as (
    select pr.*, public.comprometido(pr.id) as comprometido, coalesce(pr.proveedor_id, (select pp.proveedor_id from public.producto_proveedores pp
                    where pp.producto_id = pr.id order by pp.ultima_compra desc nulls last limit 1)) as prov
    from public.productos pr
    where pr.negocio_id = v_neg and pr.activo and pr.stock - public.comprometido(pr.id) <= greatest(pr.stock_min, 0)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'producto_id', f.id, 'nombre', f.nombre, 'codigo', f.codigo, 'codigo_proveedor', pp.codigo_proveedor, 'por_peso', f.por_peso,
      'stock', f.stock, 'stock_min', f.stock_min, 'sin_stock', f.stock <= 0,
      'propuesta', public.cantidad_propuesta(f.stock - f.comprometido, f.stock_min, f.por_peso),
      'cantidad', coalesce(pi.cantidad, public.cantidad_propuesta(f.stock - f.comprometido, f.stock_min, f.por_peso)),
      'pendiente', coalesce(pi.pendiente, false),
      'para_entregar', f.comprometido,
      'entregas', (select string_agg(trim_scale(e.cantidad)::text || ' a ' || e.a_nombre || ' (venta #' || vv.numero || ')', ', ' order by e.id)
                   from public.entregas_pendientes e join public.ventas vv on vv.id = e.venta_id where e.producto_id = f.id and e.estado = 'pendiente'),
      'ultimo_costo', pp.ultimo_costo, 'ultima_compra', pp.ultima_compra, 'costo', f.costo, 'proveedor_id', f.prov,
      'proveedor', (select nombre from public.proveedores where id = f.prov))
    order by lower(f.nombre)), '[]'::jsonb) into v_items
  from faltan f
    left join public.producto_proveedores pp on pp.producto_id = f.id and pp.proveedor_id = f.prov
    left join public.pedido_items pi on pi.producto_id = f.id;
  return jsonb_build_object(
    'proveedores', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'telefono', p.telefono,
        'items', (select jsonb_agg(i) from jsonb_array_elements(v_items) i where (i ->> 'proveedor_id')::bigint = p.id and not (i ->> 'pendiente')::boolean))
      order by lower(p.nombre))
      from public.proveedores p where p.negocio_id = v_neg and exists (select 1 from jsonb_array_elements(v_items) i
        where (i ->> 'proveedor_id')::bigint = p.id and not (i ->> 'pendiente')::boolean)), '[]'::jsonb),
    'sin_proveedor', coalesce((select jsonb_agg(i) from jsonb_array_elements(v_items) i where i -> 'proveedor_id' = 'null'::jsonb and not (i ->> 'pendiente')::boolean), '[]'::jsonb),
    'pendientes', coalesce((select jsonb_agg(i) from jsonb_array_elements(v_items) i where (i ->> 'pendiente')::boolean), '[]'::jsonb),
    'negocio', (select nombre from public.negocios where id = v_neg));
end;
$$;


-- Las entregas pendientes del negocio (cualquier usuario: se entrega en el mostrador). 'lista': ya hay stock para entregarla.
create or replace function public.entregas_pendientes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_usuario();
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'venta_id', e.venta_id, 'venta', v.numero, 'fecha', e.creado,
      'producto_id', e.producto_id, 'nombre', e.nombre, 'cantidad', e.cantidad, 'por_peso', pr.por_peso, 'stock', pr.stock,
      'lista', pr.stock >= e.cantidad, 'a_nombre', e.a_nombre, 'telefono', e.telefono, 'usuario', public.nombre_usuario(e.usuario_id))
      order by (pr.stock >= e.cantidad) desc, e.id)
    from public.entregas_pendientes e join public.ventas v on v.id = e.venta_id join public.productos pr on pr.id = e.producto_id
    where e.negocio_id = v_neg and e.estado = 'pendiente'), '[]'::jsonb);
end;
$$;

-- Entregar lo pendiente: sale del stock (sin plata: ya se cobró). Tiene que haber stock.
create or replace function public.entregar_pendiente(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); e public.entregas_pendientes; pr public.productos; v_num integer;
begin
  select * into e from public.entregas_pendientes where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró la entrega' using errcode = 'P0002'; end if;
  if e.estado <> 'pendiente' then raise exception 'Esa entrega ya no está pendiente' using errcode = 'P0001'; end if;
  select * into pr from public.productos where id = e.producto_id for update;
  if pr.stock < e.cantidad then
    raise exception 'Hay % de "%" en stock y hay que entregar %: cargá primero la compra', trim_scale(pr.stock), e.nombre, trim_scale(e.cantidad) using errcode = 'P0001';
  end if;
  select numero into v_num from public.ventas where id = e.venta_id;
  update public.productos set stock = stock - e.cantidad where id = pr.id;
  insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
    values (v_neg, pr.id, -e.cantidad, left('Entrega pendiente de la venta #' || v_num || ' a ' || e.a_nombre, 160), v_u);
  update public.entregas_pendientes set estado = 'entregada', entregada = now(), entrego_id = v_u where id = e.id;
  return jsonb_build_object('id', e.id, 'nombre', e.nombre, 'cantidad', e.cantidad, 'a_nombre', e.a_nombre, 'venta', v_num);
end;
$$;

revoke all on function public.comprometido(bigint), public.descontar_pendiente(bigint, numeric),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb),
  public.entregas_pendientes(), public.entregar_pendiente(bigint) from public, anon, authenticated;
grant execute on function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb),
  public.entregas_pendientes(), public.entregar_pendiente(bigint) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 19, 'hora', now());
$$;
