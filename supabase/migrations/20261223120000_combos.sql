-- =====================================================================
-- Combos: promociones con productos distintos ("Fernet + Coca 2,25 L a $12.000", o con un % menos).
-- Una promoción de tipo 'combo' tiene `componentes`: [{ productos: [id], cantidad }]. Cada componente es un producto, o varios
-- que valen igual (cualquiera de ellos); `cantidad` es cuántas unidades de ese componente lleva el combo. Un producto está en
-- un solo componente. El combo vale un precio fijo (`precio`) o un % menos (`pct`) en todas sus unidades.
--
-- La cuenta (la misma en promos.js):
--   - De cada componente, sus unidades de la más cara a la más barata (a igual precio, en el orden de los renglones).
--   - Se arman tantos combos como alcance el componente que menos tiene (combo 1: las más caras de cada componente…).
--   - Dentro de cada combo, las unidades van en el orden de los componentes. Con precio fijo, lo que se descuenta se
--     reparte en proporción al precio y la última unidad se lleva la diferencia del redondeo. Con %, se redondea por unidad.
--   - Lo demás no cambia: entra en promos_venta como cualquier otra (primero la que más descuenta).
-- `productos` sigue teniendo todos los productos (para buscarlas por producto); `cantidad`, las unidades del combo.
-- =====================================================================
do $$
declare r record;
begin
  -- los controles del tipo, que no conocían 'combo'
  for r in select conname from pg_constraint where conrelid = 'public.promociones'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%lleva_paga%' loop
    execute format('alter table public.promociones drop constraint %I', r.conname);
  end loop;
end $$;
alter table public.promociones add column componentes jsonb;
alter table public.promociones add constraint promociones_tipo check (tipo in ('lleva_paga', 'precio', 'unidad_pct', 'desde_pct', 'combo'));
alter table public.promociones add constraint promociones_datos check (case tipo
  when 'lleva_paga' then cantidad >= 2 and paga between 1 and cantidad - 1
  when 'precio' then cantidad >= 2 and precio is not null
  when 'unidad_pct' then cantidad >= 2 and pct is not null
  when 'combo' then jsonb_typeof(componentes) = 'array' and jsonb_array_length(componentes) between 2 and 10 and (precio is null) <> (pct is null)
  else pct is not null end);

-- Lo que descuenta un combo (mismo resultado que promo_descuentos: [{k, descuento}] de cada renglón que entró)
create or replace function public.promo_combo(pr public.promociones, p_lineas jsonb, p_usadas int[])
returns jsonb language sql stable security definer set search_path = '' as $$
  with comp as (
    select (t.ord - 1)::int as ci, (t.c ->> 'cantidad')::int as q,
           array(select x::bigint from jsonb_array_elements_text(t.c -> 'productos') x) as prods
    from jsonb_array_elements(pr.componentes) with ordinality as t(c, ord)
  ), l as (
    select x.k, x.producto_id, x.cantidad, x.precio from jsonb_to_recordset(p_lineas) as x(k int, producto_id bigint, cantidad numeric, precio numeric)
    where not (x.k = any (coalesce(p_usadas, '{}')))
  ), u as (
    select comp.ci, comp.q, l.k, round(l.precio * 100)::bigint as c,
           row_number() over (partition by comp.ci order by l.precio desc, l.k, s) as n
    from comp join l on l.producto_id = any (comp.prods) cross join generate_series(1, l.cantidad::int) s
  ), veces as (   -- cuántos combos alcanzan: lo que da el componente que menos tiene
    select min((select count(*) from u where u.ci = comp.ci) / comp.q) as v from comp
  ), g as (
    select u.ci, u.k, u.c, (u.n - 1) / u.q as grp from u, veces where u.n <= veces.v * u.q
  ), go as (
    select g.*, row_number() over (partition by g.grp order by g.ci, g.c desc, g.k) as pos, count(*) over (partition by g.grp) as tam,
           sum(g.c) over (partition by g.grp) as sc
    from g
  ), p1 as (
    select go.*, case when pr.precio is not null and go.sc > 0 then greatest(go.sc - round(pr.precio * 100)::bigint, 0) else 0 end as dg from go
  ), p2 as (
    select p1.*, case when pr.precio is not null and p1.pos < p1.tam and p1.sc > 0 then round(p1.c * p1.dg::numeric / p1.sc) else 0 end as sh from p1
  ), d as (
    select p2.k, case when pr.pct is not null then round(p2.c * pr.pct / 100.0)
                      when p2.pos = p2.tam then p2.dg - sum(p2.sh) over (partition by p2.grp) else p2.sh end as dc
    from p2
  )
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'descuento', round(t / 100.0, 2)) order by k), '[]'::jsonb)
  from (select k, sum(dc) as t from d group by k) x;
$$;

