-- =====================================================================
-- Varios códigos de barras por producto, y lo que hace falta para dar de alta un producto desde Compras
-- Un producto tiene su código principal (productos.codigo) y puede tener otros (producto_codigos): por ejemplo, el mismo
-- producto con el envase nuevo. Cualquiera de ellos lo encuentra al vender, comprar o leer una factura. Un código es de
-- un solo producto (principal u otro). Al cargar una compra desde la factura, un código de barras nuevo de un producto que
-- ya tenía el suyo queda como otro código.
-- =====================================================================

create table public.producto_codigos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  producto_id bigint not null,
  codigo text not null check (codigo ~ '^\S{1,40}$'),
  creado timestamptz not null default now(),
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete cascade
);
create unique index producto_codigos_unico on public.producto_codigos (negocio_id, lower(codigo));
create index producto_codigos_producto on public.producto_codigos (producto_id);
alter table public.producto_codigos enable row level security;
revoke all on public.producto_codigos from anon, authenticated;

-- De qué producto es un código (principal u otro), salvo p_excepto; null si no es de ninguno
create or replace function public.codigo_usado_por(p_neg uuid, p_codigo text, p_excepto bigint)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select nombre from public.productos where negocio_id = p_neg and lower(codigo) = lower(btrim(p_codigo)) and id is distinct from p_excepto limit 1),
    (select pr.nombre from public.producto_codigos c join public.productos pr on pr.id = c.producto_id
      where c.negocio_id = p_neg and lower(c.codigo) = lower(btrim(p_codigo)) and c.producto_id is distinct from p_excepto limit 1));
$$;

-- El producto (activo) que tiene ese código, principal u otro
create or replace function public.producto_por_codigo(p_neg uuid, p_codigo text)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select id from public.productos where negocio_id = p_neg and activo and lower(btrim(codigo)) = lower(btrim(p_codigo)) limit 1),
    (select c.producto_id from public.producto_codigos c join public.productos pr on pr.id = c.producto_id and pr.activo
      where c.negocio_id = p_neg and lower(c.codigo) = lower(btrim(p_codigo)) limit 1));
$$;

-- Que el código principal de un producto no sea "otro código" de uno distinto (guardar_producto ya controla los principales).
-- Si un otro código pasa a ser el principal del mismo producto, sale de la lista de otros.
create or replace function public.controlar_codigo_principal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_otro text;
begin
  if new.codigo is not null and (tg_op = 'INSERT' or new.codigo is distinct from old.codigo) then
    select pr.nombre into v_otro from public.producto_codigos c join public.productos pr on pr.id = c.producto_id
      where c.negocio_id = new.negocio_id and lower(c.codigo) = lower(new.codigo) and c.producto_id <> new.id limit 1;
    if v_otro is not null then raise exception 'El código % ya lo tiene "%"', new.codigo, v_otro using errcode = '23505'; end if;
    if tg_op = 'UPDATE' then delete from public.producto_codigos where producto_id = new.id and lower(codigo) = lower(new.codigo); end if;
  end if;
  return new;
end;
$$;
create trigger productos_codigo_principal before insert or update of codigo on public.productos
  for each row execute function public.controlar_codigo_principal();

create or replace function public.producto_json(p public.productos, p_costo boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'codigo', p.codigo, 'categoria_id', p.categoria_id,
    'precio', p.precio, 'stock', p.stock, 'stock_min', p.stock_min, 'por_peso', p.por_peso, 'plu', p.plu,
    'favorito', p.favorito, 'activo', p.activo, 'actualizado', p.actualizado, 'proveedor_id', p.proveedor_id,
    'codigos', coalesce((select jsonb_agg(c.codigo order by c.id) from public.producto_codigos c where c.producto_id = p.id), '[]'::jsonb))
    || case when p_costo then jsonb_build_object('costo', p.costo) else '{}'::jsonb end;
$$;

