-- =====================================================================
-- Etapa 3: productos, categorías, turnos, caja y ventas
--
-- Cada tabla lleva negocio_id. Las referencias entre tablas son compuestas (id, negocio_id): la base no deja
-- apuntar a un registro de otro negocio aunque una función tuviera un error.
-- Todo se lee y escribe por funciones (ninguna tabla se expone a la API).
-- Pendiente para la etapa 4: descuentos y recargos, fiado, balanza, cierre por billetes, devoluciones.
-- =====================================================================

alter table public.usuarios add constraint usuarios_id_negocio unique (id, negocio_id);

create table public.categorias (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 60),
  unique (id, negocio_id)
);
create unique index categorias_nombre_unico on public.categorias (negocio_id, lower(btrim(nombre)));

create table public.productos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 120),
  codigo text check (codigo ~ '^\S{1,40}$'),                 -- código de barras (o interno); null = sin código
  categoria_id bigint,
  costo numeric(14, 2) not null default 0 check (costo >= 0),
  precio numeric(14, 2) not null default 0 check (precio >= 0),
  stock numeric(14, 3) not null default 0,
  stock_min numeric(14, 3) not null default 0 check (stock_min >= 0),
  por_peso boolean not null default false,                  -- se vende por kilo (cantidad con decimales)
  plu text check (plu ~ '^\d{1,6}$'),                       -- código de balanza
  favorito boolean not null default false,
  activo boolean not null default true,                     -- false = dado de baja (ya tenía ventas)
  creado timestamptz not null default now(),
  actualizado timestamptz not null default now(),           -- el catálogo del navegador se actualiza con esto
  unique (id, negocio_id),
  foreign key (categoria_id, negocio_id) references public.categorias (id, negocio_id)
);
create unique index productos_codigo_unico on public.productos (negocio_id, lower(codigo)) where codigo is not null;
create unique index productos_plu_unico on public.productos (negocio_id, plu) where plu is not null;
create index productos_actualizado on public.productos (negocio_id, actualizado);

create or replace function public.tocar_actualizado()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.actualizado := now();
  return new;
end;
$$;
create trigger productos_actualizado before update on public.productos for each row execute function public.tocar_actualizado();

create table public.movimientos_stock (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  producto_id bigint not null,
  fecha timestamptz not null default now(),
  cantidad numeric(14, 3) not null,
  motivo text not null default '',
  usuario_id bigint,
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete cascade,
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index movimientos_stock_producto on public.movimientos_stock (producto_id);

create table public.turnos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  usuario_id bigint not null,
  apertura timestamptz not null default now(),
  cierre timestamptz,
  inicial numeric(14, 2) not null default 0 check (inicial >= 0),
  esperado numeric(14, 2),
  contado numeric(14, 2),
  diferencia numeric(14, 2),
  retiro numeric(14, 2),
  notas text,
  cerrado_por bigint,
  unique (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (cerrado_por, negocio_id) references public.usuarios (id, negocio_id)
);
create unique index turnos_uno_abierto on public.turnos (negocio_id) where cierre is null;

create table public.ventas (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  numero integer not null,
  clave uuid not null,                                      -- la manda la pantalla: con la misma clave no se registra dos veces
  fecha timestamptz not null default now(),
  usuario_id bigint not null,
  turno_id bigint not null,
  subtotal numeric(14, 2) not null,
  total numeric(14, 2) not null,
  paga_con numeric(14, 2),
  anulada boolean not null default false,
  anulada_fecha timestamptz,
  anulada_por bigint,
  motivo_anulacion text,
  unique (id, negocio_id),
  unique (negocio_id, numero),
  unique (negocio_id, clave),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id),
  foreign key (anulada_por, negocio_id) references public.usuarios (id, negocio_id)
);
create index ventas_fecha on public.ventas (negocio_id, fecha);
create index ventas_turno on public.ventas (turno_id);

