-- =====================================================================
-- Etapa 6: entradas y salidas de mercadería (solo dueño)
-- Suman o restan stock sin pasar por una compra ni una venta: vencidos, rotos, consumo propio, transferencias,
-- diferencias de inventario… Cada una queda numerada por negocio y tipo (RI-0001 entradas, RE-0001 salidas), con su
-- motivo, quién la hizo y el stock antes y después de cada producto. Se anulan con el movimiento al revés.
-- Los motivos son una lista editable en Ajustes (config 'motivos_remito'). Las devoluciones se hacen desde la venta o la compra.
-- =====================================================================

create table public.remitos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  tipo text not null check (tipo in ('ingreso', 'egreso')),
  numero integer not null,
  fecha timestamptz not null default now(),
  motivo text not null,
  notas text,
  usuario_id bigint not null,
  anulado boolean not null default false,
  anulado_fecha timestamptz,
  anulado_por bigint,
  unique (id, negocio_id),
  unique (negocio_id, tipo, numero),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (anulado_por, negocio_id) references public.usuarios (id, negocio_id)
);

create table public.remito_items (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  remito_id bigint not null,
  producto_id bigint,
  nombre text not null,
  cantidad numeric(14, 3) not null check (cantidad > 0),
  costo numeric(14, 2) not null default 0,
  stock_antes numeric(14, 3) not null,
  stock_despues numeric(14, 3) not null,
  foreign key (remito_id, negocio_id) references public.remitos (id, negocio_id) on delete cascade,
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete set null (producto_id)
);
create index remito_items_remito on public.remito_items (remito_id);

alter table public.remitos enable row level security;
alter table public.remito_items enable row level security;
revoke all on public.remitos, public.remito_items from anon, authenticated;

create or replace function public.etiqueta_remito(p_tipo text, p_numero integer)
returns text language sql immutable set search_path = '' as $$
  select case when p_tipo = 'ingreso' then 'RI-' else 'RE-' end || lpad(p_numero::text, 4, '0');
$$;

-- Motivos de cada tipo (los de fábrica, si el negocio no los cambió)
create or replace function public.motivos_remito(p_neg uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select c.valor from public.config c where c.negocio_id = p_neg and c.clave = 'motivos_remito' and jsonb_typeof(c.valor) = 'object'),
    jsonb_build_object(
      'ingreso', jsonb_build_array('Transferencia desde otro local', 'Ajuste de inventario (sobrante)', 'Otro'),
      'egreso', jsonb_build_array('Vencido', 'Roto / dañado', 'Consumo propio', 'Robo / faltante', 'Transferencia a otro local',
                                  'Muestra / regalo', 'Ajuste de inventario (faltante)', 'Otro')));
$$;

create or replace function public.motivos_remito()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return public.motivos_remito(v_neg);
end;
$$;

