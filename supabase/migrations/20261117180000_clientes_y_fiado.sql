-- =====================================================================
-- Etapa 4a: clientes y fiado (cuenta corriente)
--
-- Cuenta del cliente (tabla cc): monto > 0 suma deuda (cargo por una compra fiada, ajuste), < 0 la baja (pago, ajuste).
-- Saldo = suma: positivo, el cliente debe; negativo, tiene a favor.
-- Fiado es una forma de pago más en la venta (no pasa por la caja). Si el cliente tiene límite y lo pasaría,
-- la base corta con hint 'limite' y la pantalla puede reintentar con p_forzar_limite.
-- =====================================================================

create table public.clientes (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 80),
  telefono text check (length(telefono) <= 40),
  direccion text check (length(direccion) <= 120),
  limite numeric(14, 2) not null default 0 check (limite >= 0),   -- 0 = sin límite
  notas text check (length(notas) <= 500),
  activo boolean not null default true,
  creado timestamptz not null default now(),
  unique (id, negocio_id)
);
create unique index clientes_nombre_unico on public.clientes (negocio_id, lower(btrim(nombre))) where activo;

create table public.cc (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  cliente_id bigint not null,
  fecha timestamptz not null default now(),
  tipo text not null check (tipo in ('cargo', 'pago', 'ajuste')),
  monto numeric(14, 2) not null check (monto <> 0),
  concepto text not null default '',
  forma text not null default '',
  venta_id bigint,
  usuario_id bigint not null,
  turno_id bigint,
  foreign key (cliente_id, negocio_id) references public.clientes (id, negocio_id),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id)
);
create index cc_cliente on public.cc (cliente_id);

alter table public.ventas add column cliente_id bigint;
alter table public.ventas add foreign key (cliente_id, negocio_id) references public.clientes (id, negocio_id);
alter table public.caja add column cc_id bigint;   -- cobro de fiado

alter table public.clientes enable row level security;
alter table public.cc enable row level security;
revoke all on public.clientes, public.cc from anon, authenticated;

-- ---------------------------------------------------------------------
-- Ayudas
-- ---------------------------------------------------------------------
create or replace function public.saldo_cliente(p_cliente bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(monto), 0) from public.cc where cliente_id = p_cliente;
$$;

create or replace function public.cliente_json(c public.clientes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'nombre', c.nombre, 'telefono', c.telefono, 'direccion', c.direccion,
    'limite', c.limite, 'notas', c.notas, 'activo', c.activo, 'saldo', public.saldo_cliente(c.id));
$$;

create or replace function public.requiere_cliente(p_id bigint)
returns public.clientes language plpgsql stable security definer set search_path = '' as $$
declare c public.clientes;
begin
  select * into c from public.clientes where id = p_id and negocio_id = public.requiere_negocio();
  if not found then raise exception 'Cliente no encontrado' using errcode = 'P0002'; end if;
  return c;
end;
$$;

-- ---------------------------------------------------------------------
-- Clientes
-- ---------------------------------------------------------------------

-- Clientes activos (y los dados de baja que todavía tienen saldo), con su saldo
create or replace function public.clientes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_usuario();
  return coalesce((select jsonb_agg(public.cliente_json(c) order by lower(c.nombre))
    from public.clientes c where c.negocio_id = v_neg and (c.activo or public.saldo_cliente(c.id) <> 0)), '[]'::jsonb);
end;
$$;