create table public.venta_items (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  venta_id bigint not null,
  producto_id bigint,                                       -- null = "Varios"
  nombre text not null,
  cantidad numeric(14, 3) not null check (cantidad > 0),
  precio numeric(14, 2) not null,
  importe numeric(14, 2) not null,
  costo numeric(14, 2) not null default 0,
  por_peso boolean not null default false,
  categoria_id bigint,
  precio_lista numeric(14, 2),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id) on delete cascade,
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id)
);
create index venta_items_venta on public.venta_items (venta_id);
create index venta_items_producto on public.venta_items (producto_id);

create table public.venta_pagos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  venta_id bigint not null,
  forma text not null,
  monto numeric(14, 2) not null check (monto > 0),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id) on delete cascade
);
create index venta_pagos_venta on public.venta_pagos (venta_id);

create table public.caja (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  turno_id bigint not null,
  usuario_id bigint not null,
  fecha timestamptz not null default now(),
  tipo text not null check (tipo in ('ingreso', 'egreso')),
  concepto text not null,
  monto numeric(14, 2) not null check (monto > 0),
  forma text not null,
  venta_id bigint,
  manual boolean not null default false,                   -- cargado a mano en Caja (no por una venta)
  foreign key (turno_id, negocio_id) references public.turnos (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (venta_id, negocio_id) references public.ventas (id, negocio_id)
);
create index caja_turno on public.caja (turno_id);

alter table public.categorias enable row level security;
alter table public.productos enable row level security;
alter table public.movimientos_stock enable row level security;
alter table public.turnos enable row level security;
alter table public.ventas enable row level security;
alter table public.venta_items enable row level security;
alter table public.venta_pagos enable row level security;
alter table public.caja enable row level security;
revoke all on public.categorias, public.productos, public.movimientos_stock, public.turnos, public.ventas,
  public.venta_items, public.venta_pagos, public.caja from anon, authenticated;

-- ---------------------------------------------------------------------
-- Ayudas internas
-- ---------------------------------------------------------------------

-- Formas de pago del negocio (Ajustes); por defecto, las de la app local
create or replace function public.formas_pago(p_neg uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select array(select jsonb_array_elements_text(c.valor)) from public.config c
      where c.negocio_id = p_neg and c.clave = 'formas_pago' and jsonb_typeof(c.valor) = 'array'),
    array['Efectivo', 'Débito', 'Crédito', 'Transferencia', 'Mercado Pago']);
$$;

create or replace function public.nombre_usuario(p_id bigint)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select nombre from public.usuarios where id = p_id), '—');
$$;

-- Turno abierto del negocio; corta si no hay o si es de otro usuario (el dueño puede usar cualquiera)
create or replace function public.requiere_turno()
returns public.turnos language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos;
begin
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then raise exception 'La caja está cerrada: abrí tu turno en Caja' using errcode = 'P0001'; end if;
  if t.usuario_id <> v_u and not public.es_admin() then
    raise exception 'El turno abierto es de %: tiene que cerrarlo antes de que abras el tuyo', public.nombre_usuario(t.usuario_id) using errcode = 'P0001';
  end if;
  return t;
end;
$$;

create or replace function public.efectivo_esperado(p_turno bigint)
returns numeric language sql stable security definer set search_path = '' as $$
  select t.inicial + coalesce((select sum(case when c.tipo = 'ingreso' then c.monto else -c.monto end)
                               from public.caja c where c.turno_id = t.id and c.forma = 'Efectivo'), 0)
  from public.turnos t where t.id = p_turno;
$$;

-- Producto para la pantalla; el costo solo para el dueño
create or replace function public.producto_json(p public.productos, p_costo boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'codigo', p.codigo, 'categoria_id', p.categoria_id,
    'precio', p.precio, 'stock', p.stock, 'stock_min', p.stock_min, 'por_peso', p.por_peso, 'plu', p.plu,
    'favorito', p.favorito, 'activo', p.activo, 'actualizado', p.actualizado)
    || case when p_costo then jsonb_build_object('costo', p.costo) else '{}'::jsonb end;
$$;