-- p: { ingreso: [texto], egreso: [texto] }. Sin repetidos ni vacíos, hasta 30 de hasta 120 letras.
create or replace function public.guardar_motivos_remito(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v jsonb := '{}'::jsonb; t text; v_lista jsonb;
begin
  perform public.requiere_admin();
  foreach t in array array['ingreso', 'egreso'] loop
    select coalesce(jsonb_agg(m order by o), '[]'::jsonb) into v_lista from (
      select m, min(o) as o from (
        select left(btrim(x), 120) as m, o from jsonb_array_elements_text(
          case when jsonb_typeof(p -> t) = 'array' then p -> t else '[]'::jsonb end) with ordinality as e(x, o)
      ) a where m <> '' group by m) b;
    if jsonb_array_length(v_lista) = 0 then
      raise exception 'Cargá al menos un motivo de %', case when t = 'ingreso' then 'entrada' else 'salida' end using errcode = '22023';
    end if;
    if jsonb_array_length(v_lista) > 30 then raise exception 'Demasiados motivos' using errcode = '22023'; end if;
    v := v || jsonb_build_object(t, v_lista);
  end loop;
  insert into public.config (negocio_id, clave, valor) values (v_neg, 'motivos_remito', v)
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
  return v;
end;
$$;

create or replace function public.remito_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', r.id, 'tipo', r.tipo, 'numero', r.numero, 'etiqueta', public.etiqueta_remito(r.tipo, r.numero),
    'fecha', r.fecha, 'motivo', r.motivo, 'notas', r.notas, 'usuario', public.nombre_usuario(r.usuario_id),
    'anulado', r.anulado, 'anulado_fecha', r.anulado_fecha, 'anulado_por', public.nombre_usuario(r.anulado_por),
    'items', coalesce((select jsonb_agg(jsonb_build_object('producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'costo', i.costo, 'stock_antes', i.stock_antes, 'stock_despues', i.stock_despues) order by i.id)
                       from public.remito_items i where i.remito_id = r.id), '[]'::jsonb),
    'valor', (select coalesce(sum(round(i.cantidad * i.costo, 2)), 0) from public.remito_items i where i.remito_id = r.id))
  from public.remitos r where r.id = p_id;
$$;

-- p: { tipo: 'ingreso' | 'egreso', motivo, notas, items: [{producto_id, cantidad}] }. El mismo producto dos veces se suma.
-- Devuelve la entrada o salida, con stock_negativo: los productos que quedaron con stock menor a cero.
create or replace function public.registrar_remito(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin();
  v_tipo text := coalesce(p ->> 'tipo', ''); v_motivo text := left(btrim(coalesce(p ->> 'motivo', '')), 120);
  v_id bigint; v_num integer; v_etq text; x record; pr public.productos; v_delta numeric; v_n integer := 0;
begin
  if v_tipo not in ('ingreso', 'egreso') then raise exception 'Tiene que ser una entrada o una salida' using errcode = '22023'; end if;
  if v_motivo = '' then raise exception 'Elegí el motivo' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' or jsonb_array_length(p -> 'items') = 0 then
    raise exception 'No cargaste ningún producto' using errcode = '22023';
  end if;
  if jsonb_array_length(p -> 'items') > 500 then raise exception 'Demasiados productos' using errcode = '22023'; end if;
  perform 1 from public.negocios where id = v_neg for update;   -- numeración sin saltos ni repetidos
  v_num := coalesce((select max(numero) from public.remitos where negocio_id = v_neg and tipo = v_tipo), 0) + 1;
  v_etq := public.etiqueta_remito(v_tipo, v_num);
  insert into public.remitos (negocio_id, tipo, numero, motivo, notas, usuario_id)
    values (v_neg, v_tipo, v_num, v_motivo, nullif(left(btrim(coalesce(p ->> 'notas', '')), 300), ''), v_u) returning id into v_id;
  -- se suman los repetidos y se recorren por id (siempre en el mismo orden, para no trabarse con otra operación)
  for x in
    select nullif(e ->> 'producto_id', '')::bigint as producto_id, sum(round(public.num(e, 'cantidad', 'Cantidad'), 3)) as cantidad
    from jsonb_array_elements(p -> 'items') e group by 1 order by 1
  loop
    select * into pr from public.productos where id = x.producto_id and negocio_id = v_neg for update;
    if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
    if x.cantidad is null or x.cantidad <= 0 then raise exception 'Cantidad en 0 en %', pr.nombre using errcode = '22023'; end if;
    v_delta := case when v_tipo = 'ingreso' then x.cantidad else -x.cantidad end;
    insert into public.remito_items (negocio_id, remito_id, producto_id, nombre, cantidad, costo, stock_antes, stock_despues)
      values (v_neg, v_id, pr.id, pr.nombre, x.cantidad, coalesce(pr.costo, 0), pr.stock, pr.stock + v_delta);
    update public.productos set stock = stock + v_delta where id = pr.id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
      values (v_neg, pr.id, v_delta, left((case when v_tipo = 'ingreso' then 'Entrada ' else 'Salida ' end) || v_etq || ' — ' || v_motivo, 160), v_u);
    v_n := v_n + 1;
  end loop;
  return public.remito_json(v_id) || jsonb_build_object('stock_negativo',
    (select coalesce(jsonb_agg(i.nombre order by i.id), '[]'::jsonb) from public.remito_items i where i.remito_id = v_id and i.stock_despues < 0));
end;
$$;

-- Anular: el movimiento al revés (lo que entró sale, lo que salió vuelve). Los productos borrados se saltean.
create or replace function public.anular_remito(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.remitos; i record; v_etq text;
begin
  select * into r from public.remitos where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró la entrada o salida' using errcode = 'P0002'; end if;
  if r.anulado then raise exception 'Ya estaba anulada' using errcode = 'P0001'; end if;
  v_etq := public.etiqueta_remito(r.tipo, r.numero);
  for i in select producto_id, sum(cantidad) as cantidad from public.remito_items
           where remito_id = r.id and producto_id is not null group by producto_id order by producto_id loop
    update public.productos set stock = stock + case when r.tipo = 'ingreso' then -i.cantidad else i.cantidad end
      where id = i.producto_id and negocio_id = v_neg;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
      values (v_neg, i.producto_id, case when r.tipo = 'ingreso' then -i.cantidad else i.cantidad end,
              'Anulación de la ' || case when r.tipo = 'ingreso' then 'entrada ' else 'salida ' end || v_etq, v_u);
  end loop;
  update public.remitos set anulado = true, anulado_fecha = now(), anulado_por = v_u where id = r.id;
  return public.remito_json(r.id);
end;
$$;

-- Lista (las últimas 300), con cuántos productos y el valor al costo. p_tipo: 'ingreso', 'egreso' o null (todas)
create or replace function public.remitos(p_tipo text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'tipo', r.tipo, 'numero', r.numero, 'etiqueta', public.etiqueta_remito(r.tipo, r.numero),
      'fecha', r.fecha, 'motivo', r.motivo, 'notas', r.notas, 'usuario', public.nombre_usuario(r.usuario_id), 'anulado', r.anulado,
      'items', (select count(*) from public.remito_items i where i.remito_id = r.id),
      'valor', (select coalesce(sum(round(i.cantidad * i.costo, 2)), 0) from public.remito_items i where i.remito_id = r.id)) order by r.id desc)
    from (select * from public.remitos where negocio_id = v_neg and (coalesce(p_tipo, '') = '' or tipo = p_tipo) order by id desc limit 300) r), '[]'::jsonb);
end;
$$;

create or replace function public.remito(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if not exists (select 1 from public.remitos where id = p_id and negocio_id = v_neg) then
    raise exception 'No se encontró la entrada o salida' using errcode = 'P0002';
  end if;
  return public.remito_json(p_id);
end;
$$;

revoke all on function public.etiqueta_remito(text, integer), public.motivos_remito(uuid), public.motivos_remito(), public.guardar_motivos_remito(jsonb),
  public.remito_json(bigint), public.registrar_remito(jsonb), public.anular_remito(bigint), public.remitos(text), public.remito(bigint)
  from public, anon, authenticated;
grant execute on function public.motivos_remito(), public.guardar_motivos_remito(jsonb), public.registrar_remito(jsonb),
  public.anular_remito(bigint), public.remitos(text), public.remito(bigint) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 12, 'hora', now());
$$;
