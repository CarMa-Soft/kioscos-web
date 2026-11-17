-- =====================================================================
-- Etapa 5a: proveedores, compras y cuenta corriente de proveedores (como en la app local, #27)
--
-- Compra: suma el stock, actualiza el costo (y el precio, si se pone uno nuevo) y deja al proveedor entre los del
-- producto con su último costo. Se paga con la caja (sale del turno) o queda a cuenta del proveedor.
-- Cuenta del proveedor (cc_prov): monto > 0 suma deuda (compra, ajuste), < 0 la baja (pago, ajuste). Saldo = suma.
-- Cada compra con proveedor suma su total; si se pagó con la caja, el pago la cancela en el momento.
-- Todo solo el dueño. Pendiente (etapa 5b): factura pendiente, vencimientos y aplicación de pagos; (5c) devolución a proveedor.
-- =====================================================================

create table public.proveedores (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 80),
  cuit text check (cuit ~ '^\d{2}-\d{8}-\d$'),
  telefono text, contacto text, dias text, notas text,
  plazo integer check (plazo between 0 and 365),            -- días para pagar (lo usa la etapa 5b)
  creado timestamptz not null default now(),
  unique (id, negocio_id)
);
create unique index proveedores_nombre_unico on public.proveedores (negocio_id, lower(btrim(nombre)));
create unique index proveedores_cuit_unico on public.proveedores (negocio_id, cuit) where cuit is not null;

alter table public.productos add column proveedor_id bigint;   -- el habitual
alter table public.productos add foreign key (proveedor_id, negocio_id) references public.proveedores (id, negocio_id);

-- Proveedores de cada producto, con el último costo de cada uno (para comparar)
create table public.producto_proveedores (
  negocio_id uuid not null,
  producto_id bigint not null,
  proveedor_id bigint not null,
  ultimo_costo numeric(14, 2),
  ultima_compra timestamptz,
  codigo_proveedor text,                                    -- para reconocer sus facturas (lectura con IA, más adelante)
  primary key (producto_id, proveedor_id),
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete cascade,
  foreign key (proveedor_id, negocio_id) references public.proveedores (id, negocio_id) on delete cascade
);
create index producto_proveedores_proveedor on public.producto_proveedores (proveedor_id);

create table public.compras (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  fecha timestamptz not null default now(),                 -- cuándo se registró
  proveedor_id bigint,
  comprobante text not null default '',
  notas text,
  total numeric(14, 2) not null check (total >= 0),
  pagada_caja boolean not null default false,
  forma text not null default '',
  usuario_id bigint not null,
  turno_id bigint,
  anulada boolean not null default false,
  anulada_fecha timestamptz,
  anulada_por bigint,
  unique (id, negocio_id),
  foreign key (proveedor_id, negocio_id) references public.proveedores (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id),
  foreign key (anulada_por, negocio_id) references public.usuarios (id, negocio_id)
);
create index compras_fecha on public.compras (negocio_id, fecha);
create index compras_proveedor on public.compras (proveedor_id);

create table public.compra_items (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  compra_id bigint not null,
  producto_id bigint not null,
  nombre text not null,
  cantidad numeric(14, 3) not null check (cantidad > 0),
  costo numeric(14, 2) not null check (costo >= 0),
  precio_nuevo numeric(14, 2),
  costo_anterior numeric(14, 2),
  precio_anterior numeric(14, 2),
  unique (id, negocio_id),
  foreign key (compra_id, negocio_id) references public.compras (id, negocio_id) on delete cascade,
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id)
);
create index compra_items_compra on public.compra_items (compra_id);
create index compra_items_producto on public.compra_items (producto_id);