-- Venta completa para la pantalla (sin costos)
create or replace function public.venta_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'usuario', public.nombre_usuario(v.usuario_id),
    'turno_id', v.turno_id, 'subtotal', v.subtotal, 'total', v.total, 'paga_con', v.paga_con,
    'anulada', v.anulada, 'anulada_fecha', v.anulada_fecha, 'anulada_por', case when v.anulada then public.nombre_usuario(v.anulada_por) end,
    'motivo_anulacion', v.motivo_anulacion,
    'items', coalesce((select jsonb_agg(jsonb_build_object('producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'precio', i.precio, 'importe', i.importe, 'por_peso', i.por_peso) order by i.id)
                       from public.venta_items i where i.venta_id = v.id), '[]'::jsonb),
    'pagos', coalesce((select jsonb_agg(jsonb_build_object('forma', p.forma, 'monto', p.monto) order by p.id)
                       from public.venta_pagos p where p.venta_id = v.id), '[]'::jsonb))
  from public.ventas v where v.id = p_id;
$$;

-- Un número de la pantalla: vacío = null; con coma decimal también
create or replace function public.num(p jsonb, p_campo text, p_que text)
returns numeric language plpgsql immutable set search_path = '' as $$
declare v text := btrim(coalesce(p ->> p_campo, ''));
begin
  if v = '' then return null; end if;
  return replace(v, ',', '.')::numeric;
exception when others then
  raise exception '%: valor inválido', p_que using errcode = '22023';
end;
$$;

-- ---------------------------------------------------------------------
-- Catálogo y productos
-- ---------------------------------------------------------------------

-- Productos y categorías para el navegador. Con p_desde, solo lo que cambió desde entonces (también los dados de baja,
-- para sacarlos). 'ahora' es lo que hay que mandar la próxima vez (la pantalla le resta un margen por las dudas).
create or replace function public.catalogo(p_desde timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_admin boolean;
begin
  perform public.requiere_usuario();
  v_admin := public.es_admin();
  return jsonb_build_object(
    'ahora', now(),
    'completo', p_desde is null,
    'categorias', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre) order by lower(c.nombre))
                            from public.categorias c where c.negocio_id = v_neg), '[]'::jsonb),
    'productos', coalesce((select jsonb_agg(public.producto_json(p, v_admin) order by p.id)
                           from public.productos p
                           where p.negocio_id = v_neg and (p_desde is null and p.activo or p.actualizado >= p_desde)), '[]'::jsonb));
end;
$$;

-- Crear o editar un producto (solo dueño). p: { id?, nombre, codigo, categoria_id, costo, precio, stock, stock_min,
-- por_peso, plu, favorito }. El stock, si viene y cambió, queda como movimiento.
create or replace function public.guardar_producto(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin();
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_nombre text := btrim(coalesce(p ->> 'nombre', ''));
  v_codigo text := nullif(btrim(coalesce(p ->> 'codigo', '')), '');
  v_plu text := nullif(btrim(coalesce(p ->> 'plu', '')), '');
  v_cat bigint := nullif(p ->> 'categoria_id', '')::bigint;
  v_stock numeric := round(public.num(p, 'stock', 'Stock'), 3);
  v_otro text; v_actual public.productos; r public.productos;
begin
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if v_codigo is not null and v_codigo ~ '\s' then raise exception 'El código no puede tener espacios' using errcode = '22023'; end if;
  if v_plu is not null and v_plu !~ '^\d{1,6}$' then raise exception 'El código de balanza tiene que ser de 1 a 6 números' using errcode = '22023'; end if;
  if v_cat is not null and not exists (select 1 from public.categorias where id = v_cat and negocio_id = v_neg) then
    raise exception 'Categoría no encontrada' using errcode = 'P0002';
  end if;
  if v_codigo is not null then
    select nombre into v_otro from public.productos where negocio_id = v_neg and lower(codigo) = lower(v_codigo) and id is distinct from v_id;
    if v_otro is not null then raise exception 'El código % ya lo tiene "%"', v_codigo, v_otro using errcode = '23505'; end if;
  end if;
  if v_plu is not null and exists (select 1 from public.productos where negocio_id = v_neg and plu = v_plu and id is distinct from v_id) then
    raise exception 'El código de balanza % ya está usado', v_plu using errcode = '23505';
  end if;

  if v_id is null then
    insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, stock, stock_min, por_peso, plu, favorito)
    values (v_neg, v_nombre, v_codigo, v_cat,
      coalesce(round(public.num(p, 'costo', 'Costo'), 2), 0), coalesce(round(public.num(p, 'precio', 'Precio'), 2), 0),
      coalesce(v_stock, 0), coalesce(round(public.num(p, 'stock_min', 'Stock mínimo'), 3), 0),
      coalesce((p ->> 'por_peso')::boolean, false), v_plu, coalesce((p ->> 'favorito')::boolean, false))
    returning * into r;
    if coalesce(v_stock, 0) <> 0 then
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, r.id, v_stock, 'Stock inicial', v_u);
    end if;
  else
    select * into v_actual from public.productos where id = v_id and negocio_id = v_neg for update;
    if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
    update public.productos set nombre = v_nombre, codigo = v_codigo, categoria_id = v_cat,
        costo = coalesce(round(public.num(p, 'costo', 'Costo'), 2), costo), precio = coalesce(round(public.num(p, 'precio', 'Precio'), 2), precio),
        stock = coalesce(v_stock, stock), stock_min = coalesce(round(public.num(p, 'stock_min', 'Stock mínimo'), 3), stock_min),
        por_peso = coalesce((p ->> 'por_peso')::boolean, por_peso), plu = v_plu,
        favorito = coalesce((p ->> 'favorito')::boolean, favorito), activo = coalesce((p ->> 'activo')::boolean, activo)
      where id = v_id returning * into r;
    if v_stock is not null and v_stock <> v_actual.stock then
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
        values (v_neg, r.id, v_stock - v_actual.stock, 'Corrección desde la ficha', v_u);
    end if;
  end if;
  return public.producto_json(r, true);
