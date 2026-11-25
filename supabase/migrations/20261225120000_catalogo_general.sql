-- =====================================================================
-- Catálogo general de productos (compartido por todos los negocios) y marca y contenido en los productos.
--
-- catalogo_general: productos con código de barras de los datos abiertos de Precios Claros (SEPA, Secretaría de Comercio),
-- unificados por código (tools/catalogo-general.js; los datos van en la migración siguiente). Solo de lectura, por funciones:
--   - catalogo_general_buscar(texto): por código (con o sin el 0 de adelante de un UPC) o por palabras del nombre/marca;
--     marca los que el negocio ya tiene.
--   - agregar_desde_catalogo(items): el dueño crea en su negocio los que eligió, con su precio (y costo, categoría: una de las
--     suyas o la sugerida, que se crea si no la tiene).
-- Categoría sugerida (catalogo_general.categoria): deducida del nombre por palabras (tools/catalogo-general/categorias.js);
-- crear_categorias(nombres) crea de una vez las que falten (Productos → Categorías → Crear las sugeridas).
--   - alta_desde_caja y guardar_producto reciben marca y contenido (Vender completa el nombre desde el catálogo general).
-- productos.marca, productos.contenido + productos.unidad (g, kg, ml, l, un, m): opcionales.
-- =====================================================================
create table public.catalogo_general (
  codigo text primary key check (codigo ~ '^\d{8,14}$'),
  nombre text not null check (length(nombre) between 1 and 160),
  marca text check (length(marca) <= 80),
  contenido numeric(12, 3) check (contenido > 0),
  unidad text check (unidad in ('g', 'kg', 'ml', 'l', 'un', 'm')),
  precio_ref numeric(14, 2),            -- mediana del precio de lista en las cadenas (referencia, no se usa sola)
  cadenas integer not null default 1,   -- en cuántas cadenas aparece (para ordenar: los más comunes primero)
  categoria text check (length(categoria) <= 40),   -- sugerida, deducida del nombre (puede no tener)
  -- para buscar sin mayúsculas ni acentos
  busca text generated always as (lower(translate(nombre || ' ' || coalesce(marca, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'))) stored
);
alter table public.catalogo_general enable row level security;
revoke all on public.catalogo_general from anon, authenticated;

alter table public.productos add column marca text check (length(marca) <= 80),
  add column contenido numeric(12, 3) check (contenido > 0),
  add column unidad text check (unidad in ('g', 'kg', 'ml', 'l', 'un', 'm')),
  add constraint productos_contenido_unidad check ((contenido is null) = (unidad is null));

-- Las formas de escribir un mismo código: un UPC (12) se lee también con un 0 adelante (13), y al revés
create or replace function public.codigo_variantes(c text)
returns text[] language sql immutable set search_path = '' as $$
  select array_remove(array[c, case when c ~ '^\d{12}$' then '0' || c end, case when c ~ '^0\d{12}$' then substr(c, 2) end], null);
$$;

-- El contenido escrito por la persona: "500 g", "2,25 l", "750 cc", "1 kg", o vacío. Devuelve (contenido, unidad).
create or replace function public.leer_contenido(p jsonb, out contenido numeric, out unidad text)
language plpgsql immutable set search_path = '' as $$
declare v_c numeric := public.num(p, 'contenido', 'Contenido'); v_u text := lower(btrim(coalesce(p ->> 'unidad', '')));
begin
  v_u := case when v_u in ('gr', 'grs', 'gramos') then 'g' when v_u in ('cc', 'cm3') then 'ml' when v_u in ('lt', 'lts', 'litro', 'litros') then 'l'
              when v_u in ('kilo', 'kilos', 'kgs') then 'kg' when v_u in ('u', 'unidad', 'unidades', 'uni') then 'un' else v_u end;
  if v_c is null or v_c <= 0 then contenido := null; unidad := null; return; end if;
  if v_u not in ('g', 'kg', 'ml', 'l', 'un', 'm') then raise exception 'La unidad del contenido tiene que ser g, kg, ml, l, un o m' using errcode = '22023'; end if;
  contenido := round(v_c, 3); unidad := v_u;
end;
$$;

create or replace function public.catalogo_general_json(g public.catalogo_general, p_neg uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'marca', g.marca, 'contenido', g.contenido, 'unidad', g.unidad,
    'precio_ref', g.precio_ref, 'cadenas', g.cadenas, 'categoria', g.categoria,
    -- el negocio ya lo tiene (por su código principal o uno alternativo)
    'ya', exists (select 1 from public.productos p where p.negocio_id = p_neg and lower(p.codigo) = any (public.codigo_variantes(g.codigo)))
       or exists (select 1 from public.producto_codigos c where c.negocio_id = p_neg and lower(c.codigo) = any (public.codigo_variantes(g.codigo))));
$$;

-- Buscar en el catálogo general: un código (de 8 a 14 números) o palabras (todas tienen que estar, sin acentos)
create or replace function public.catalogo_general_buscar(p_texto text, p_limite integer default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_t text := btrim(coalesce(p_texto, '')); v_palabras text[];
  v_lim integer := least(greatest(coalesce(p_limite, 50), 1), 200);
begin
  perform public.requiere_usuario();
  if v_t ~ '^\d{8,14}$' then
    return coalesce((select jsonb_agg(public.catalogo_general_json(g, v_neg)) from public.catalogo_general g where g.codigo = any (public.codigo_variantes(v_t))), '[]'::jsonb);
  end if;
  v_palabras := array(select w from regexp_split_to_table(lower(translate(v_t, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')), '\s+') w where length(w) >= 2);
  if cardinality(v_palabras) = 0 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(public.catalogo_general_json(g, v_neg) order by g.cadenas desc, g.nombre)
    from (select * from public.catalogo_general g
          where not exists (select 1 from unnest(v_palabras) w where position(w in g.busca) = 0)
          order by g.cadenas desc, g.nombre limit v_lim) g), '[]'::jsonb);
end;
$$;

-- La categoría del negocio con ese nombre (sin mayúsculas ni espacios de más); con p_crear, la crea si no está
create or replace function public.categoria_por_nombre(p_neg uuid, p_nombre text, p_crear boolean)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint; v_nombre text := left(btrim(coalesce(p_nombre, '')), 60);
begin
  if v_nombre = '' then return null; end if;
  select id into v_id from public.categorias where negocio_id = p_neg and lower(btrim(nombre)) = lower(v_nombre);
  if v_id is null and p_crear then insert into public.categorias (negocio_id, nombre) values (p_neg, v_nombre) returning id into v_id; end if;
  return v_id;
end;
$$;

-- Crear de una vez varias categorías (las sugeridas): las que ya están no se repiten. Devuelve todas las del negocio.
create or replace function public.crear_categorias(p_nombres jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); n text;
begin
  perform public.requiere_admin();
  if jsonb_typeof(p_nombres) is distinct from 'array' or jsonb_array_length(p_nombres) > 50 then raise exception 'Lista de categorías inválida' using errcode = '22023'; end if;
  for n in select jsonb_array_elements_text(p_nombres) loop perform public.categoria_por_nombre(v_neg, n, true); end loop;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre) order by lower(c.nombre)) from public.categorias c where c.negocio_id = v_neg), '[]'::jsonb);
end;
$$;

-- El dueño crea en su negocio productos del catálogo general. p_items: [{ codigo, precio, costo?, categoria_id? | categoria: 'sugerida' }].
-- Los que ya tiene (por código) se saltean. Devuelve { creados, ya: [nombres], productos: [producto_json] }.
create or replace function public.agregar_desde_catalogo(p_items jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); it jsonb; g public.catalogo_general; r public.productos; v_cat bigint; v_precio numeric;
  v_creados jsonb := '[]'; v_ya jsonb := '[]';
begin
  perform public.requiere_admin();
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Elegí los productos' using errcode = '22023'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'Se pueden agregar hasta 500 productos por vez' using errcode = '22023'; end if;
  for it in select value from jsonb_array_elements(p_items) loop
    select * into g from public.catalogo_general where codigo = it ->> 'codigo';
    if not found then raise exception 'El código % no está en el catálogo general', it ->> 'codigo' using errcode = 'P0002'; end if;
    v_precio := round(public.num(it, 'precio', 'Precio'), 2);
    if v_precio is null or v_precio < 0 then raise exception 'Falta el precio de "%"', g.nombre using errcode = '22023'; end if;
    v_cat := nullif(it ->> 'categoria_id', '')::bigint;
    if it ->> 'categoria' = 'sugerida' then v_cat := public.categoria_por_nombre(v_neg, g.categoria, true); end if;
    if v_cat is not null and not exists (select 1 from public.categorias where id = v_cat and negocio_id = v_neg) then
      raise exception 'Categoría no encontrada' using errcode = 'P0002';
    end if;
    if (public.catalogo_general_json(g, v_neg) ->> 'ya')::boolean then v_ya := v_ya || to_jsonb(g.nombre); continue; end if;
    insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, marca, contenido, unidad)
      values (v_neg, left(g.nombre, 120), g.codigo, v_cat, coalesce(round(public.num(it, 'costo', 'Costo'), 2), 0), v_precio, g.marca, g.contenido, g.unidad)
      returning * into r;
    v_creados := v_creados || public.producto_json(r, true);
  end loop;
  return jsonb_build_object('creados', jsonb_array_length(v_creados), 'ya', v_ya, 'productos', v_creados);
end;
$$;

create or replace function public.producto_json(p public.productos, p_costo boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'codigo', p.codigo, 'categoria_id', p.categoria_id,
    'precio', p.precio, 'stock', p.stock, 'stock_min', p.stock_min, 'por_peso', p.por_peso, 'plu', p.plu,
    'favorito', p.favorito, 'activo', p.activo, 'actualizado', p.actualizado, 'proveedor_id', p.proveedor_id, 'margen', p.margen, 'a_revisar', p.a_revisar,
    'marca', p.marca, 'contenido', p.contenido, 'unidad', p.unidad,
    'codigos', coalesce((select jsonb_agg(c.codigo order by c.id) from public.producto_codigos c where c.producto_id = p.id), '[]'::jsonb))
    || case when p_costo then jsonb_build_object('costo', p.costo) else '{}'::jsonb end;
$$;


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
  v_marca text := nullif(left(btrim(coalesce(p ->> 'marca', '')), 80), ''); v_cont record := public.leer_contenido(p);
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
    insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, stock, stock_min, por_peso, plu, favorito, marca, contenido, unidad)
    values (v_neg, v_nombre, v_codigo, v_cat,
      coalesce(round(public.num(p, 'costo', 'Costo'), 2), 0), coalesce(round(public.num(p, 'precio', 'Precio'), 2), 0),
      coalesce(v_stock, 0), coalesce(round(public.num(p, 'stock_min', 'Stock mínimo'), 3), 0),
      coalesce((p ->> 'por_peso')::boolean, false), v_plu, coalesce((p ->> 'favorito')::boolean, false), v_marca, v_cont.contenido, v_cont.unidad)
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
        favorito = coalesce((p ->> 'favorito')::boolean, favorito), activo = coalesce((p ->> 'activo')::boolean, activo),
        -- marca y contenido: solo si vienen (Compras y otras pantallas guardan sin ellos)
        marca = case when p ? 'marca' then v_marca else marca end,
        contenido = case when p ? 'contenido' then v_cont.contenido else contenido end, unidad = case when p ? 'contenido' then v_cont.unidad else unidad end,
        a_revisar = false   -- el dueño lo revisó y lo guardó desde la ficha
      where id = v_id returning * into r;
    if v_stock is not null and v_stock <> v_actual.stock then
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
        values (v_neg, r.id, v_stock - v_actual.stock, 'Corrección desde la ficha', v_u);
    end if;
  end if;
  return public.producto_json(r, true);
end;
$$;


create or replace function public.alta_desde_caja(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario();
  v_codigo text := nullif(btrim(coalesce(p ->> 'codigo', '')), '');
  v_nombre text := left(btrim(coalesce(p ->> 'nombre', '')), 120);
  v_precio numeric := round(public.num(p, 'precio', 'Precio'), 2);
  v_otro text; r public.productos;
  v_marca text := nullif(left(btrim(coalesce(p ->> 'marca', '')), 80), ''); v_cont record := public.leer_contenido(p);
begin
  if v_precio is null or v_precio <= 0 then raise exception 'Poné el precio' using errcode = '22023'; end if;
  if v_codigo is not null and v_codigo !~ '^\S{1,40}$' then
    raise exception 'El código no puede tener espacios ni pasar de 40 caracteres' using errcode = '22023';
  end if;
  if v_codigo is not null then
    v_otro := coalesce((select nombre from public.productos where negocio_id = v_neg and lower(codigo) = lower(v_codigo) limit 1),
      (select pr.nombre from public.producto_codigos c join public.productos pr on pr.id = c.producto_id
        where c.negocio_id = v_neg and lower(c.codigo) = lower(v_codigo) limit 1));
    if v_otro is not null then raise exception 'El código % ya lo tiene "%"', v_codigo, v_otro using errcode = '23505'; end if;
  end if;
  if v_nombre = '' then v_nombre := case when v_codigo is null then 'Producto sin nombre' else 'Producto ' || v_codigo end; end if;
  if (select count(*) from public.productos where negocio_id = v_neg and a_revisar) >= 500 then
    raise exception 'Hay 500 productos creados en caja sin revisar: revisalos en Productos antes de crear más' using errcode = 'P0001';
  end if;
  insert into public.productos (negocio_id, nombre, codigo, precio, a_revisar, marca, contenido, unidad)
    values (v_neg, v_nombre, v_codigo, v_precio, true, v_marca, v_cont.contenido, v_cont.unidad)
    returning * into r;
  return public.producto_json(r, public.es_admin());
end;
$$;


revoke all on function public.codigo_variantes(text), public.leer_contenido(jsonb), public.catalogo_general_json(public.catalogo_general, uuid),
  public.catalogo_general_buscar(text, integer), public.agregar_desde_catalogo(jsonb), public.categoria_por_nombre(uuid, text, boolean),
  public.crear_categorias(jsonb) from public, anon, authenticated;
grant execute on function public.catalogo_general_buscar(text, integer), public.agregar_desde_catalogo(jsonb), public.crear_categorias(jsonb) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 42, 'hora', now());
$$;
