-- =====================================================================
-- Etapa 7: aumentos masivos de precios (solo dueño), con deshacer
-- A los productos que se ven en la lista, a una categoría, a un proveedor o a todos: un % o un monto fijo, al precio y
-- (si se elige) también al costo, con redondeo hacia arriba a múltiplos de lo que diga Ajustes (config 'redondeo', 10 de fábrica).
-- Cada aumento guarda el antes y el después de cada producto. Deshacer vuelve al antes, salvo los productos que se
-- cambiaron después (no se pisan).
-- =====================================================================

create table public.aumentos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  fecha timestamptz not null default now(),
  usuario_id bigint not null,
  descripcion text not null,
  deshecho boolean not null default false,
  deshecho_fecha timestamptz,
  deshecho_por bigint,
  unique (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id),
  foreign key (deshecho_por, negocio_id) references public.usuarios (id, negocio_id)
);
create index aumentos_negocio on public.aumentos (negocio_id, id);

create table public.aumento_cambios (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  aumento_id bigint not null,
  producto_id bigint not null,
  precio_antes numeric(14, 2) not null,
  costo_antes numeric(14, 2) not null,
  precio_despues numeric(14, 2) not null,
  costo_despues numeric(14, 2) not null,
  foreign key (aumento_id, negocio_id) references public.aumentos (id, negocio_id) on delete cascade,
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete cascade
);
create index aumento_cambios_aumento on public.aumento_cambios (aumento_id);

alter table public.aumentos enable row level security;
alter table public.aumento_cambios enable row level security;
revoke all on public.aumentos, public.aumento_cambios from anon, authenticated;