create or replace function public.promos_venta(p_neg uuid, p_lineas jsonb, p_formas text[], p_sin bigint[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  pr public.promociones; v_usadas int[] := '{}'; v_aplicadas bigint[] := '{}'; v_res jsonb := '[]';
  v_d jsonb; v_t numeric; v_mejor public.promociones; v_mejor_id bigint; v_mejor_t numeric; v_mejor_d jsonb;
begin
  loop
    v_mejor_id := null; v_mejor_t := 0;
    for pr in select * from public.promos_de_hoy(p_neg) loop
      continue when pr.id = any (coalesce(p_sin, '{}')) or pr.id = any (v_aplicadas)
        or (cardinality(pr.formas) > 0 and not (coalesce(p_formas, '{}') <@ pr.formas));
      v_d := case when pr.tipo = 'combo' then public.promo_combo(pr, p_lineas, v_usadas) else public.promo_descuentos(pr, p_lineas, v_usadas) end;
      select coalesce(sum((x ->> 'descuento')::numeric), 0) into v_t from jsonb_array_elements(v_d) x;
      if v_t > v_mejor_t then v_mejor := pr; v_mejor_id := pr.id; v_mejor_t := v_t; v_mejor_d := v_d; end if;
    end loop;
    exit when v_mejor_id is null;
    v_aplicadas := v_aplicadas || v_mejor_id;
    v_usadas := v_usadas || array(select (x ->> 'k')::int from jsonb_array_elements(v_mejor_d) x);
    v_res := v_res || (select jsonb_agg(x || jsonb_build_object('promocion_id', v_mejor.id, 'nombre', v_mejor.nombre)) from jsonb_array_elements(v_mejor_d) x);
  end loop;
  return v_res;
end;
$$;

create or replace function public.promo_json(p public.promociones)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'tipo', p.tipo, 'cantidad', p.cantidad, 'paga', p.paga, 'pct', p.pct,
    'precio', p.precio, 'productos', to_jsonb(p.productos), 'componentes', p.componentes, 'desde', p.desde, 'hasta', p.hasta,
    'dias', to_jsonb(p.dias), 'formas', to_jsonb(p.formas), 'activa', p.activa);
$$;

-- p: como antes; para un combo, además componentes: [{ productos: [id], cantidad }] y precio o pct (uno solo)
create or replace function public.guardar_promocion(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_id bigint := nullif(p ->> 'id', '')::bigint; r public.promociones;
  v_prods bigint[]; v_dias smallint[]; v_formas text[]; v_tipo text := p ->> 'tipo'; v_n int; v_paga int; v_pct int; v_precio numeric;
  v_comps jsonb; c jsonb; v_cp bigint[]; v_q numeric;
begin
  perform public.requiere_admin();
  if btrim(coalesce(p ->> 'nombre', '')) = '' then raise exception 'Poné el nombre de la promoción' using errcode = '22023'; end if;
  if v_tipo is null or v_tipo not in ('lleva_paga', 'precio', 'unidad_pct', 'desde_pct', 'combo') then raise exception 'Tipo de promoción inválido' using errcode = '22023'; end if;
  if v_tipo = 'combo' then
    -- los componentes: cada uno con sus productos (sin repetir entre componentes) y su cantidad
    if jsonb_typeof(p -> 'componentes') is distinct from 'array' or jsonb_array_length(p -> 'componentes') < 2 then
      raise exception 'Un combo lleva al menos dos productos distintos' using errcode = '22023';
    end if;
    if jsonb_array_length(p -> 'componentes') > 10 then raise exception 'Un combo lleva hasta 10 productos distintos' using errcode = '22023'; end if;
    v_comps := '[]'; v_prods := '{}'; v_n := 0;
    for c in select value from jsonb_array_elements(p -> 'componentes') loop
      if jsonb_typeof(c -> 'productos') is distinct from 'array' then raise exception 'Elegí los productos de cada parte del combo' using errcode = '22023'; end if;
      v_cp := array(select distinct x::bigint from jsonb_array_elements_text(c -> 'productos') x);
      if cardinality(v_cp) = 0 then raise exception 'Elegí los productos de cada parte del combo' using errcode = '22023'; end if;
      if v_cp && v_prods then raise exception 'Un producto está en dos partes del combo' using errcode = '22023'; end if;
      v_q := public.num(c, 'cantidad', 'Cantidad');
      if v_q is null or v_q < 1 or v_q > 100 or v_q <> trunc(v_q) then
        raise exception 'La cantidad de cada parte del combo tiene que ser un número entero entre 1 y 100' using errcode = '22023';
      end if;
      v_prods := v_prods || v_cp; v_n := v_n + v_q::int;
      v_comps := v_comps || jsonb_build_object('productos', to_jsonb(v_cp), 'cantidad', v_q::int);
    end loop;
    if v_n > 100 then raise exception 'El combo tiene demasiadas unidades' using errcode = '22023'; end if;
    if (public.num(p, 'precio', 'Precio') is null) = (public.num(p, 'pct', 'Porcentaje') is null) then
      raise exception 'Poné el precio del combo o el porcentaje de descuento (uno de los dos)' using errcode = '22023';
    end if;
    if public.num(p, 'precio', 'Precio') <= 0 then raise exception 'Poné el precio del combo' using errcode = '22023'; end if;
    v_precio := round(public.num(p, 'precio', 'Precio'), 2);
    v_pct := public.num(p, 'pct', 'Porcentaje');
    if v_pct is not null and (v_pct < 1 or v_pct > 100 or public.num(p, 'pct', 'Porcentaje') <> v_pct) then
      raise exception 'El porcentaje tiene que ser un número entero entre 1 y 100' using errcode = '22023';
    end if;
  else
    if jsonb_typeof(p -> 'productos') is distinct from 'array' then raise exception 'Elegí los productos de la promoción' using errcode = '22023'; end if;
    v_prods := array(select distinct x::bigint from jsonb_array_elements_text(p -> 'productos') x);
    if cardinality(v_prods) = 0 then raise exception 'Elegí los productos de la promoción' using errcode = '22023'; end if;
    v_n := public.num(p, 'cantidad', 'Cantidad');
    if v_n is null or v_n < 1 or v_n > 100 or public.num(p, 'cantidad', 'Cantidad') <> v_n then
      raise exception 'La cantidad tiene que ser un número entero entre 1 y 100' using errcode = '22023';
    end if;
    if v_tipo = 'precio' and (public.num(p, 'precio', 'Precio') is null or public.num(p, 'precio', 'Precio') <= 0) then
      raise exception 'Poné el precio de la promoción' using errcode = '22023';
    end if;
    if v_tipo in ('unidad_pct', 'desde_pct') and public.num(p, 'pct', 'Porcentaje') is null then
      raise exception 'Poné el porcentaje de descuento' using errcode = '22023';
    end if;
    v_paga := case when v_tipo = 'lleva_paga' then public.num(p, 'paga', 'Paga') end;
    v_pct := case when v_tipo in ('unidad_pct', 'desde_pct') then public.num(p, 'pct', 'Porcentaje') end;
    v_precio := case when v_tipo = 'precio' then round(public.num(p, 'precio', 'Precio'), 2) end;
    if v_tipo = 'lleva_paga' and (v_paga is null or v_paga < 1 or v_paga >= v_n) then
      raise exception 'En "lleva N, paga M", M tiene que ser menor que N' using errcode = '22023';
    end if;
    if v_tipo in ('lleva_paga', 'precio', 'unidad_pct') and v_n < 2 then raise exception 'La cantidad tiene que ser 2 o más' using errcode = '22023'; end if;
    if v_pct is not null and (v_pct < 1 or v_pct > 100 or public.num(p, 'pct', 'Porcentaje') <> v_pct) then
      raise exception 'El porcentaje tiene que ser un número entero entre 1 y 100' using errcode = '22023';
    end if;
  end if;
  if (select count(*) from public.productos where negocio_id = v_neg and id = any (v_prods)) <> cardinality(v_prods) then
    raise exception 'Producto no encontrado' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.productos where id = any (v_prods) and por_peso) then
    raise exception 'Las promociones son de productos por unidad (no por kilo)' using errcode = '22023';
  end if;
  v_dias := array(select distinct x::smallint from jsonb_array_elements_text(coalesce(p -> 'dias', '[]')) x order by 1);
  v_formas := array(select distinct left(btrim(x), 40) from jsonb_array_elements_text(coalesce(p -> 'formas', '[]')) x where btrim(x) <> '');
  if nullif(p ->> 'hasta', '')::date < nullif(p ->> 'desde', '')::date then
    raise exception 'La fecha "hasta" es anterior a "desde"' using errcode = '22023';
  end if;
  if v_id is null then
    insert into public.promociones (negocio_id, nombre, tipo, cantidad, paga, pct, precio, productos, componentes, desde, hasta, dias, formas, activa)
      values (v_neg, btrim(coalesce(p ->> 'nombre', '')), v_tipo, v_n, v_paga, v_pct, v_precio, v_prods, v_comps,
              nullif(p ->> 'desde', '')::date, nullif(p ->> 'hasta', '')::date, v_dias, v_formas, coalesce((p ->> 'activa')::boolean, true))
      returning * into r;
  else
    update public.promociones set nombre = btrim(coalesce(p ->> 'nombre', '')), tipo = v_tipo, cantidad = v_n, paga = v_paga, pct = v_pct,
        precio = v_precio, productos = v_prods, componentes = v_comps, desde = nullif(p ->> 'desde', '')::date, hasta = nullif(p ->> 'hasta', '')::date,
        dias = v_dias, formas = v_formas, activa = coalesce((p ->> 'activa')::boolean, true)
      where id = v_id and negocio_id = v_neg returning * into r;
    if not found then raise exception 'Promoción no encontrada' using errcode = 'P0002'; end if;
  end if;
  return public.promo_json(r);
end;
$$;

revoke all on function public.promo_combo(public.promociones, jsonb, int[]) from public, anon, authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 40, 'hora', now());
$$;
