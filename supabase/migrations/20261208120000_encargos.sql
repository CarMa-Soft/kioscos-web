-- =====================================================================
-- Encargos: un cliente encarga un producto sin pagarlo (o dejando una seña). No es una venta: no toca el stock.
-- - La seña entra a la caja del turno ese día (ingreso "Seña encargo #N").
-- - Lo encargado cuenta como comprometido: Pedidos lo propone pedir, con la nota de a quién.
-- - Al venir a buscarlo, Vender lo pasa a la venta (p_encargos) y la seña se descuenta como forma de pago "Seña"
--   (no vuelve a entrar a la caja). Si se anula esa venta, el encargo vuelve a quedar pendiente.
-- - Si se cancela, la seña se devuelve (egreso de la caja) o queda para el negocio.
-- =====================================================================
create table public.encargos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  numero integer not null,
  producto_id bigint not null,
  nombre text not null,                        -- el producto, al encargarlo
  cantidad numeric(14, 3) not null check (cantidad > 0),
  cliente_id bigint,
  a_nombre text not null check (length(btrim(a_nombre)) between 1 and 80),
  telefono text check (length(telefono) <= 40),
  notas text check (length(notas) <= 200),
  sena numeric(14, 2) not null default 0 check (sena >= 0),
  sena_forma text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'entregado', 'cancelado')),
  venta_id bigint,
  sena_devuelta boolean not null default false,
  motivo text,
  usuario_id bigint not null,
  creado timestamptz not null default now(),
  cerrado timestamptz,
  cerrado_por bigint,
  unique (id, negocio_id),
  unique (negocio_id, numero),
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id),
  foreign key (cliente_id, negocio_id) references public.clientes (id, negocio_id),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (cerrado_por, negocio_id) references public.usuarios (id, negocio_id)
);
create index encargos_negocio on public.encargos (negocio_id, estado);
create index encargos_producto on public.encargos (producto_id) where estado = 'pendiente';
create index encargos_venta on public.encargos (venta_id) where venta_id is not null;
alter table public.encargos enable row level security;
revoke all on public.encargos from anon, authenticated;

-- Comprometido = entregas pendientes (ya vendidas) + encargos pendientes
create or replace function public.comprometido(p_producto_id bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select sum(cantidad) from public.entregas_pendientes where producto_id = p_producto_id and estado = 'pendiente'), 0)
       + coalesce((select sum(cantidad) from public.encargos where producto_id = p_producto_id and estado = 'pendiente'), 0);
$$;

create or replace function public.encargo_json(e public.encargos)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', e.id, 'numero', e.numero, 'producto_id', e.producto_id, 'nombre', e.nombre, 'cantidad', e.cantidad,
    'por_peso', pr.por_peso, 'stock', pr.stock, 'precio', pr.precio, 'lista', pr.stock >= e.cantidad,
    'cliente', (select jsonb_build_object('id', c.id, 'nombre', c.nombre) from public.clientes c where c.id = e.cliente_id),
    'a_nombre', e.a_nombre, 'telefono', e.telefono, 'notas', e.notas, 'sena', e.sena, 'sena_forma', e.sena_forma,
    'estado', e.estado, 'fecha', e.creado, 'usuario', public.nombre_usuario(e.usuario_id))
  from public.productos pr where pr.id = e.producto_id;
$$;

-- p: { producto_id, cantidad, cliente_id | (nombre, telefono), notas, sena, sena_forma }. Cualquier usuario.
create or replace function public.registrar_encargo(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); pr public.productos; c public.clientes;
  v_cant numeric := round(public.num(p, 'cantidad', 'Cantidad'), 3); v_sena numeric := coalesce(round(public.num(p, 'sena', 'Seña'), 2), 0);
  v_forma text := coalesce(nullif(p ->> 'sena_forma', ''), 'Efectivo'); v_nombre text; t public.turnos; e public.encargos;