create table public.cc_prov (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  proveedor_id bigint not null,
  fecha timestamptz not null default now(),
  tipo text not null check (tipo in ('compra', 'pago', 'ajuste', 'anulacion')),
  monto numeric(14, 2) not null check (monto <> 0),
  concepto text not null default '',
  forma text not null default '',
  de_caja boolean not null default false,
  compra_id bigint,
  turno_id bigint,
  usuario_id bigint not null,
  anulado boolean not null default false,
  anula_id bigint,
  unique (id, negocio_id),
  foreign key (proveedor_id, negocio_id) references public.proveedores (id, negocio_id),
  foreign key (compra_id, negocio_id) references public.compras (id, negocio_id),
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index cc_prov_proveedor on public.cc_prov (proveedor_id);
create index cc_prov_compra on public.cc_prov (compra_id);

alter table public.caja add column compra_id bigint, add column cc_prov_id bigint;
alter table public.caja add foreign key (compra_id, negocio_id) references public.compras (id, negocio_id);
alter table public.caja add foreign key (cc_prov_id, negocio_id) references public.cc_prov (id, negocio_id);

alter table public.proveedores enable row level security;
alter table public.producto_proveedores enable row level security;
alter table public.compras enable row level security;
alter table public.compra_items enable row level security;
alter table public.cc_prov enable row level security;
revoke all on public.proveedores, public.producto_proveedores, public.compras, public.compra_items, public.cc_prov from anon, authenticated;

-- ---------------------------------------------------------------------
-- Ayudas
-- ---------------------------------------------------------------------
-- CUIT: 11 números con el dígito verificador correcto. Devuelve 20-12345678-9, null si viene vacío, o corta.
create or replace function public.cuit_valido(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g'); s integer := 0; r integer; w integer[] := array[5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
begin
  if d = '' then return null; end if;
  if length(d) <> 11 then raise exception 'El CUIT tiene que tener 11 números' using errcode = '22023'; end if;
  for i in 1..10 loop s := s + w[i] * substr(d, i, 1)::int; end loop;
  r := 11 - s % 11;
  r := case when r = 11 then 0 when r = 10 then 9 else r end;
  if r <> substr(d, 11, 1)::int then
    raise exception 'El CUIT %-%-% no es válido (el último número no coincide): revisalo', substr(d, 1, 2), substr(d, 3, 8), substr(d, 11, 1) using errcode = '22023';
  end if;
  return substr(d, 1, 2) || '-' || substr(d, 3, 8) || '-' || substr(d, 11, 1);
end;
$$;

create or replace function public.saldo_proveedor(p_id bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(monto), 0) from public.cc_prov where proveedor_id = p_id;
$$;

create or replace function public.requiere_proveedor(p_id bigint)
returns public.proveedores language plpgsql stable security definer set search_path = '' as $$
declare p public.proveedores;
begin
  select * into p from public.proveedores where id = p_id and negocio_id = public.requiere_negocio();
  if not found then raise exception 'Proveedor no encontrado' using errcode = 'P0002'; end if;
  return p;
end;
$$;

create or replace function public.proveedor_json(p public.proveedores)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'cuit', p.cuit, 'telefono', p.telefono, 'contacto', p.contacto,
    'dias', p.dias, 'notas', p.notas, 'plazo', p.plazo, 'saldo', public.saldo_proveedor(p.id),
    'productos', (select count(*) from public.producto_proveedores pp join public.productos x on x.id = pp.producto_id
                  where pp.proveedor_id = p.id and x.activo),
    'ultima_compra', (select jsonb_build_object('fecha', c.fecha, 'total', c.total) from public.compras c
                      where c.proveedor_id = p.id and not c.anulada order by c.id desc limit 1));
$$;

-- El producto ahora informa su proveedor habitual
create or replace function public.producto_json(p public.productos, p_costo boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'codigo', p.codigo, 'categoria_id', p.categoria_id,
    'precio', p.precio, 'stock', p.stock, 'stock_min', p.stock_min, 'por_peso', p.por_peso, 'plu', p.plu,
    'favorito', p.favorito, 'activo', p.activo, 'actualizado', p.actualizado, 'proveedor_id', p.proveedor_id)
    || case when p_costo then jsonb_build_object('costo', p.costo) else '{}'::jsonb end;
$$;

-- ---------------------------------------------------------------------
-- Proveedores (solo dueño)
-- ---------------------------------------------------------------------
create or replace function public.proveedores()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return coalesce((select jsonb_agg(public.proveedor_json(p) order by lower(p.nombre)) from public.proveedores p where p.negocio_id = v_neg), '[]'::jsonb);
end;
$$;

create or replace function public.guardar_proveedor(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_nombre text := btrim(coalesce(p ->> 'nombre', '')); v_cuit text := public.cuit_valido(p ->> 'cuit');
  v_plazo integer := round(public.num(p, 'plazo', 'Días de plazo'))::int; r public.proveedores;
begin
  perform public.requiere_admin();
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if v_plazo is not null and (v_plazo < 0 or v_plazo > 365) then raise exception 'Los días de plazo tienen que ser entre 0 y 365' using errcode = '22023'; end if;
  if exists (select 1 from public.proveedores where negocio_id = v_neg and lower(btrim(nombre)) = lower(v_nombre) and id is distinct from v_id) then
    raise exception 'Ya hay un proveedor con ese nombre' using errcode = '23505';
  end if;
  if v_cuit is not null and exists (select 1 from public.proveedores where negocio_id = v_neg and cuit = v_cuit and id is distinct from v_id) then
    raise exception 'Ya hay un proveedor con el CUIT %', v_cuit using errcode = '23505';
  end if;
  if v_id is null then
    insert into public.proveedores (negocio_id, nombre, cuit, telefono, contacto, dias, notas, plazo)
      values (v_neg, v_nombre, v_cuit, nullif(btrim(p ->> 'telefono'), ''), nullif(btrim(p ->> 'contacto'), ''), nullif(btrim(p ->> 'dias'), ''),
              nullif(btrim(p ->> 'notas'), ''), v_plazo) returning * into r;
  else
    perform public.requiere_proveedor(v_id);
    update public.proveedores set nombre = v_nombre, cuit = v_cuit, telefono = nullif(btrim(p ->> 'telefono'), ''), contacto = nullif(btrim(p ->> 'contacto'), ''),
        dias = nullif(btrim(p ->> 'dias'), ''), notas = nullif(btrim(p ->> 'notas'), ''), plazo = v_plazo
      where id = v_id returning * into r;
  end if;
  return public.proveedor_json(r);
end;
$$;

-- Solo si no tiene compras y su cuenta está en cero. Los productos que lo tenían de habitual pasan a otro de sus proveedores.
create or replace function public.eliminar_proveedor(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare r public.proveedores;
begin
  perform public.requiere_admin();
  r := public.requiere_proveedor(p_id);
  if exists (select 1 from public.compras where proveedor_id = r.id) then raise exception 'No se puede: tiene compras registradas' using errcode = 'P0001'; end if;
  if public.saldo_proveedor(r.id) <> 0 then raise exception 'No se puede: su cuenta no está en cero' using errcode = 'P0001'; end if;
  delete from public.producto_proveedores where proveedor_id = r.id;
  update public.productos x set proveedor_id = (select min(pp.proveedor_id) from public.producto_proveedores pp where pp.producto_id = x.id)
    where x.proveedor_id = r.id;
  delete from public.cc_prov where proveedor_id = r.id;
  delete from public.proveedores where id = r.id;
end;
$$;

-- Cuenta del proveedor: sus datos, saldo y movimientos (del más viejo al más nuevo)
create or replace function public.cuenta_proveedor(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r public.proveedores;
begin
  perform public.requiere_admin();
  r := public.requiere_proveedor(p_id);
  return public.proveedor_json(r) || jsonb_build_object('movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'fecha', m.fecha,
      'tipo', m.tipo, 'monto', m.monto, 'concepto', m.concepto, 'forma', m.forma, 'de_caja', m.de_caja, 'compra_id', m.compra_id,
      'anulado', m.anulado, 'usuario', public.nombre_usuario(m.usuario_id)) order by m.id) from public.cc_prov m where m.proveedor_id = r.id), '[]'::jsonb));