end;
$$;

create or replace function public.ajustar_stock(p_producto_id bigint, p_nuevo numeric, p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.productos; v_delta numeric;
begin
  if p_nuevo is null then raise exception 'Falta el stock nuevo' using errcode = '22023'; end if;
  select * into r from public.productos where id = p_producto_id and negocio_id = v_neg for update;
  if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
  v_delta := round(p_nuevo, 3) - r.stock;
  if v_delta <> 0 then
    update public.productos set stock = round(p_nuevo, 3) where id = r.id returning * into r;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
      values (v_neg, r.id, v_delta, coalesce(nullif(left(btrim(p_motivo), 120), ''), 'Ajuste'), v_u);
  end if;
  return public.producto_json(r, true);
end;
$$;

-- Si ya se vendió, se da de baja (no se borra, para no perder el historial); si no, se borra
create or replace function public.eliminar_producto(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if not exists (select 1 from public.productos where id = p_id and negocio_id = v_neg) then
    raise exception 'Producto no encontrado' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.venta_items where producto_id = p_id) then
    update public.productos set activo = false where id = p_id;
    return jsonb_build_object('desactivado', true);
  end if;
  delete from public.productos where id = p_id;
  return jsonb_build_object('eliminado', true);
end;
$$;

create or replace function public.guardar_categoria(p_id bigint, p_nombre text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_nombre text := btrim(coalesce(p_nombre, '')); r public.categorias;
begin
  perform public.requiere_admin();
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if exists (select 1 from public.categorias where negocio_id = v_neg and lower(btrim(nombre)) = lower(v_nombre) and id is distinct from p_id) then
    raise exception 'Ya existe esa categoría' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.categorias (negocio_id, nombre) values (v_neg, v_nombre) returning * into r;
  else
    update public.categorias set nombre = v_nombre where id = p_id and negocio_id = v_neg returning * into r;
    if not found then raise exception 'Categoría no encontrada' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'nombre', r.nombre);
end;
$$;

create or replace function public.eliminar_categoria(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_n integer;
begin
  perform public.requiere_admin();
  select count(*) into v_n from public.productos where categoria_id = p_id and negocio_id = v_neg;
  if v_n > 0 then raise exception 'No se puede: tiene % producto(s). Pasalos a otra categoría primero.', v_n using errcode = '23503'; end if;
  delete from public.categorias where id = p_id and negocio_id = v_neg;
end;
$$;

-- ---------------------------------------------------------------------
-- Turnos y caja
-- ---------------------------------------------------------------------

-- Estado de la caja: el turno abierto (si hay), cuánto efectivo debería haber, totales por forma de pago,
-- movimientos y ventas del turno. Lo ven todos los usuarios (el empleado cierra su turno).
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
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.fecha, 'tipo', c.tipo, 'concepto', c.concepto,
        'monto', c.monto, 'forma', c.forma, 'venta_id', c.venta_id, 'manual', c.manual, 'usuario', public.nombre_usuario(c.usuario_id)) order by c.id desc)
      from public.caja c where c.turno_id = t.id), '[]'::jsonb),
    'ventas', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'total', v.total,
        'anulada', v.anulada, 'usuario', public.nombre_usuario(v.usuario_id),
        'resumen', (select string_agg(i.nombre, ', ' order by i.id) from public.venta_items i where i.venta_id = v.id)) order by v.id desc)
      from public.ventas v where v.turno_id = t.id), '[]'::jsonb));