-- Crear o editar un cliente (cualquier usuario; el límite de fiado lo cambia solo el dueño)
create or replace function public.guardar_cliente(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_nombre text := btrim(coalesce(p ->> 'nombre', '')); v_limite numeric := round(public.num(p, 'limite', 'Límite'), 2);
  c public.clientes; r public.clientes;
begin
  perform public.requiere_usuario();
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if v_limite < 0 then raise exception 'El límite no puede ser negativo' using errcode = '22023'; end if;
  if exists (select 1 from public.clientes where negocio_id = v_neg and activo and lower(btrim(nombre)) = lower(v_nombre) and id is distinct from v_id) then
    raise exception 'Ya hay un cliente con ese nombre' using errcode = '23505';
  end if;
  if v_id is not null then c := public.requiere_cliente(v_id); end if;
  if not public.es_admin() and v_limite is distinct from coalesce(c.limite, 0) and v_limite is not null then
    raise exception 'El límite de fiado lo cambia solo el dueño' using errcode = '42501';
  end if;
  if v_id is null then
    insert into public.clientes (negocio_id, nombre, telefono, direccion, limite, notas)
      values (v_neg, v_nombre, nullif(btrim(p ->> 'telefono'), ''), nullif(btrim(p ->> 'direccion'), ''), coalesce(v_limite, 0), nullif(btrim(p ->> 'notas'), ''))
      returning * into r;
  else
    update public.clientes set nombre = v_nombre, telefono = nullif(btrim(p ->> 'telefono'), ''), direccion = nullif(btrim(p ->> 'direccion'), ''),
        limite = coalesce(v_limite, limite), notas = nullif(btrim(p ->> 'notas'), '')
      where id = v_id returning * into r;
  end if;
  return public.cliente_json(r);
end;
$$;

-- Si tiene movimientos o ventas se da de baja; si no, se borra. Con saldo no se puede.
create or replace function public.eliminar_cliente(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare c public.clientes;
begin
  perform public.requiere_admin();
  c := public.requiere_cliente(p_id);
  if public.saldo_cliente(c.id) <> 0 then raise exception 'No se puede: tiene saldo pendiente' using errcode = 'P0001'; end if;
  if exists (select 1 from public.cc where cliente_id = c.id) or exists (select 1 from public.ventas where cliente_id = c.id) then
    update public.clientes set activo = false where id = c.id;
    return jsonb_build_object('desactivado', true);
  end if;
  delete from public.clientes where id = c.id;
  return jsonb_build_object('eliminado', true);
end;
$$;

-- Cuenta del cliente: sus datos, saldo y movimientos (del más viejo al más nuevo)
create or replace function public.cuenta_cliente(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c public.clientes;
begin
  perform public.requiere_usuario();
  c := public.requiere_cliente(p_id);
  return public.cliente_json(c) || jsonb_build_object('movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'fecha', m.fecha,
      'tipo', m.tipo, 'monto', m.monto, 'concepto', m.concepto, 'forma', m.forma, 'venta_id', m.venta_id,
      'usuario', public.nombre_usuario(m.usuario_id)) order by m.id) from public.cc m where m.cliente_id = c.id), '[]'::jsonb));
end;
$$;

-- Cobrar (el cliente paga lo que debe): entra a la caja del turno
create or replace function public.cobrar_cliente(p_cliente_id bigint, p_monto numeric, p_forma text, p_concepto text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); c public.clientes; t public.turnos; v_cc bigint;
begin
  perform 1 from public.negocios where id = v_neg for update;
  c := public.requiere_cliente(p_cliente_id);
  if coalesce(p_monto, 0) <= 0 then raise exception 'El monto tiene que ser mayor a 0' using errcode = '22023'; end if;
  if not (coalesce(p_forma, '') = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
  t := public.requiere_turno();
  insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, forma, usuario_id, turno_id)
    values (v_neg, c.id, 'pago', -round(p_monto, 2), coalesce(nullif(left(btrim(p_concepto), 120), ''), 'Pago'), p_forma, v_u, t.id)
    returning id into v_cc;
  insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, cc_id)
    values (v_neg, t.id, v_u, 'ingreso', 'Cobro fiado — ' || c.nombre, round(p_monto, 2), p_forma, v_cc);
  return jsonb_build_object('saldo', public.saldo_cliente(c.id));
end;
$$;