-- Múltiplo al que se redondean los precios hacia arriba (0 = sin redondeo)
create or replace function public.redondeo_precios(p_neg uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select case when jsonb_typeof(c.valor) = 'number' and (c.valor #>> '{}')::numeric between 0 and 100000
                               then (c.valor #>> '{}')::numeric end
                   from public.config c where c.negocio_id = p_neg and c.clave = 'redondeo'), 10);
$$;

create or replace function public.redondear_precio(p_valor numeric, p_multiplo numeric)
returns numeric language sql immutable set search_path = '' as $$
  select case when coalesce(p_multiplo, 0) > 0 then ceil(round(p_valor, 2) / p_multiplo) * p_multiplo else round(p_valor, 2) end;
$$;

-- Un precio o costo con el aumento (y el redondeo hacia arriba); nunca menos de cero
create or replace function public.valor_aumentado(p_x numeric, p_modo text, p_valor numeric, p_multiplo numeric)
returns numeric language sql immutable set search_path = '' as $$
  select greatest(0, public.redondear_precio(case when p_modo = 'pct' then p_x * (1 + p_valor / 100) else p_x + p_valor end, p_multiplo));
$$;

-- p: { alcance: 'ids' | 'categoria' | 'proveedor' | 'todos', ids: [id], categoria_id, proveedor_id,
--      modo: 'pct' | 'monto', valor, costo: bool (también el costo), redondear: bool, descripcion }
--      simular: true → solo { cantidad, ejemplos } sin cambiar nada
-- Solo productos activos. Ningún precio ni costo baja de cero. Devuelve { id, cantidad }.
create or replace function public.aumento_masivo(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin();
  v_alcance text := coalesce(p ->> 'alcance', ''); v_modo text := coalesce(p ->> 'modo', '');
  v_valor numeric := public.num(p, 'valor', 'Aumento'); v_costo boolean := coalesce((p ->> 'costo')::boolean, false);
  v_mult numeric := case when coalesce((p ->> 'redondear')::boolean, false) then public.redondeo_precios(v_neg) else 0 end;
  v_cat bigint := nullif(p ->> 'categoria_id', '')::bigint; v_prov bigint := nullif(p ->> 'proveedor_id', '')::bigint;
  v_ids bigint[]; v_sel bigint[]; v_id bigint; v_n integer;
begin
  if v_modo not in ('pct', 'monto') then raise exception 'Elegí si es un porcentaje o un monto' using errcode = '22023'; end if;
  if v_valor is null or v_valor = 0 then raise exception 'Poné el aumento' using errcode = '22023'; end if;
  if v_modo = 'pct' and (v_valor < -99 or v_valor > 1000) then raise exception 'El porcentaje tiene que estar entre -99 y 1000' using errcode = '22023'; end if;
  if v_alcance = 'ids' then
    if jsonb_typeof(p -> 'ids') is distinct from 'array' then raise exception 'No hay productos elegidos' using errcode = '22023'; end if;
    select array_agg(distinct (x #>> '{}')::bigint) into v_ids from jsonb_array_elements(p -> 'ids') x;
  elsif v_alcance = 'categoria' then
    if not exists (select 1 from public.categorias where id = v_cat and negocio_id = v_neg) then raise exception 'Elegí la categoría' using errcode = '22023'; end if;
  elsif v_alcance = 'proveedor' then
    if not exists (select 1 from public.proveedores where id = v_prov and negocio_id = v_neg) then raise exception 'Elegí el proveedor' using errcode = '22023'; end if;
  elsif v_alcance <> 'todos' then
    raise exception 'Elegí a qué productos' using errcode = '22023';
  end if;

  -- los productos elegidos (activos), siempre en el mismo orden
  select coalesce(array_agg(pr.id order by pr.id), '{}') into v_sel from public.productos pr
  where pr.negocio_id = v_neg and pr.activo
    and case v_alcance
          when 'ids' then pr.id = any (v_ids)
          when 'categoria' then pr.categoria_id = v_cat
          when 'proveedor' then pr.proveedor_id = v_prov
                                or exists (select 1 from public.producto_proveedores pp where pp.producto_id = pr.id and pp.proveedor_id = v_prov)
          else true end;
  -- simular: cuántos y unos ejemplos, sin cambiar nada (para la vista previa de la pantalla)
  if coalesce((p ->> 'simular')::boolean, false) then
    return jsonb_build_object('cantidad', cardinality(v_sel), 'ejemplos', coalesce((select jsonb_agg(jsonb_build_object('nombre', x.nombre, 'precio', x.precio,
        'precio_nuevo', public.valor_aumentado(x.precio, v_modo, v_valor, v_mult)) order by x.nombre)
      from (select * from public.productos where id = any (v_sel) order by nombre limit 4) x), '[]'::jsonb));
  end if;
  if cardinality(v_sel) = 0 then raise exception 'No hay productos que coincidan' using errcode = '22023'; end if;
  perform 1 from public.productos where id = any (v_sel) order by id for update;

  insert into public.aumentos (negocio_id, usuario_id, descripcion)
    values (v_neg, v_u, coalesce(nullif(left(btrim(coalesce(p ->> 'descripcion', '')), 200), ''), 'Aumento de precios')) returning id into v_id;
  with cambios as (
    insert into public.aumento_cambios (negocio_id, aumento_id, producto_id, precio_antes, costo_antes, precio_despues, costo_despues)
      select v_neg, v_id, pr.id, pr.precio, pr.costo, public.valor_aumentado(pr.precio, v_modo, v_valor, v_mult),
             case when v_costo then public.valor_aumentado(pr.costo, v_modo, v_valor, 0) else pr.costo end
      from public.productos pr where pr.id = any (v_sel)
    returning producto_id, precio_despues, costo_despues
  )
  update public.productos pr set precio = c.precio_despues, costo = c.costo_despues
    from cambios c where pr.id = c.producto_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('id', v_id, 'cantidad', v_n);
end;
$$;

-- Deshacer: vuelven al precio y costo de antes los que no se tocaron después
create or replace function public.deshacer_aumento(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); a public.aumentos; v_total integer; v_rev integer;
begin
  select * into a from public.aumentos where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró el aumento' using errcode = 'P0002'; end if;
  if a.deshecho then raise exception 'Ese aumento ya se deshizo' using errcode = 'P0001'; end if;
  select count(*) into v_total from public.aumento_cambios where aumento_id = a.id;
  perform 1 from public.productos where id in (select producto_id from public.aumento_cambios where aumento_id = a.id) order by id for update;
  update public.productos pr set precio = c.precio_antes, costo = c.costo_antes
    from public.aumento_cambios c
    where c.aumento_id = a.id and pr.id = c.producto_id and pr.precio = c.precio_despues and pr.costo = c.costo_despues;
  get diagnostics v_rev = row_count;
  update public.aumentos set deshecho = true, deshecho_fecha = now(), deshecho_por = v_u where id = a.id;
  return jsonb_build_object('revertidos', v_rev, 'saltados', v_total - v_rev);
end;
$$;

-- Los últimos 15 (para deshacer)
create or replace function public.aumentos()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'fecha', a.fecha, 'descripcion', a.descripcion,
      'usuario', public.nombre_usuario(a.usuario_id), 'deshecho', a.deshecho,
      'cantidad', (select count(*) from public.aumento_cambios c where c.aumento_id = a.id)) order by a.id desc)
    from (select * from public.aumentos where negocio_id = v_neg order by id desc limit 15) a), '[]'::jsonb);
end;
$$;

-- Redondeo de los precios (Ajustes): múltiplo entre 0 (sin redondeo) y 100000
create or replace function public.guardar_redondeo(p_valor numeric)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if p_valor is null or p_valor < 0 or p_valor > 100000 then raise exception 'El redondeo tiene que ser entre 0 y 100000' using errcode = '22023'; end if;
  insert into public.config (negocio_id, clave, valor) values (v_neg, 'redondeo', to_jsonb(trim_scale(round(p_valor, 2))))
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
  return trim_scale(round(p_valor, 2));
end;
$$;

revoke all on function public.redondeo_precios(uuid), public.redondear_precio(numeric, numeric), public.valor_aumentado(numeric, text, numeric, numeric), public.aumento_masivo(jsonb),
  public.deshacer_aumento(bigint), public.aumentos(), public.guardar_redondeo(numeric) from public, anon, authenticated;
grant execute on function public.aumento_masivo(jsonb), public.deshacer_aumento(bigint), public.aumentos(), public.guardar_redondeo(numeric) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 13, 'hora', now());
$$;