end;
$$;

-- Pago al proveedor: de la caja (con una forma de pago) o aparte (banco, cheque), sin tocar la caja
create or replace function public.pagar_proveedor(p_proveedor_id bigint, p_monto numeric, p_de_caja boolean, p_forma text, p_concepto text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores; t public.turnos; v_forma text; v_mov bigint;
begin
  perform 1 from public.negocios where id = v_neg for update;
  r := public.requiere_proveedor(p_proveedor_id);
  if coalesce(p_monto, 0) <= 0 then raise exception 'El monto tiene que ser mayor a 0' using errcode = '22023'; end if;
  if coalesce(p_de_caja, false) then
    if not (coalesce(p_forma, '') = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    t := public.requiere_turno(); v_forma := p_forma;
  else
    v_forma := coalesce(nullif(left(btrim(p_forma), 40), ''), 'Aparte');
  end if;
  insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, turno_id, usuario_id)
    values (v_neg, r.id, 'pago', -round(p_monto, 2), coalesce(nullif(left(btrim(p_concepto), 120), ''), 'Pago'), v_forma, coalesce(p_de_caja, false), t.id, v_u)
    returning id into v_mov;
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, cc_prov_id)
      values (v_neg, t.id, v_u, 'egreso', 'Pago a ' || r.nombre, round(p_monto, 2), v_forma, v_mov);
  end if;
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