-- Deuda anterior o corrección (solo dueño). No mueve plata.
create or replace function public.ajuste_cliente(p_cliente_id bigint, p_monto numeric, p_concepto text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); c public.clientes;
begin
  c := public.requiere_cliente(p_cliente_id);
  if coalesce(round(p_monto, 2), 0) = 0 then raise exception 'El monto no puede ser 0' using errcode = '22023'; end if;
  insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, usuario_id)
    values (v_neg, c.id, 'ajuste', round(p_monto, 2),
      coalesce(nullif(left(btrim(p_concepto), 120), ''), case when p_monto > 0 then 'Deuda anterior' else 'Ajuste' end), v_u);
  return jsonb_build_object('saldo', public.saldo_cliente(c.id));
end;
$$;

-- ---------------------------------------------------------------------
-- Ventas con cliente y fiado
-- ---------------------------------------------------------------------
create or replace function public.venta_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'usuario', public.nombre_usuario(v.usuario_id),
    'turno_id', v.turno_id, 'subtotal', v.subtotal, 'total', v.total, 'paga_con', v.paga_con,
    'cliente', (select jsonb_build_object('id', c.id, 'nombre', c.nombre) from public.clientes c where c.id = v.cliente_id),
    'anulada', v.anulada, 'anulada_fecha', v.anulada_fecha, 'anulada_por', case when v.anulada then public.nombre_usuario(v.anulada_por) end,
    'motivo_anulacion', v.motivo_anulacion,
    'items', coalesce((select jsonb_agg(jsonb_build_object('producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'precio', i.precio, 'importe', i.importe, 'por_peso', i.por_peso) order by i.id)
                       from public.venta_items i where i.venta_id = v.id), '[]'::jsonb),
    'pagos', coalesce((select jsonb_agg(jsonb_build_object('forma', p.forma, 'monto', p.monto) order by p.id)
                       from public.venta_pagos p where p.venta_id = v.id), '[]'::jsonb))
  from public.ventas v where v.id = p_id;
$$;

drop function public.registrar_venta(uuid, jsonb, jsonb, numeric);

-- Igual que en la etapa 3, más: p_cliente_id (opcional; obligatorio para fiar) y la forma de pago 'Fiado',
-- que carga la deuda en la cuenta del cliente en lugar de entrar a la caja.
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas; c public.clientes;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_importe numeric; v_monto numeric;
  v_sub numeric := 0; v_pagado numeric := 0; v_fiado numeric := 0; v_pid bigint; v_saldo numeric;
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
      v_importe := round(v_cant * p.precio, 2);
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe, costo, por_peso, categoria_id, precio_lista)
        values (v_neg, v.id, p.id, p.nombre, v_cant, p.precio, v_importe, p.costo, p.por_peso, p.categoria_id, p.precio);
      update public.productos set stock = stock - v_cant where id = p.id;
    else
      v_importe := round(public.num(it, 'importe', 'Importe'), 2);
      if v_importe is null or v_importe <= 0 then raise exception 'El importe de "Varios" tiene que ser mayor a 0' using errcode = '22023'; end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe)
        values (v_neg, v.id, null, coalesce(nullif(left(btrim(it ->> 'nombre'), 120), ''), 'Varios'), 1, v_importe, v_importe);
    end if;
    v_sub := v_sub + v_importe;
  end loop;

  v_formas := public.formas_pago(v_neg);
  for pg in select value from jsonb_array_elements(p_pagos) loop
    v_monto := round(public.num(pg, 'monto', 'Monto del pago'), 2);
    if v_monto is null or v_monto <= 0 then continue; end if;
    if pg ->> 'forma' = 'Fiado' then
      if c.id is null then raise exception 'Para fiar hay que elegir el cliente' using errcode = '22023'; end if;
      v_fiado := v_fiado + v_monto;
      insert into public.venta_pagos (negocio_id, venta_id, forma, monto) values (v_neg, v.id, 'Fiado', v_monto);
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id, turno_id)
        values (v_neg, c.id, 'cargo', v_monto, 'Compra #' || v.numero, v.id, v_u, t.id);
    else
      if not (coalesce(pg ->> 'forma', '') = any (v_formas)) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
      insert into public.venta_pagos (negocio_id, venta_id, forma, monto) values (v_neg, v.id, pg ->> 'forma', v_monto);
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_monto, pg ->> 'forma', v.id);
    end if;
    v_pagado := v_pagado + v_monto;
  end loop;
  if abs(v_pagado - v_sub) > 0.005 then
    raise exception 'Los pagos (%) no suman el total (%)', v_pagado, v_sub using errcode = '22023';
  end if;
  -- límite de fiado: se controla con la deuda ya cargada (la de esta venta incluida)
  if v_fiado > 0 and c.limite > 0 and not coalesce(p_forzar_limite, false) then
    v_saldo := public.saldo_cliente(c.id);
    if v_saldo > c.limite then
      raise exception '% pasaría su límite de fiado (%): quedaría debiendo %', c.nombre, c.limite, v_saldo using errcode = 'P0001', hint = 'limite';
    end if;
  end if;

  update public.ventas set subtotal = v_sub, total = v_sub,
      paga_con = case when p_paga_con >= v_sub then round(p_paga_con, 2) end
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