-- Agregar un código a un producto (solo dueño): si no tenía, queda como el principal; si no, como otro código
create or replace function public.agregar_codigo(p_producto_id bigint, p_codigo text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r public.productos; v_cod text := btrim(coalesce(p_codigo, '')); v_otro text;
begin
  perform public.requiere_admin();
  r := public.requiere_producto(p_producto_id);
  if v_cod !~ '^\S{1,40}$' then raise exception 'El código tiene que tener entre 1 y 40 caracteres, sin espacios' using errcode = '22023'; end if;
  if lower(coalesce(r.codigo, '')) = lower(v_cod) or exists (select 1 from public.producto_codigos where producto_id = r.id and lower(codigo) = lower(v_cod)) then
    raise exception 'Ese código ya es de "%"', r.nombre using errcode = '23505';
  end if;
  v_otro := public.codigo_usado_por(r.negocio_id, v_cod, r.id);
  if v_otro is not null then raise exception 'El código % ya lo tiene "%"', v_cod, v_otro using errcode = '23505'; end if;
  if coalesce(r.codigo, '') = '' then
    update public.productos set codigo = v_cod where id = r.id returning * into r;
  else
    insert into public.producto_codigos (negocio_id, producto_id, codigo) values (r.negocio_id, r.id, v_cod);
    update public.productos set actualizado = now() where id = r.id returning * into r;   -- para que el catálogo del navegador se entere
  end if;
  return public.producto_json(r, true);
end;
$$;

-- Quitar uno de los otros códigos (el principal se cambia desde la ficha)
create or replace function public.quitar_codigo(p_producto_id bigint, p_codigo text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r public.productos;
begin
  perform public.requiere_admin();
  r := public.requiere_producto(p_producto_id);
  delete from public.producto_codigos where producto_id = r.id and lower(codigo) = lower(btrim(coalesce(p_codigo, '')));
  if not found then raise exception 'Ese código no está entre los otros códigos del producto' using errcode = 'P0002'; end if;
  update public.productos set actualizado = now() where id = r.id returning * into r;
  return public.producto_json(r, true);
end;
$$;

-- Leer facturas: el código de barras también encuentra los otros códigos
create or replace function public.preparar_factura(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $
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
        and pr.id = public.producto_por_codigo(v_neg, public.codigo_barras(it ->> 'codigo_barras')) limit 1;
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
        select jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre) order by s.puntaje desc, s.nombre) from (select * from (
          select pr.id, pr.nombre, (select count(*) from unnest(v_bus) w where exists (select 1 from unnest(public.palabras(pr.nombre)) x
                   where x = w or (length(w) > 3 and (x like w || '%' or w like x || '%'))))::numeric
                 / greatest(cardinality(v_bus), cardinality(public.palabras(pr.nombre)), 1) as puntaje
          from public.productos pr where pr.negocio_id = v_neg and pr.activo and cardinality(v_bus) > 0
        ) s0 where s0.puntaje > 0 order by s0.puntaje desc, s0.nombre limit 5) s), '[]'::jsonb)));
    end if;
  end loop;
  return jsonb_build_object('proveedor', case when v_prov is null then null else jsonb_build_object('id', v_prov) end, 'cuit', v_cuit, 'lineas', v_lineas,
    'margen', public.margen_precios(v_neg), 'redondeo', public.redondeo_precios(v_neg));
end;
$;


-- Guardar la compra desde la factura: un código de barras nuevo de un producto que ya tenía el suyo queda como otro código
create or replace function public.registrar_compra_factura(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $
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
    -- el código de barras de la factura, si ningún producto lo usa: el principal si no tenía; si ya tenía otro (cambió el
    -- envase), queda como otro código del producto
    v_barras := public.codigo_barras(l ->> 'codigo_barras');
    if v_barras is not null and public.codigo_usado_por(v_neg, v_barras, null) is null then
      if exists (select 1 from public.productos where id = v_prod and coalesce(codigo, '') = '') then
        update public.productos set codigo = v_barras where id = v_prod;
      else
        insert into public.producto_codigos (negocio_id, producto_id, codigo) values (v_neg, v_prod, v_barras);
        update public.productos set actualizado = now() where id = v_prod;
      end if;
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
$;


revoke all on function public.codigo_usado_por(uuid, text, bigint), public.producto_por_codigo(uuid, text), public.controlar_codigo_principal(),
  public.agregar_codigo(bigint, text), public.quitar_codigo(bigint, text) from public, anon, authenticated;
grant execute on function public.agregar_codigo(bigint, text), public.quitar_codigo(bigint, text) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 18, 'hora', now());
$$;