-- Saldo inicial o corrección: suma (monto > 0) o resta deuda. No mueve plata.
create or replace function public.ajuste_proveedor(p_proveedor_id bigint, p_monto numeric, p_concepto text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores;
begin
  r := public.requiere_proveedor(p_proveedor_id);
  if coalesce(round(p_monto, 2), 0) = 0 then raise exception 'El monto no puede ser 0' using errcode = '22023'; end if;
  insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, usuario_id)
    values (v_neg, r.id, 'ajuste', round(p_monto, 2),
      coalesce(nullif(left(btrim(p_concepto), 120), ''), case when p_monto > 0 then 'Saldo inicial' else 'Ajuste' end), v_u);
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

-- Anular un pago o un ajuste cargado por error: movimiento al revés (si el pago salió de la caja, la plata vuelve)
create or replace function public.anular_mov_proveedor(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); m public.cc_prov; r public.proveedores; t public.turnos; v_mov bigint;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into m from public.cc_prov where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró el movimiento' using errcode = 'P0002'; end if;
  if m.tipo not in ('pago', 'ajuste') or m.compra_id is not null then raise exception 'Ese movimiento es de una compra: anulá la compra' using errcode = 'P0001'; end if;
  if m.anulado then raise exception 'Ese movimiento ya estaba anulado' using errcode = 'P0001'; end if;
  r := public.requiere_proveedor(m.proveedor_id);
  if m.de_caja then t := public.requiere_turno(); end if;
  insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, turno_id, usuario_id, anula_id)
    values (v_neg, r.id, 'anulacion', -m.monto, 'Anulación: ' || m.concepto, m.forma, m.de_caja, t.id, v_u, m.id) returning id into v_mov;
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, cc_prov_id)
      values (v_neg, t.id, v_u, 'ingreso', 'Anulación pago a ' || r.nombre, -m.monto, m.forma, v_mov);
  end if;
  update public.cc_prov set anulado = true where id = m.id;
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

-- ---------------------------------------------------------------------
-- Compras (solo dueño)
-- ---------------------------------------------------------------------
create or replace function public.compra_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'fecha', c.fecha, 'proveedor_id', c.proveedor_id,
    'proveedor', (select p.nombre from public.proveedores p where p.id = c.proveedor_id),
    'comprobante', c.comprobante, 'notas', c.notas, 'total', c.total, 'pagada_caja', c.pagada_caja, 'forma', c.forma,
    'usuario', public.nombre_usuario(c.usuario_id), 'anulada', c.anulada, 'anulada_fecha', c.anulada_fecha,
    'anulada_por', case when c.anulada then public.nombre_usuario(c.anulada_por) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'costo', i.costo, 'precio_nuevo', i.precio_nuevo, 'costo_anterior', i.costo_anterior, 'precio_anterior', i.precio_anterior) order by i.id)
                       from public.compra_items i where i.compra_id = c.id), '[]'::jsonb))
  from public.compras c where c.id = p_id;
$$;