-- Anular: el fiado vuelve a la cuenta del cliente; lo demás sale de la caja (y solo entonces hace falta el turno)
create or replace function public.anular_venta(p_id bigint, p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v public.ventas; t public.turnos; i record; pg record;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into v from public.ventas where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Venta no encontrada' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'La venta ya estaba anulada' using errcode = 'P0001'; end if;
  if exists (select 1 from public.venta_pagos where venta_id = v.id and forma <> 'Fiado') then t := public.requiere_turno(); end if;
  for i in select * from public.venta_items where venta_id = v.id and producto_id is not null loop
    update public.productos set stock = stock + i.cantidad where id = i.producto_id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
      values (v_neg, i.producto_id, i.cantidad, 'Anulación venta #' || v.numero, v_u);
  end loop;
  for pg in select * from public.venta_pagos where venta_id = v.id loop
    if pg.forma = 'Fiado' then
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id)
        values (v_neg, v.cliente_id, 'ajuste', -pg.monto, 'Anulación compra #' || v.numero, v.id, v_u);
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'egreso', 'Anulación venta #' || v.numero, pg.monto, pg.forma, v.id);
    end if;
  end loop;
  update public.ventas set anulada = true, anulada_fecha = now(), anulada_por = v_u,
      motivo_anulacion = nullif(left(btrim(coalesce(p_motivo, '')), 200), '')
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

-- Las ventas del turno muestran el cliente
create or replace function public.estado_caja()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); t public.turnos;
begin
  perform public.requiere_usuario();
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then
    return jsonb_build_object('turno', null, 'formas_pago', to_jsonb(public.formas_pago(v_neg)));
  end if;
  return jsonb_build_object(
    'formas_pago', to_jsonb(public.formas_pago(v_neg)),
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
        'anulada', v.anulada, 'usuario', public.nombre_usuario(v.usuario_id),
        'cliente', (select c.nombre from public.clientes c where c.id = v.cliente_id),
        'fiado', exists (select 1 from public.venta_pagos p where p.venta_id = v.id and p.forma = 'Fiado'),
        'resumen', (select string_agg(i.nombre, ', ' order by i.id) from public.venta_items i where i.venta_id = v.id)) order by v.id desc)
      from public.ventas v where v.turno_id = t.id), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.saldo_cliente(bigint), public.cliente_json(public.clientes), public.requiere_cliente(bigint),
  public.clientes(), public.guardar_cliente(jsonb), public.eliminar_cliente(bigint), public.cuenta_cliente(bigint),
  public.cobrar_cliente(bigint, numeric, text, text), public.ajuste_cliente(bigint, numeric, text),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean)
  from public, anon, authenticated;

grant execute on function public.clientes(), public.guardar_cliente(jsonb), public.eliminar_cliente(bigint), public.cuenta_cliente(bigint),
  public.cobrar_cliente(bigint, numeric, text, text), public.ajuste_cliente(bigint, numeric, text),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean)
  to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 4, 'hora', now());
$$;