begin
  select * into pr from public.productos where id = nullif(p ->> 'producto_id', '')::bigint and negocio_id = v_neg;
  if not found then raise exception 'Elegí el producto' using errcode = '22023'; end if;
  if not pr.activo then raise exception '"%" está dado de baja', pr.nombre using errcode = 'P0001'; end if;
  if v_cant is null or v_cant <= 0 then raise exception 'Poné la cantidad' using errcode = '22023'; end if;
  if not pr.por_peso and v_cant <> trunc(v_cant) then raise exception 'La cantidad de "%" tiene que ser entera', pr.nombre using errcode = '22023'; end if;
  if nullif(p ->> 'cliente_id', '') is not null then c := public.requiere_cliente((p ->> 'cliente_id')::bigint); end if;
  v_nombre := coalesce(c.nombre, nullif(left(btrim(coalesce(p ->> 'nombre', '')), 80), ''));
  if v_nombre is null then raise exception 'Poné a nombre de quién es el encargo' using errcode = '22023'; end if;
  if v_sena < 0 then raise exception 'La seña no puede ser negativa' using errcode = '22023'; end if;
  if v_sena > 0 then
    if v_forma = 'Fiado' or not (v_forma = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago de la seña inválida' using errcode = '22023'; end if;
    t := public.requiere_turno();
  end if;
  perform 1 from public.negocios where id = v_neg for update;   -- numeración sin repetir
  insert into public.encargos (negocio_id, numero, producto_id, nombre, cantidad, cliente_id, a_nombre, telefono, notas, sena, sena_forma, usuario_id)
    values (v_neg, coalesce((select max(numero) from public.encargos where negocio_id = v_neg), 0) + 1, pr.id, pr.nombre, v_cant, c.id, v_nombre,
      coalesce(nullif(left(btrim(coalesce(p ->> 'telefono', '')), 40), ''), c.telefono), nullif(left(btrim(coalesce(p ->> 'notas', '')), 200), ''),
      v_sena, case when v_sena > 0 then v_forma end, v_u)
    returning * into e;
  if v_sena > 0 then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma)
      values (v_neg, t.id, v_u, 'ingreso', 'Seña encargo #' || e.numero || ' (' || v_nombre || ')', v_sena, v_forma);
  end if;
  return public.encargo_json(e);
end;
$$;

-- Los pendientes: primero los que ya se pueden entregar
create or replace function public.encargos()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_usuario();
  return coalesce((select jsonb_agg(public.encargo_json(e) order by (pr.stock >= e.cantidad) desc, e.id)
    from public.encargos e join public.productos pr on pr.id = e.producto_id
    where e.negocio_id = v_neg and e.estado = 'pendiente'), '[]'::jsonb);
end;
$$;

-- Cancelar: la seña se devuelve (sale de la caja del turno, con la forma en que se dejó) o queda para el negocio
create or replace function public.cancelar_encargo(p_id bigint, p_devolver boolean, p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); e public.encargos; t public.turnos;
begin
  select * into e from public.encargos where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró el encargo' using errcode = 'P0002'; end if;
  if e.estado <> 'pendiente' then raise exception 'El encargo #% ya no está pendiente', e.numero using errcode = 'P0001'; end if;
  if e.sena > 0 and p_devolver is null then raise exception 'Elegí si la seña se devuelve' using errcode = '22023'; end if;
  if e.sena > 0 and p_devolver then
    t := public.requiere_turno();
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma)
      values (v_neg, t.id, v_u, 'egreso', 'Devolución seña encargo #' || e.numero || ' (' || e.a_nombre || ')', e.sena, coalesce(e.sena_forma, 'Efectivo'));
  end if;
  update public.encargos set estado = 'cancelado', sena_devuelta = coalesce(p_devolver, false) and sena > 0, cerrado = now(), cerrado_por = v_u,
      motivo = nullif(left(btrim(coalesce(p_motivo, '')), 200), '')
    where id = e.id returning * into e;
  return public.encargo_json(e);
end;
$$;

-- Si se anula la venta con la que se entregó un encargo, el encargo vuelve a quedar pendiente (con su seña)
create or replace function public.ventas_anulada_encargos()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.anulada and not old.anulada then
    update public.encargos set estado = 'pendiente', venta_id = null, cerrado = null, cerrado_por = null where venta_id = new.id and estado = 'entregado';
  end if;
  return new;
end;
$$;
create trigger ventas_anulada_encargos after update of anulada on public.ventas for each row execute function public.ventas_anulada_encargos();

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
    where pr.negocio_id = v_neg and pr.activo and not pr.a_revisar   -- los creados en caja: su stock todavía no se contó
      and pr.stock - public.comprometido(pr.id) <= greatest(pr.stock_min, 0)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'producto_id', f.id, 'nombre', f.nombre, 'codigo', f.codigo, 'codigo_proveedor', pp.codigo_proveedor, 'por_peso', f.por_peso,
      'stock', f.stock, 'stock_min', f.stock_min, 'sin_stock', f.stock <= 0,
      'propuesta', public.cantidad_propuesta(f.stock - f.comprometido, f.stock_min, f.por_peso),
      'cantidad', coalesce(pi.cantidad, public.cantidad_propuesta(f.stock - f.comprometido, f.stock_min, f.por_peso)),
      'pendiente', coalesce(pi.pendiente, false),
      'para_entregar', f.comprometido,
      'entregas', (select string_agg(x.t, ', ' order by x.o) from (
                     select trim_scale(e.cantidad)::text || ' a ' || e.a_nombre || ' (venta #' || vv.numero || ')' as t, e.creado as o
                       from public.entregas_pendientes e join public.ventas vv on vv.id = e.venta_id where e.producto_id = f.id and e.estado = 'pendiente'
                     union all
                     select trim_scale(en.cantidad)::text || ' a ' || en.a_nombre || ' (encargo #' || en.numero || ')', en.creado
                       from public.encargos en where en.producto_id = f.id and en.estado = 'pendiente') x),
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