end;
$$;

create or replace function public.abrir_turno(p_inicial numeric default 0)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if found then raise exception 'Ya hay un turno abierto (%)', public.nombre_usuario(t.usuario_id) using errcode = 'P0001'; end if;
  if coalesce(p_inicial, 0) < 0 then raise exception 'El efectivo inicial no puede ser negativo' using errcode = '22023'; end if;
  insert into public.turnos (negocio_id, usuario_id, inicial) values (v_neg, v_u, round(coalesce(p_inicial, 0), 2));
  return public.estado_caja();
end;
$$;

-- Cerrar el turno: lo cierra quien lo abrió o el dueño. Devuelve el resumen del cierre.
create or replace function public.cerrar_turno(p_contado numeric, p_retiro numeric default 0, p_notas text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v_esperado numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then raise exception 'No hay ningún turno abierto' using errcode = 'P0001'; end if;
  if t.usuario_id <> v_u and not public.es_admin() then
    raise exception 'Solo quien abrió el turno (o el dueño) puede cerrarlo' using errcode = '42501';
  end if;
  if p_contado is null or p_contado < 0 then raise exception 'Poné el efectivo contado' using errcode = '22023'; end if;
  if coalesce(p_retiro, 0) < 0 or coalesce(p_retiro, 0) > p_contado then
    raise exception 'El retiro no puede ser mayor a lo contado' using errcode = '22023';
  end if;
  v_esperado := public.efectivo_esperado(t.id);
  update public.turnos set cierre = now(), esperado = v_esperado, contado = round(p_contado, 2), diferencia = round(p_contado, 2) - v_esperado,
      retiro = round(coalesce(p_retiro, 0), 2), notas = nullif(left(btrim(coalesce(p_notas, '')), 500), ''), cerrado_por = v_u
    where id = t.id returning * into t;
  return jsonb_build_object('id', t.id, 'apertura', t.apertura, 'cierre', t.cierre, 'inicial', t.inicial, 'esperado', t.esperado,
    'contado', t.contado, 'diferencia', t.diferencia, 'retiro', t.retiro);
end;
$$;

-- Ingreso o egreso de plata cargado a mano (con motivo)
create or replace function public.movimiento_caja(p_tipo text, p_concepto text, p_monto numeric, p_forma text default 'Efectivo')
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos;
begin
  perform 1 from public.negocios where id = v_neg for update;
  t := public.requiere_turno();
  if p_tipo not in ('ingreso', 'egreso') then raise exception 'Tipo inválido' using errcode = '22023'; end if;
  if coalesce(btrim(p_concepto), '') = '' then raise exception 'Escribí el motivo' using errcode = '22023'; end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'El monto tiene que ser mayor a 0' using errcode = '22023'; end if;
  if not (p_forma = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
  insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, manual)
    values (v_neg, t.id, v_u, p_tipo, left(btrim(p_concepto), 120), round(p_monto, 2), p_forma, true);
  return public.estado_caja();
end;
$$;

-- ---------------------------------------------------------------------
-- Ventas
-- ---------------------------------------------------------------------

-- Registrar una venta. p_clave la genera la pantalla por cada venta: si se corta la conexión y se reintenta con la misma
-- clave, devuelve la venta que ya estaba (no la registra dos veces).
-- p_items: [{ producto_id, cantidad }] o [{ nombre, importe }] para "Varios". El precio sale del producto (no de la pantalla).
-- p_pagos: [{ forma, monto }], tienen que sumar el total.
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_importe numeric; v_monto numeric;
  v_sub numeric := 0; v_pagado numeric := 0; v_pid bigint;
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
  t := public.requiere_turno();

  insert into public.ventas (negocio_id, numero, clave, usuario_id, turno_id, subtotal, total)
    values (v_neg, coalesce((select max(numero) from public.ventas where negocio_id = v_neg), 0) + 1, p_clave, v_u, t.id, 0, 0)
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
    if not (coalesce(pg ->> 'forma', '') = any (v_formas)) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    insert into public.venta_pagos (negocio_id, venta_id, forma, monto) values (v_neg, v.id, pg ->> 'forma', v_monto);
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
      values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_monto, pg ->> 'forma', v.id);
    v_pagado := v_pagado + v_monto;
  end loop;
  if abs(v_pagado - v_sub) > 0.005 then
    raise exception 'Los pagos (%) no suman el total (%)', v_pagado, v_sub using errcode = '22023';
  end if;

  update public.ventas set subtotal = v_sub, total = v_sub,
      paga_con = case when p_paga_con >= v_sub then round(p_paga_con, 2) end
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