-- p: { proveedor_id?, comprobante, notas, total? (si no, suma de los renglones), pagar_caja, forma,
--      items: [{ producto_id, cantidad, costo, precio_nuevo? }] }
create or replace function public.registrar_compra(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores; t public.turnos;
  c public.compras; it jsonb; x public.productos; v_cant numeric; v_costo numeric; v_precio numeric; v_suma numeric := 0; v_total numeric;
  v_forma text := ''; v_n integer := 0; v_concepto text; v_pago bigint; v_prov bigint := nullif(p ->> 'proveedor_id', '')::bigint;
begin
  perform 1 from public.negocios where id = v_neg for update;
  if v_prov is not null then r := public.requiere_proveedor(v_prov); end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' or jsonb_array_length(p -> 'items') = 0 then
    raise exception 'La compra no tiene productos' using errcode = '22023';
  end if;
  if coalesce((p ->> 'pagar_caja')::boolean, false) then
    v_forma := coalesce(nullif(p ->> 'forma', ''), 'Efectivo');
    if not (v_forma = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    t := public.requiere_turno();
  end if;
  insert into public.compras (negocio_id, proveedor_id, comprobante, notas, total, pagada_caja, forma, usuario_id, turno_id)
    values (v_neg, r.id, left(btrim(coalesce(p ->> 'comprobante', '')), 60), nullif(left(btrim(coalesce(p ->> 'notas', '')), 300), ''), 0,
            t.id is not null, v_forma, v_u, t.id)
    returning * into c;
  v_concepto := 'Compra' || coalesce(' a ' || r.nombre, '') || case when c.comprobante <> '' then ' (' || c.comprobante || ')' else '' end;

  for it in select value from jsonb_array_elements(p -> 'items') loop
    select * into x from public.productos where id = nullif(it ->> 'producto_id', '')::bigint and negocio_id = v_neg for update;
    if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
    v_cant := round(public.num(it, 'cantidad', 'Cantidad de ' || x.nombre), 3);
    if v_cant is null or v_cant <= 0 then raise exception 'Cantidad en 0 en %', x.nombre using errcode = '22023'; end if;
    v_costo := round(coalesce(public.num(it, 'costo', 'Costo de ' || x.nombre), 0), 2);
    if v_costo < 0 then raise exception 'El costo de % no puede ser negativo', x.nombre using errcode = '22023'; end if;
    v_precio := round(public.num(it, 'precio_nuevo', 'Precio de ' || x.nombre), 2);
    if v_precio < 0 then raise exception 'El precio de % no puede ser negativo', x.nombre using errcode = '22023'; end if;
    insert into public.compra_items (negocio_id, compra_id, producto_id, nombre, cantidad, costo, precio_nuevo, costo_anterior, precio_anterior)
      values (v_neg, c.id, x.id, x.nombre, v_cant, v_costo, v_precio, x.costo, x.precio);
    update public.productos set stock = stock + v_cant,
        costo = case when v_costo > 0 then v_costo else costo end,
        precio = coalesce(v_precio, precio),
        proveedor_id = coalesce(proveedor_id, r.id)
      where id = x.id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, x.id, v_cant, v_concepto, v_u);
    if r.id is not null then
      insert into public.producto_proveedores (negocio_id, producto_id, proveedor_id, ultimo_costo, ultima_compra)
        values (v_neg, x.id, r.id, nullif(v_costo, 0), now())
        on conflict (producto_id, proveedor_id) do update set ultimo_costo = coalesce(excluded.ultimo_costo, public.producto_proveedores.ultimo_costo),
          ultima_compra = excluded.ultima_compra;
    end if;
    v_suma := v_suma + round(v_cant * v_costo, 2); v_n := v_n + 1;
  end loop;
  -- el total de la factura puede diferir de la suma (impuestos, redondeos): si viene, vale ese
  v_total := round(coalesce(public.num(p, 'total', 'Total'), v_suma), 2);
  if v_total < 0 then raise exception 'El total no puede ser negativo' using errcode = '22023'; end if;
  update public.compras set total = v_total where id = c.id;

  if t.id is not null and v_total > 0 then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, compra_id)
      values (v_neg, t.id, v_u, 'egreso', v_concepto, v_total, v_forma, c.id);
  end if;
  -- cuenta del proveedor: la compra suma deuda; si se pagó con la caja, el pago la cancela en el momento
  if r.id is not null and v_total > 0 then
    insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
      values (v_neg, r.id, 'compra', v_total, 'Compra' || case when c.comprobante <> '' then ' ' || c.comprobante else '' end, c.id, v_u);
    if t.id is not null then
      insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, compra_id, turno_id, usuario_id)
        values (v_neg, r.id, 'pago', -v_total, 'Pagada con la caja', v_forma, true, c.id, t.id, v_u);
    end if;
  end if;
  return public.compra_json(c.id);
end;
$$;

