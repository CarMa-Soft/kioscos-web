-- Cuenta del cliente como la del proveedor: plazo, vencimientos y aplicación de pagos a las ventas fiadas.
--
-- Deudas del cliente (lo que se aplica):
--   · cada venta fiada: su importe es la suma de sus movimientos en cc (el cargo "Compra #N" menos lo que restaron su
--     anulación o sus devoluciones a la cuenta). Si esa suma da negativa (se devolvió a la cuenta más de lo fiado), el
--     exceso es un crédito.
--   · cada ajuste que suma sin venta (deuda anterior).
-- Créditos: los pagos y los ajustes que restan sin venta (y el exceso de una venta, ver arriba).
-- aplicaciones_cli: qué parte de cada crédito cubre cada deuda. Siempre: suma de pendientes − suma de libres = saldo.
-- Vencimiento: fecha de la venta (o del ajuste) + plazo del cliente, o el general (config 'plazo_clientes', 30 de fábrica).
-- Se calcula al mostrarlo: si cambia el plazo, cambia el vencimiento de lo pendiente.
--
-- No se tocan registrar_venta, anular_venta ni devolver_venta: un disparador en cc, en cada movimiento que no es un pago,
-- recorta lo aplicado de más (si una devolución o anulación dejó una venta con más pagado que su importe) y aplica lo
-- que haya a favor a lo pendiente, empezando por lo que vence primero. Los pagos los aplica cobrar_cliente.

alter table public.clientes add column plazo integer check (plazo between 0 and 365);   -- null = el general de Ajustes
alter table public.cc add unique (id, negocio_id);