-- Anular una venta pagada en parte con seña: esa parte no sale de la caja (la seña vuelve al encargo)
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
  if v_resto > 0 and exists (select 1 from public.venta_pagos where venta_id = v.id and forma not in ('Fiado', 'Seña')) then t := public.requiere_turno(); end if;
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
    elsif pg.forma = 'Seña' then
      null;   -- la seña sigue en la caja: vuelve al encargo, que queda pendiente otra vez
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

drop function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb);
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false, p_descuento numeric default 0, p_autorizacion uuid default null,
  p_entrega jsonb default null, p_encargos jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas; c public.clientes;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_precio numeric; v_importe numeric; v_etiqueta numeric;
  v_sub numeric := 0; v_desc_ren numeric := 0; v_desc numeric; v_base numeric; v_bases numeric := 0; v_b numeric; v_pct numeric;
  v_rec numeric; v_recargo numeric := 0; v_fiado numeric := 0; v_pid bigint; v_saldo numeric; v_forma text;
  v_manual numeric; v_alista numeric; v_pct_desc numeric; v_tope numeric; v_aut bigint;
  v_item bigint; v_pend numeric; v_ent_nombre text; v_ent_tel text;
  v_enc public.encargos; v_enc_ids bigint[] := '{}'; v_sena_disp numeric := 0; v_sena numeric := 0;
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
  -- encargos que se entregan con esta venta: su seña (que ya entró a la caja) se puede usar como pago "Seña"
  if p_encargos is not null and jsonb_typeof(p_encargos) <> 'null' then
    if jsonb_typeof(p_encargos) <> 'array' then raise exception 'Encargos inválidos' using errcode = '22023'; end if;
    v_enc_ids := array(select distinct (x #>> '{}')::bigint from jsonb_array_elements(p_encargos) x);
    for v_enc in select * from public.encargos where negocio_id = v_neg and id = any (v_enc_ids) for update loop
      if v_enc.estado <> 'pendiente' then raise exception 'El encargo #% ya no está pendiente', v_enc.numero using errcode = 'P0001'; end if;
      v_sena_disp := v_sena_disp + v_enc.sena;
    end loop;
    if (select count(*) from public.encargos where negocio_id = v_neg and id = any (v_enc_ids)) <> cardinality(v_enc_ids) then
      raise exception 'Encargo no encontrado' using errcode = 'P0002';
    end if;
  end if;
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
    if v_forma not in ('Fiado', 'Seña') and not (v_forma = any (v_formas)) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    if v_forma = 'Fiado' and c.id is null then raise exception 'Para fiar hay que elegir el cliente' using errcode = '22023'; end if;
    v_pct := case when v_forma = 'Seña' then 0 else public.pct_recargo(v_neg, v_forma) end;
    v_rec := case when v_pct > 0 then round(v_b * v_pct / 100, 0) else 0 end;
    insert into public.venta_pagos (negocio_id, venta_id, forma, monto, recargo, pct_recargo) values (v_neg, v.id, v_forma, v_b + v_rec, v_rec, v_pct);
    if v_forma = 'Fiado' then
      v_fiado := v_fiado + v_b + v_rec;
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id, turno_id)
        values (v_neg, c.id, 'cargo', v_b + v_rec, 'Compra #' || v.numero, v.id, v_u, t.id);
    elsif v_forma = 'Seña' then
      v_sena := v_sena + v_b;   -- ya entró a la caja cuando se dejó la seña
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_b + v_rec, v_forma, v.id);
    end if;
    v_bases := v_bases + v_b; v_recargo := v_recargo + v_rec;
  end loop;
  if abs(v_bases - v_base) > 0.005 then
    raise exception 'Los pagos (%) no suman el total (%)', v_bases, v_base using errcode = '22023';
  end if;
  if v_sena > v_sena_disp + 0.005 then
    raise exception 'La seña que se usa (%) pasa la de los encargos (%)', v_sena, v_sena_disp using errcode = '22023';
  end if;
  if cardinality(v_enc_ids) > 0 then
    update public.encargos set estado = 'entregado', venta_id = v.id, cerrado = now(), cerrado_por = v_u
      where negocio_id = v_neg and id = any (v_enc_ids);
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

revoke all on function public.encargo_json(public.encargos), public.registrar_encargo(jsonb), public.encargos(),
  public.cancelar_encargo(bigint, boolean, text), public.ventas_anulada_encargos(),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.registrar_encargo(jsonb), public.encargos(), public.cancelar_encargo(bigint, boolean, text),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 25, 'hora', now());
$$;