create or replace function public.venta(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_usuario();
  if not exists (select 1 from public.ventas where id = p_id and negocio_id = v_neg) then
    raise exception 'Venta no encontrada' using errcode = 'P0002';
  end if;
  return public.venta_json(p_id);
end;
$$;

-- Anular una venta (solo dueño): vuelve el stock y sale la plata de la caja del turno abierto
create or replace function public.anular_venta(p_id bigint, p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v public.ventas; t public.turnos; i record; pg record;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into v from public.ventas where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Venta no encontrada' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'La venta ya estaba anulada' using errcode = 'P0001'; end if;
  t := public.requiere_turno();
  for i in select * from public.venta_items where venta_id = v.id and producto_id is not null loop
    update public.productos set stock = stock + i.cantidad where id = i.producto_id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
      values (v_neg, i.producto_id, i.cantidad, 'Anulación venta #' || v.numero, v_u);
  end loop;
  for pg in select * from public.venta_pagos where venta_id = v.id loop
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
      values (v_neg, t.id, v_u, 'egreso', 'Anulación venta #' || v.numero, pg.monto, pg.forma, v.id);
  end loop;
  update public.ventas set anulada = true, anulada_fecha = now(), anulada_por = v_u,
      motivo_anulacion = nullif(left(btrim(coalesce(p_motivo, '')), 200), '')
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.tocar_actualizado(), public.formas_pago(uuid), public.nombre_usuario(bigint), public.requiere_turno(),
  public.efectivo_esperado(bigint), public.producto_json(public.productos, boolean), public.venta_json(bigint), public.num(jsonb, text, text),
  public.catalogo(timestamptz), public.guardar_producto(jsonb), public.ajustar_stock(bigint, numeric, text), public.eliminar_producto(bigint),
  public.guardar_categoria(bigint, text), public.eliminar_categoria(bigint), public.estado_caja(), public.abrir_turno(numeric),
  public.cerrar_turno(numeric, numeric, text), public.movimiento_caja(text, text, numeric, text),
  public.registrar_venta(uuid, jsonb, jsonb, numeric), public.venta(bigint), public.anular_venta(bigint, text)
  from public, anon, authenticated;

grant execute on function public.catalogo(timestamptz), public.guardar_producto(jsonb), public.ajustar_stock(bigint, numeric, text),
  public.eliminar_producto(bigint), public.guardar_categoria(bigint, text), public.eliminar_categoria(bigint), public.estado_caja(),
  public.abrir_turno(numeric), public.cerrar_turno(numeric, numeric, text), public.movimiento_caja(text, text, numeric, text),
  public.registrar_venta(uuid, jsonb, jsonb, numeric), public.venta(bigint), public.anular_venta(bigint, text)
  to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 3, 'hora', now());
$$;