create table public.aplicaciones_cli (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  cliente_id bigint not null,
  credito_id bigint not null,                               -- pago o ajuste que resta (cc)
  venta_id bigint,                                          -- la deuda: una venta fiada…
  deuda_id bigint,                                          -- …o un ajuste que suma (cc)
  monto numeric(14, 2) not null check (monto > 0),
  fecha timestamptz not null default now(),
  usuario_id bigint,
  check ((venta_id is null) <> (deuda_id is null)),
  foreign key (cliente_id, negocio_id) references public.clientes (id, negocio_id),
  foreign key (credito_id, negocio_id) references public.cc (id, negocio_id),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id),
  foreign key (deuda_id, negocio_id) references public.cc (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index aplicaciones_cli_cliente on public.aplicaciones_cli (cliente_id);
create index aplicaciones_cli_credito on public.aplicaciones_cli (credito_id);
create index aplicaciones_cli_venta on public.aplicaciones_cli (venta_id);
create index aplicaciones_cli_deuda on public.aplicaciones_cli (deuda_id);
alter table public.aplicaciones_cli enable row level security;
revoke all on public.aplicaciones_cli from anon, authenticated;

-- ---------------------------------------------------------------------
-- Plazo general
-- ---------------------------------------------------------------------
create or replace function public.plazo_clientes(p_neg uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select coalesce((select (c.valor #>> '{}')::integer from public.config c
                   where c.negocio_id = p_neg and c.clave = 'plazo_clientes' and jsonb_typeof(c.valor) = 'number'), 30);
$$;

create or replace function public.guardar_plazo_clientes(p_dias integer)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if p_dias is null or p_dias < 0 or p_dias > 365 then raise exception 'El plazo tiene que ser entre 0 y 365 días' using errcode = '22023'; end if;
  insert into public.config (negocio_id, clave, valor) values (v_neg, 'plazo_clientes', to_jsonb(p_dias))
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
  return p_dias;
end;
$$;

-- ---------------------------------------------------------------------
-- Deudas y créditos del cliente
-- ---------------------------------------------------------------------
create or replace function public.deudas_cliente(p_cliente bigint)
returns table (venta_id bigint, deuda_id bigint, numero integer, concepto text, fecha timestamptz, vencimiento date,
               importe numeric, aplicado numeric, pendiente numeric, pagada timestamptz)
language sql stable security definer set search_path = '' as $$
  with cl as (select coalesce(c.plazo, public.plazo_clientes(c.negocio_id)) as plazo, public.zona_horaria(c.negocio_id) as z
              from public.clientes c where c.id = p_cliente),
  v as (select m.venta_id, sum(m.monto) as s from public.cc m where m.cliente_id = p_cliente and m.venta_id is not null group by m.venta_id),
  d as (
    select v.venta_id, null::bigint as deuda_id, ve.numero, 'Compra #' || ve.numero as concepto, ve.fecha, v.s as importe
      from v join public.ventas ve on ve.id = v.venta_id where v.s > 0
    union all
    select null, m.id, null, m.concepto, m.fecha, m.monto
      from public.cc m where m.cliente_id = p_cliente and m.venta_id is null and m.tipo = 'ajuste' and m.monto > 0)
  select d.venta_id, d.deuda_id, d.numero, d.concepto, d.fecha,
    (d.fecha at time zone (select z from cl))::date + (select plazo from cl) as vencimiento,
    d.importe, x.aplicado, d.importe - x.aplicado, case when d.importe - x.aplicado <= 0.004 then x.ultima end
  from d cross join lateral (
    select coalesce(sum(a.monto), 0) as aplicado, max(a.fecha) as ultima from public.aplicaciones_cli a
    where (d.venta_id is not null and a.venta_id = d.venta_id) or (d.deuda_id is not null and a.deuda_id = d.deuda_id)) x
  order by 6, d.fecha;
$$;

create or replace function public.creditos_cliente(p_cliente bigint)
returns table (id bigint, venta_id bigint, fecha timestamptz, importe numeric, aplicado numeric, libre numeric)
language sql stable security definer set search_path = '' as $$
  with cr as (
    select m.id, null::bigint as venta_id, m.fecha, -m.monto as importe
      from public.cc m where m.cliente_id = p_cliente and m.venta_id is null and m.monto < 0
    union all
    -- una venta a la que se devolvió a la cuenta más de lo fiado: el exceso (con el id de su primer movimiento que resta)
    select (select min(n.id) from public.cc n where n.venta_id = v.venta_id and n.monto < 0), v.venta_id,
      (select max(n.fecha) from public.cc n where n.venta_id = v.venta_id), -v.s
      from (select m.venta_id, sum(m.monto) as s from public.cc m where m.cliente_id = p_cliente and m.venta_id is not null group by m.venta_id) v
      where v.s < 0)
  select cr.id, cr.venta_id, cr.fecha, cr.importe, x.aplicado, cr.importe - x.aplicado
  from cr cross join lateral (select coalesce(sum(a.monto), 0) as aplicado from public.aplicaciones_cli a where a.credito_id = cr.id) x
  order by cr.id;
$$;

-- ---------------------------------------------------------------------
-- Aplicar
-- ---------------------------------------------------------------------
create or replace function public.aplicar_cli(p_neg uuid, p_cliente bigint, p_credito bigint, p_venta bigint, p_deuda bigint, p_monto numeric, p_usuario bigint)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.aplicaciones_cli (negocio_id, cliente_id, credito_id, venta_id, deuda_id, monto, usuario_id)
  select p_neg, p_cliente, p_credito, p_venta, p_deuda, round(p_monto, 2), p_usuario where round(p_monto, 2) > 0;
$$;

-- Lo que esté a favor, a lo pendiente: los créditos del más viejo al más nuevo, a lo que vence primero
create or replace function public.aplicar_automatico_cli(p_cliente bigint, p_usuario bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := (select negocio_id from public.clientes where id = p_cliente); cr record; dd record; v_libre numeric; v_m numeric;
begin
  for cr in select * from public.creditos_cliente(p_cliente) where libre > 0.004 loop
    v_libre := cr.libre;
    for dd in select * from public.deudas_cliente(p_cliente) where pendiente > 0.004 loop
      exit when v_libre <= 0.004;
      v_m := least(v_libre, dd.pendiente);
      perform public.aplicar_cli(v_neg, p_cliente, cr.id, dd.venta_id, dd.deuda_id, v_m, p_usuario);
      v_libre := v_libre - v_m;
    end loop;
  end loop;
end;
$$;

-- Si una venta quedó con más aplicado que su importe (devolución o anulación), se saca lo de más, de lo último aplicado
create or replace function public.recortar_aplicaciones_cli(p_cliente bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare t record; a record; v_sobra numeric;
begin
  for t in
    select x.venta_id, x.deuda_id, x.aplicado - coalesce(d.importe, 0) as sobra
    from (select ap.venta_id, ap.deuda_id, sum(ap.monto) as aplicado from public.aplicaciones_cli ap
          where ap.cliente_id = p_cliente group by ap.venta_id, ap.deuda_id) x
    left join public.deudas_cliente(p_cliente) d on d.venta_id = x.venta_id or d.deuda_id = x.deuda_id
    where x.aplicado - coalesce(d.importe, 0) > 0.004
  loop
    v_sobra := t.sobra;
    for a in select * from public.aplicaciones_cli ap where ap.cliente_id = p_cliente
               and (ap.venta_id = t.venta_id or ap.deuda_id = t.deuda_id) order by ap.id desc loop
      exit when v_sobra <= 0.004;
      if a.monto <= v_sobra + 0.004 then
        delete from public.aplicaciones_cli where id = a.id; v_sobra := v_sobra - a.monto;
      else
        update public.aplicaciones_cli set monto = monto - round(v_sobra, 2) where id = a.id; v_sobra := 0;
      end if;
    end loop;
  end loop;
end;
$$;

-- p_lista: [{ venta_id | deuda_id, monto }]. Con p_credito, solo de ese crédito (un pago); si no, de lo que esté a favor.
create or replace function public.aplicar_lista_cli(p_neg uuid, p_cliente bigint, p_lista jsonb, p_credito bigint, p_usuario bigint)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare x jsonb; dd record; v_m numeric; v_total numeric := 0; cr record; v_falta numeric; v_usar numeric;
begin
  if p_lista is null or jsonb_typeof(p_lista) <> 'array' then return 0; end if;
  for x in select value from jsonb_array_elements(p_lista) loop
    v_m := round(public.num(x, 'monto', 'Monto aplicado'), 2);
    if v_m is null or v_m <= 0 then continue; end if;
    select * into dd from public.deudas_cliente(p_cliente) d
      where (d.venta_id = nullif(x ->> 'venta_id', '')::bigint) or (d.deuda_id = nullif(x ->> 'deuda_id', '')::bigint);
    if not found then raise exception 'Hay una compra que no es de este cliente o ya no está pendiente' using errcode = 'P0002'; end if;
    if v_m > dd.pendiente + 0.004 then
      raise exception 'A % le quedan % por pagar', case when dd.venta_id is not null then 'la compra #' || dd.numero
        else coalesce(nullif(dd.concepto, ''), 'una deuda') end, dd.pendiente using errcode = '22023';
    end if;
    v_falta := v_m;
    for cr in select * from public.creditos_cliente(p_cliente) c where c.libre > 0.004 and (p_credito is null or c.id = p_credito) loop
      exit when v_falta <= 0.004;
      v_usar := least(cr.libre, v_falta);
      perform public.aplicar_cli(p_neg, p_cliente, cr.id, dd.venta_id, dd.deuda_id, v_usar, p_usuario);
      v_falta := v_falta - v_usar;
    end loop;
    if v_falta > 0.004 then
      raise exception '%', case when p_credito is null then 'No hay tanto a favor sin aplicar' else 'Lo aplicado a las compras suma más que el pago' end
        using errcode = '22023';
    end if;
    v_total := v_total + v_m;
  end loop;
  return v_total;
end;
$$;

-- El disparador: cada movimiento que no es un pago (venta fiada, anulación, devolución, ajuste) recorta y aplica lo que haya a favor
create or replace function public.cc_aplicar()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo <> 'pago' then
    perform public.recortar_aplicaciones_cli(new.cliente_id);
    perform public.aplicar_automatico_cli(new.cliente_id, new.usuario_id);
  end if;
  return null;
end;
$$;
create trigger cc_aplicar after insert on public.cc for each row execute function public.cc_aplicar();

-- ---------------------------------------------------------------------
-- Clientes: plazo
-- ---------------------------------------------------------------------
create or replace function public.cliente_json(c public.clientes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'nombre', c.nombre, 'telefono', c.telefono, 'direccion', c.direccion,
    'limite', c.limite, 'plazo', c.plazo, 'notas', c.notas, 'activo', c.activo, 'saldo', public.saldo_cliente(c.id));
$$;

-- Crear o editar un cliente (cualquier usuario; el límite de fiado y el plazo los cambia solo el dueño).
-- plazo: si no viene, no cambia; vacío = el general de Ajustes.
create or replace function public.guardar_cliente(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_nombre text := btrim(coalesce(p ->> 'nombre', '')); v_limite numeric := round(public.num(p, 'limite', 'Límite'), 2);
  v_hay_plazo boolean := p ? 'plazo'; v_plazo numeric := public.num(p, 'plazo', 'Plazo');
  c public.clientes; r public.clientes;
begin
  perform public.requiere_usuario();
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if v_limite < 0 then raise exception 'El límite no puede ser negativo' using errcode = '22023'; end if;
  if v_plazo is not null and (v_plazo < 0 or v_plazo > 365 or v_plazo <> trunc(v_plazo)) then
    raise exception 'El plazo tiene que ser de 0 a 365 días' using errcode = '22023';
  end if;
  if exists (select 1 from public.clientes where negocio_id = v_neg and activo and lower(btrim(nombre)) = lower(v_nombre) and id is distinct from v_id) then
    raise exception 'Ya hay un cliente con ese nombre' using errcode = '23505';
  end if;
  if v_id is not null then c := public.requiere_cliente(v_id); end if;
  if not public.es_admin() and v_limite is distinct from coalesce(c.limite, 0) and v_limite is not null then
    raise exception 'El límite de fiado lo cambia solo el dueño' using errcode = '42501';
  end if;
  if not public.es_admin() and v_hay_plazo and v_plazo::integer is distinct from c.plazo then
    raise exception 'El plazo lo cambia solo el dueño' using errcode = '42501';
  end if;
  if v_id is null then
    insert into public.clientes (negocio_id, nombre, telefono, direccion, limite, plazo, notas)
      values (v_neg, v_nombre, nullif(btrim(p ->> 'telefono'), ''), nullif(btrim(p ->> 'direccion'), ''), coalesce(v_limite, 0),
        case when v_hay_plazo then v_plazo::integer end, nullif(btrim(p ->> 'notas'), ''))
      returning * into r;
  else
    update public.clientes set nombre = v_nombre, telefono = nullif(btrim(p ->> 'telefono'), ''), direccion = nullif(btrim(p ->> 'direccion'), ''),
        limite = coalesce(v_limite, limite), plazo = case when v_hay_plazo then v_plazo::integer else plazo end, notas = nullif(btrim(p ->> 'notas'), '')
      where id = v_id returning * into r;
    -- con otro plazo cambian los vencimientos (se calculan al mostrarlos); lo aplicado no cambia
  end if;
  return public.cliente_json(r);
end;
$$;

-- ---------------------------------------------------------------------
-- Cuenta, cobro y aplicación
-- ---------------------------------------------------------------------

-- Cuenta del cliente: datos, saldo, lo pendiente (con vencimiento), lo pagado, lo que está a favor sin aplicar y los movimientos
create or replace function public.cuenta_cliente(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c public.clientes;
begin
  perform public.requiere_usuario();
  c := public.requiere_cliente(p_id);
  return public.cliente_json(c) || jsonb_build_object(
    'plazo_general', public.plazo_clientes(c.negocio_id),
    'hoy', public.hoy_negocio(c.negocio_id),
    'pendientes', coalesce((select jsonb_agg(to_jsonb(d) order by d.vencimiento, d.fecha) from public.deudas_cliente(c.id) d where d.pendiente > 0.004), '[]'::jsonb),
    'pagadas', coalesce((select jsonb_agg(to_jsonb(d) order by d.pagada desc) from
        (select * from public.deudas_cliente(c.id) x where x.pendiente <= 0.004 order by x.pagada desc limit 100) d), '[]'::jsonb),
    'a_favor', (select coalesce(sum(greatest(libre, 0)), 0) from public.creditos_cliente(c.id)),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'fecha', m.fecha,
      'tipo', m.tipo, 'monto', m.monto, 'concepto', m.concepto, 'forma', m.forma, 'venta_id', m.venta_id,
      'usuario', public.nombre_usuario(m.usuario_id)) order by m.id) from public.cc m where m.cliente_id = c.id), '[]'::jsonb));
end;
$$;

-- Cobrar (el cliente paga): entra a la caja del turno. p_aplicaciones: [{ venta_id | deuda_id, monto }] (a qué compras va);
-- sin p_aplicaciones, a lo que vence primero. Lo que sobra queda a favor.
drop function public.cobrar_cliente(bigint, numeric, text, text);
create or replace function public.cobrar_cliente(p_cliente_id bigint, p_monto numeric, p_forma text, p_concepto text default null,
  p_aplicaciones jsonb default null)
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
  if p_aplicaciones is null then perform public.aplicar_automatico_cli(c.id, v_u);
  else perform public.aplicar_lista_cli(v_neg, c.id, p_aplicaciones, v_cc, v_u); end if;
  insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, cc_id)
    values (v_neg, t.id, v_u, 'ingreso', 'Cobro fiado — ' || c.nombre, round(p_monto, 2), p_forma, v_cc);
  return jsonb_build_object('saldo', public.saldo_cliente(c.id));
end;
$$;

-- Aplicar lo que está a favor a compras pendientes (no mueve plata). Sin p_aplicaciones, a lo que vence primero.
create or replace function public.aplicar_cliente(p_cliente_id bigint, p_aplicaciones jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); c public.clientes;
begin
  perform 1 from public.negocios where id = v_neg for update;
  c := public.requiere_cliente(p_cliente_id);
  if p_aplicaciones is null then perform public.aplicar_automatico_cli(c.id, v_u);
  elsif coalesce(public.aplicar_lista_cli(v_neg, c.id, p_aplicaciones, null, v_u), 0) = 0 then
    raise exception 'Elegí a qué compras aplicarlo' using errcode = '22023';
  end if;
  return jsonb_build_object('saldo', public.saldo_cliente(c.id));
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.plazo_clientes(uuid), public.guardar_plazo_clientes(integer), public.deudas_cliente(bigint),
  public.creditos_cliente(bigint), public.aplicar_cli(uuid, bigint, bigint, bigint, bigint, numeric, bigint),
  public.aplicar_automatico_cli(bigint, bigint), public.recortar_aplicaciones_cli(bigint),
  public.aplicar_lista_cli(uuid, bigint, jsonb, bigint, bigint), public.cc_aplicar(),
  public.cobrar_cliente(bigint, numeric, text, text, jsonb), public.aplicar_cliente(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.guardar_plazo_clientes(integer), public.cobrar_cliente(bigint, numeric, text, text, jsonb),
  public.aplicar_cliente(bigint, jsonb) to authenticated;

-- Los pagos que ya había se aplican una sola vez, a lo que vence primero
select public.aplicar_automatico_cli(c.id, null) from public.clientes c;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 23, 'hora', now());
$$;
