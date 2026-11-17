-- =====================================================================
-- Etapa 8a: cargar una compra desde la factura (leída con IA)
-- La factura la lee la función de Supabase "leer-factura" (con la clave de IA guardada en los secretos de Supabase, nunca
-- en el navegador). La base: controla quién puede leer y cuántas lecturas por día, anota el consumo, reconoce el proveedor
-- y los productos de cada renglón (por código de barras, por el código del proveedor o por cómo lo describe), propone
-- productos parecidos, y guarda la compra recordando cómo viene cada producto de ese proveedor para la próxima factura.
-- El formato de la factura leída está en CLAUDE.md ("Factura leída").
-- =====================================================================

-- Cómo viene cada producto en las facturas de cada proveedor
alter table public.producto_proveedores add column descripcion_proveedor text;
alter table public.producto_proveedores add column unidades numeric(14, 3);   -- unidades de venta por unidad facturada
create index producto_proveedores_codigo on public.producto_proveedores (proveedor_id, codigo_proveedor) where codigo_proveedor is not null;

-- Consumo de IA por negocio (para saber cuánto gasta cada uno; el detalle oficial está en la consola de Anthropic)
create table public.lecturas_ia (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  fecha timestamptz not null default now(),
  usuario_id bigint,
  tarea text not null default 'leer_factura',
  modelo text,
  tokens_entrada integer not null default 0,
  tokens_salida integer not null default 0,
  costo_usd numeric(10, 4) not null default 0,
  ok boolean not null default true,
  resultado text,
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index lecturas_ia_negocio on public.lecturas_ia (negocio_id, fecha);
alter table public.lecturas_ia enable row level security;
revoke all on public.lecturas_ia from anon, authenticated;

-- Margen para proponer el precio de venta de los productos nuevos de una factura (config 'margen', 40 de fábrica)
create or replace function public.margen_precios(p_neg uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select case when jsonb_typeof(c.valor) = 'number' and (c.valor #>> '{}')::numeric between 0 and 1000
                               then (c.valor #>> '{}')::numeric end
                   from public.config c where c.negocio_id = p_neg and c.clave = 'margen'), 40);
$$;

create or replace function public.guardar_margen(p_valor numeric)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if p_valor is null or p_valor < 0 or p_valor > 1000 then raise exception 'El margen tiene que ser entre 0 y 1000' using errcode = '22023'; end if;
  insert into public.config (negocio_id, clave, valor) values (v_neg, 'margen', to_jsonb(trim_scale(round(p_valor, 2))))
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
  return trim_scale(round(p_valor, 2));
end;
$$;

-- ---------------------------------------------------------------------
-- Lectura con IA: la función de Supabase pide permiso como el usuario y anota el consumo como servicio
-- ---------------------------------------------------------------------
-- Hasta 60 lecturas por día por negocio (para que un error o un abuso no gaste de más)
create or replace function public.permiso_lectura_ia()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v_hoy integer;
begin
  select count(*) into v_hoy from public.lecturas_ia where negocio_id = v_neg and fecha > now() - interval '1 day';
  if v_hoy >= 60 then
    raise exception 'Ya se leyeron 60 facturas en las últimas 24 horas: probá de nuevo más tarde' using errcode = 'P0001';
  end if;
  return jsonb_build_object('negocio_id', v_neg, 'usuario_id', v_u);
end;
$$;

-- Solo la llama la función de Supabase (con la clave de servicio)
create or replace function public.anotar_lectura_ia(p_neg uuid, p_usuario bigint, p jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  insert into public.lecturas_ia (negocio_id, usuario_id, modelo, tokens_entrada, tokens_salida, costo_usd, ok, resultado)
    values (p_neg, p_usuario, left(p ->> 'modelo', 60), coalesce((p ->> 'tokens_entrada')::integer, 0), coalesce((p ->> 'tokens_salida')::integer, 0),
            coalesce((p ->> 'costo_usd')::numeric, 0), coalesce((p ->> 'ok')::boolean, true), left(p ->> 'resultado', 300));
end;
$$;

-- Consumo: este mes, en total y las últimas 10 lecturas
create or replace function public.uso_ia()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_mes timestamptz;
begin
  perform public.requiere_admin();
  v_mes := (date_trunc('month', now() at time zone public.zona_horaria(v_neg))) at time zone public.zona_horaria(v_neg);
  return jsonb_build_object(
    'mes', (select jsonb_build_object('lecturas', count(*), 'costo_usd', coalesce(sum(costo_usd), 0)) from public.lecturas_ia where negocio_id = v_neg and fecha >= v_mes),
    'total', (select jsonb_build_object('lecturas', count(*), 'costo_usd', coalesce(sum(costo_usd), 0)) from public.lecturas_ia where negocio_id = v_neg),
    'ultimas', coalesce((select jsonb_agg(jsonb_build_object('fecha', l.fecha, 'usuario', public.nombre_usuario(l.usuario_id), 'ok', l.ok,
        'resultado', l.resultado, 'costo_usd', l.costo_usd) order by l.id desc)
      from (select * from public.lecturas_ia where negocio_id = v_neg order by id desc limit 10) l), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- Reconocer lo que trae la factura
-- ---------------------------------------------------------------------
-- Palabras para comparar descripciones: sin tildes, números separados de las letras ("x400g" → 400 g), sin las que no dicen nada
create or replace function public.palabras(p text)
returns text[] language sql immutable set search_path = '' as $$
  select coalesce(array_agg(distinct w), '{}') from regexp_split_to_table(
    regexp_replace(regexp_replace(regexp_replace(
      translate(lower(coalesce(p, '')), 'áéíóúüàèìòùâêîôûñ', 'aeiouuaeiouaeioun'),
      '([a-z])([0-9])', '\1 \2', 'g'), '([0-9])([a-z])', '\1 \2', 'g'), '[^a-z0-9]+', ' ', 'g'), ' ') w
  where length(w) > 1 and w <> all (array['un', 'unid', 'unidad', 'unidades', 'gr', 'grs', 'gs', 'gramos', 'ml', 'cc', 'lt', 'lts',
                                          'de', 'con', 'en', 'el', 'la', 'bolsa']);
$$;

-- Código de barras válido (8 a 14 números) o null
create or replace function public.codigo_barras(p text)
returns text language sql immutable set search_path = '' as $$
  select case when length(d) between 8 and 14 then d end from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;

-- p: { factura, proveedor_id? }. Devuelve { proveedor: {id} | null, cuit, lineas: [{ producto_id, unidades, sugerencias: [{id, nombre}] }] }
-- El proveedor: el elegido a mano, o por CUIT, o por la primera palabra del nombre. Cada renglón: por código de barras,
-- por el código del proveedor o por cómo lo describe; si no, hasta 5 productos parecidos.
create or replace function public.preparar_factura(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); f jsonb := p -> 'factura'; v_cuit text; v_prov bigint; v_primera text; it jsonb;
  v_lineas jsonb := '[]'::jsonb; v_pid bigint; v_un numeric; v_bus text[];
begin
  perform public.requiere_admin();
  if jsonb_typeof(f -> 'items') is distinct from 'array' then raise exception 'La factura no tiene renglones' using errcode = '22023'; end if;
  begin v_cuit := public.cuit_valido(f #>> '{proveedor,cuit}'); exception when others then v_cuit := null; end;
  v_prov := (select id from public.proveedores where negocio_id = v_neg and id = nullif(p ->> 'proveedor_id', '')::bigint);
  if v_prov is null and v_cuit is not null then v_prov := (select id from public.proveedores where negocio_id = v_neg and cuit = v_cuit limit 1); end if;
  if v_prov is null then
    v_primera := (public.palabras(split_part(btrim(coalesce(f #>> '{proveedor,nombre}', '')), ' ', 1)))[1];
    if length(v_primera) > 2 then
      v_prov := (select id from public.proveedores where negocio_id = v_neg and (public.palabras(split_part(btrim(nombre), ' ', 1)))[1] = v_primera order by id limit 1);
    end if;
  end if;
  for it in select value from jsonb_array_elements(f -> 'items') loop
    v_pid := null; v_un := null;
    select pr.id, pp.unidades into v_pid, v_un from public.productos pr
      left join public.producto_proveedores pp on pp.producto_id = pr.id and pp.proveedor_id = v_prov
      where pr.negocio_id = v_neg and pr.activo and public.codigo_barras(it ->> 'codigo_barras') is not null
        and lower(btrim(pr.codigo)) = public.codigo_barras(it ->> 'codigo_barras') limit 1;
    if v_pid is null and v_prov is not null then
      select pp.producto_id, pp.unidades into v_pid, v_un from public.producto_proveedores pp join public.productos pr on pr.id = pp.producto_id and pr.activo
        where pp.proveedor_id = v_prov and nullif(btrim(it ->> 'codigo'), '') is not null and pp.codigo_proveedor = left(btrim(it ->> 'codigo'), 40) limit 1;
      if v_pid is null then
        select pp.producto_id, pp.unidades into v_pid, v_un from public.producto_proveedores pp join public.productos pr on pr.id = pp.producto_id and pr.activo
          where pp.proveedor_id = v_prov and pp.descripcion_proveedor = left(btrim(it ->> 'descripcion'), 160) limit 1;
      end if;
    end if;
    if v_pid is not null then
      v_lineas := v_lineas || jsonb_build_array(jsonb_build_object('producto_id', v_pid, 'unidades', v_un, 'sugerencias', '[]'::jsonb));
    else
      v_bus := public.palabras(it ->> 'descripcion');
      v_lineas := v_lineas || jsonb_build_array(jsonb_build_object('producto_id', null, 'unidades', null, 'sugerencias', coalesce((
        select jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre) order by s.puntaje desc, s.nombre) from (
          select pr.id, pr.nombre, (select count(*) from unnest(v_bus) w where exists (select 1 from unnest(public.palabras(pr.nombre)) x
                   where x = w or (length(w) > 3 and (x like w || '%' or w like x || '%'))))::numeric
                 / greatest(cardinality(v_bus), cardinality(public.palabras(pr.nombre)), 1) as puntaje
          from public.productos pr where pr.negocio_id = v_neg and pr.activo and cardinality(v_bus) > 0
        ) s where s.puntaje > 0 order by s.puntaje desc, s.nombre limit 5), '[]'::jsonb)));
    end if;
  end loop;
  return jsonb_build_object('proveedor', case when v_prov is null then null else jsonb_build_object('id', v_prov) end, 'cuit', v_cuit, 'lineas', v_lineas,
    'margen', public.margen_precios(v_neg), 'redondeo', public.redondeo_precios(v_neg));
end;
$$;

-- ---------------------------------------------------------------------
-- Guardar la compra desde la factura
-- p: { proveedor_id | proveedor_nuevo: {nombre, cuit}, comprobante, total, pagar_caja, forma, fecha_factura, vencimiento, notas,
--      lineas: [{ producto_id | nuevo: {nombre, categoria_id, por_peso, precio}, codigo, codigo_barras, descripcion, unidades,
--                 cantidad, costo, precio_nuevo }] }
-- Crea el proveedor y los productos nuevos, pone el código de barras a los que no tenían, recuerda cómo viene cada producto
-- de este proveedor y registra la compra (registrar_compra). Devuelve la compra con creados y productos.
-- ---------------------------------------------------------------------
create or replace function public.registrar_compra_factura(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v_prov bigint; v_cuit text;
  l jsonb; k integer := 0; v_prod bigint; v_barras text; v_codigo text; v_unid numeric; v_items jsonb := '[]'::jsonb;
  v_creados integer := 0; v_ids jsonb := '[]'::jsonb; r jsonb;
begin
  if jsonb_typeof(p -> 'lineas') is distinct from 'array' or jsonb_array_length(p -> 'lineas') = 0 then
    raise exception 'La factura no tiene renglones' using errcode = '22023';
  end if;
  v_prov := (select id from public.proveedores where negocio_id = v_neg and id = nullif(p ->> 'proveedor_id', '')::bigint);
  if v_prov is null then
    if jsonb_typeof(p -> 'proveedor_nuevo') is distinct from 'object' then raise exception 'Elegí el proveedor' using errcode = '22023'; end if;
    v_cuit := public.cuit_valido(p #>> '{proveedor_nuevo,cuit}');
    v_prov := (select id from public.proveedores where negocio_id = v_neg and cuit = v_cuit limit 1);
    if v_prov is null then
      v_prov := (public.guardar_proveedor(jsonb_build_object('nombre', p #>> '{proveedor_nuevo,nombre}', 'cuit', v_cuit)) ->> 'id')::bigint;
    end if;
  end if;
  for l in select value from jsonb_array_elements(p -> 'lineas') loop
    k := k + 1;
    v_prod := (select id from public.productos where negocio_id = v_neg and id = nullif(l ->> 'producto_id', '')::bigint);
    if v_prod is null then
      if jsonb_typeof(l -> 'nuevo') is distinct from 'object' then
        raise exception 'Falta elegir qué producto es el renglón % (%)', k, left(l ->> 'descripcion', 60) using errcode = '22023';
      end if;
      v_prod := (public.guardar_producto(jsonb_build_object('nombre', l #>> '{nuevo,nombre}', 'categoria_id', l #>> '{nuevo,categoria_id}',
        'por_peso', coalesce((l #>> '{nuevo,por_peso}')::boolean, false), 'costo', 0, 'precio', coalesce(nullif(l #>> '{nuevo,precio}', ''), '0'))) ->> 'id')::bigint;
      v_creados := v_creados + 1;
    end if;
    -- el código de barras de la factura, si el producto no tenía y ningún otro lo usa
    v_barras := public.codigo_barras(l ->> 'codigo_barras');
    if v_barras is not null and not exists (select 1 from public.productos where negocio_id = v_neg and lower(btrim(codigo)) = v_barras) then
      update public.productos set codigo = v_barras where id = v_prod and coalesce(codigo, '') = '';
    end if;
    -- cómo viene de este proveedor: un código de proveedor apunta a un solo producto
    v_codigo := nullif(left(btrim(coalesce(l ->> 'codigo', '')), 40), '');
    v_unid := round(coalesce(public.num(l, 'unidades', 'Unidades del renglón ' || k), 1), 3);
    if v_unid <= 0 then raise exception 'Revisá las unidades de venta del renglón %', k using errcode = '22023'; end if;
    if v_codigo is not null then
      update public.producto_proveedores set codigo_proveedor = null where proveedor_id = v_prov and codigo_proveedor = v_codigo and producto_id <> v_prod;
    end if;
    insert into public.producto_proveedores (negocio_id, producto_id, proveedor_id, codigo_proveedor, descripcion_proveedor, unidades)
      values (v_neg, v_prod, v_prov, v_codigo, nullif(left(btrim(coalesce(l ->> 'descripcion', '')), 160), ''), v_unid)
      on conflict (producto_id, proveedor_id) do update set codigo_proveedor = excluded.codigo_proveedor,
        descripcion_proveedor = excluded.descripcion_proveedor, unidades = excluded.unidades;
    v_items := v_items || jsonb_build_array(jsonb_build_object('producto_id', v_prod, 'cantidad', l -> 'cantidad', 'costo', l -> 'costo',
      'precio_nuevo', nullif(l ->> 'precio_nuevo', '')));
    v_ids := v_ids || to_jsonb(v_prod);
  end loop;
  r := public.registrar_compra(jsonb_build_object('proveedor_id', v_prov, 'comprobante', p -> 'comprobante', 'notas', p -> 'notas', 'total', p -> 'total',
    'pagar_caja', coalesce((p ->> 'pagar_caja')::boolean, false), 'forma', p -> 'forma', 'fecha_factura', p -> 'fecha_factura',
    'vencimiento', p -> 'vencimiento', 'items', v_items));
  return r || jsonb_build_object('creados', v_creados, 'productos', v_ids);
end;
$$;

revoke all on function public.margen_precios(uuid), public.guardar_margen(numeric), public.permiso_lectura_ia(),
  public.anotar_lectura_ia(uuid, bigint, jsonb), public.uso_ia(), public.palabras(text), public.codigo_barras(text),
  public.preparar_factura(jsonb), public.registrar_compra_factura(jsonb) from public, anon, authenticated;
grant execute on function public.guardar_margen(numeric), public.permiso_lectura_ia(), public.uso_ia(),
  public.preparar_factura(jsonb), public.registrar_compra_factura(jsonb) to authenticated;
grant execute on function public.anotar_lectura_ia(uuid, bigint, jsonb) to service_role;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 14, 'hora', now());
$$;