-- Anular: sale el stock que entró, vuelve a la caja lo que se pagó con ella y se saca de la cuenta del proveedor lo que la
-- compra había dejado (si ya se le había pagado algo aparte, queda a favor). El costo de los productos no cambia.
create or replace function public.anular_compra(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); c public.compras; t public.turnos; i record; v_neto numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into c from public.compras where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Compra no encontrada' using errcode = 'P0002'; end if;
  if c.anulada then raise exception 'La compra ya estaba anulada' using errcode = 'P0001'; end if;
  if c.pagada_caja and c.total > 0 then t := public.requiere_turno(); end if;
  for i in select * from public.compra_items where compra_id = c.id loop
    update public.productos set stock = stock - i.cantidad where id = i.producto_id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, i.producto_id, -i.cantidad, 'Anulación de compra', v_u);
  end loop;
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, compra_id)
      values (v_neg, t.id, v_u, 'ingreso', 'Anulación de compra', c.total, coalesce(nullif(c.forma, ''), 'Efectivo'), c.id);
  end if;
  if c.proveedor_id is not null then
    select coalesce(sum(monto), 0) into v_neto from public.cc_prov where compra_id = c.id;
    if v_neto <> 0 then
      insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
        values (v_neg, c.proveedor_id, 'anulacion', -v_neto, 'Anulación de compra' || case when c.comprobante <> '' then ' ' || c.comprobante else '' end, c.id, v_u);
    end if;
  end if;
  update public.compras set anulada = true, anulada_fecha = now(), anulada_por = v_u where id = c.id;
  return public.compra_json(c.id);
end;
$$;

-- Últimas 300 compras
create or replace function public.compras()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.fecha, 'proveedor', (select p.nombre from public.proveedores p where p.id = c.proveedor_id),
      'comprobante', c.comprobante, 'total', c.total, 'pagada_caja', c.pagada_caja, 'forma', c.forma, 'anulada', c.anulada,
      'items', (select count(*) from public.compra_items i where i.compra_id = c.id)) order by c.id desc)
    from (select * from public.compras where negocio_id = v_neg order by id desc limit 300) c), '[]'::jsonb);
end;
$$;

create or replace function public.compra(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.requiere_admin();
  if not exists (select 1 from public.compras where id = p_id and negocio_id = public.requiere_negocio()) then
    raise exception 'Compra no encontrada' using errcode = 'P0002';
  end if;
  return public.compra_json(p_id);
end;
$$;

-- Proveedores de un producto, con el último costo de cada uno (ficha del producto y carga de compras)
create or replace function public.proveedores_de_producto(p_producto_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('proveedor_id', pp.proveedor_id, 'nombre', pr.nombre, 'ultimo_costo', pp.ultimo_costo,
      'ultima_compra', pp.ultima_compra, 'habitual', pp.proveedor_id = x.proveedor_id) order by pp.ultima_compra desc nulls last)
    from public.producto_proveedores pp join public.proveedores pr on pr.id = pp.proveedor_id join public.productos x on x.id = pp.producto_id
    where pp.producto_id = p_producto_id and pp.negocio_id = v_neg), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.cuit_valido(text), public.saldo_proveedor(bigint), public.requiere_proveedor(bigint), public.proveedor_json(public.proveedores),
  public.proveedores(), public.guardar_proveedor(jsonb), public.eliminar_proveedor(bigint), public.cuenta_proveedor(bigint),
  public.pagar_proveedor(bigint, numeric, boolean, text, text), public.ajuste_proveedor(bigint, numeric, text), public.anular_mov_proveedor(bigint),
  public.compra_json(bigint), public.registrar_compra(jsonb), public.anular_compra(bigint), public.compras(), public.compra(bigint),
  public.proveedores_de_producto(bigint)
  from public, anon, authenticated;
grant execute on function public.proveedores(), public.guardar_proveedor(jsonb), public.eliminar_proveedor(bigint), public.cuenta_proveedor(bigint),
  public.pagar_proveedor(bigint, numeric, boolean, text, text), public.ajuste_proveedor(bigint, numeric, text), public.anular_mov_proveedor(bigint),
  public.registrar_compra(jsonb), public.anular_compra(bigint), public.compras(), public.compra(bigint), public.proveedores_de_producto(bigint)
  to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 9, 'hora', now());
$$;
