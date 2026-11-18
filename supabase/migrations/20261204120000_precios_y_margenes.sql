-- =====================================================================
-- Precios y márgenes (como en GScom): un producto puede tener margen automático (productos.margen). Si lo tiene, su
-- precio de venta sigue al costo: cada vez que cambia el costo (compra, factura, ficha, actualización) se recalcula
-- costo + margen, redondeado hacia arriba como diga Ajustes → Precios. Sin margen, el precio es fijo.
-- ajustar_precios(p) hace en bloque, sobre los productos elegidos:
--   - 'venta': sube o baja el precio de los de precio fijo (los de margen siguen al costo y no se tocan);
--   - 'costo': sube o baja el costo; los de margen recalculan su precio, los fijos lo mantienen;
--   - 'margen': calcula el precio con un margen y lo deja automático, o lo quita (precio fijo).
-- Todo queda en aumentos / aumento_cambios (ahora también con el margen de antes y después) y se puede deshacer.
-- =====================================================================

alter table public.productos add column margen numeric(7, 2) check (margen is null or margen between 0 and 1000);
alter table public.aumento_cambios add column margen_antes numeric(7, 2), add column margen_despues numeric(7, 2);

-- Precio con margen: costo + margen, redondeado hacia arriba al múltiplo de Ajustes
create or replace function public.precio_por_margen(p_neg uuid, p_costo numeric, p_margen numeric)
returns numeric language sql stable security definer set search_path = '' as $$
  select public.redondear_precio(p_costo * (1 + p_margen / 100), public.redondeo_precios(p_neg));
$$;

-- Si cambia el costo de un producto con margen y el precio no se cambió a mano en el mismo momento, el precio sigue al costo
create or replace function public.precio_sigue_costo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.margen is not null and new.costo is distinct from old.costo and new.costo > 0 and new.precio is not distinct from old.precio then
    new.precio := public.precio_por_margen(new.negocio_id, new.costo, new.margen);
  end if;
  return new;
end;
$$;
create trigger productos_precio_sigue_costo before update of costo on public.productos
  for each row execute function public.precio_sigue_costo();

create or replace function public.producto_json(p public.productos, p_costo boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'codigo', p.codigo, 'categoria_id', p.categoria_id,
    'precio', p.precio, 'stock', p.stock, 'stock_min', p.stock_min, 'por_peso', p.por_peso, 'plu', p.plu,
    'favorito', p.favorito, 'activo', p.activo, 'actualizado', p.actualizado, 'proveedor_id', p.proveedor_id, 'margen', p.margen,
    'codigos', coalesce((select jsonb_agg(c.codigo order by c.id) from public.producto_codigos c where c.producto_id = p.id), '[]'::jsonb))
    || case when p_costo then jsonb_build_object('costo', p.costo) else '{}'::jsonb end;
$$;

-- p: { ids: [id], que: 'venta' | 'costo' | 'margen', modo: 'pct' | 'monto', valor, redondeo (solo 'venta'; si no viene, el de
--      Ajustes), margen (solo 'margen'; null = quitar el margen), descripcion }
-- Devuelve { id (para deshacer), cantidad, saltados }. Saltea los que no cambian (sin costo, precio por margen en 'venta', etc.).
create or replace function public.ajustar_precios(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin();
  v_que text := coalesce(p ->> 'que', ''); v_modo text := coalesce(p ->> 'modo', '');
  v_valor numeric := public.num(p, 'valor', 'Valor'); v_margen numeric := public.num(p, 'margen', 'Margen');
  v_red numeric := coalesce(public.num(p, 'redondeo', 'Redondeo'), public.redondeo_precios(v_neg));
  v_ids bigint[]; v_id bigint; r public.productos; v_x numeric; v_precio numeric; v_costo numeric; v_mg numeric; v_n integer := 0;
begin
  if v_que not in ('venta', 'costo', 'margen') then raise exception 'Elegí qué se cambia' using errcode = '22023'; end if;
  if v_que <> 'margen' then
    if v_modo not in ('pct', 'monto') then raise exception 'Elegí si es un porcentaje o un monto' using errcode = '22023'; end if;
    if v_valor is null or v_valor = 0 then raise exception 'Poné cuánto se cambia' using errcode = '22023'; end if;
    if v_modo = 'pct' and (v_valor < -90 or v_valor > 500) then raise exception 'El porcentaje tiene que estar entre -90 y 500' using errcode = '22023'; end if;
  elsif v_margen is not null and (v_margen < 0 or v_margen > 1000) then
    raise exception 'El margen tiene que estar entre 0 y 1000' using errcode = '22023';
  end if;
  if v_red < 0 then raise exception 'Redondeo inválido' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'ids') is distinct from 'array' then raise exception 'No hay productos elegidos' using errcode = '22023'; end if;
  select array_agg(distinct (x #>> '{}')::bigint) into v_ids from jsonb_array_elements(p -> 'ids') x;
  if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'No hay productos elegidos' using errcode = '22023'; end if;
  if cardinality(v_ids) > 5000 then raise exception 'Demasiados productos de una vez' using errcode = '22023'; end if;

  insert into public.aumentos (negocio_id, usuario_id, descripcion)
    values (v_neg, v_u, coalesce(nullif(left(btrim(coalesce(p ->> 'descripcion', '')), 200), ''), 'Precios y márgenes')) returning id into v_id;
  for r in select * from public.productos where negocio_id = v_neg and activo and id = any (v_ids) order by id for update loop
    v_precio := r.precio; v_costo := r.costo; v_mg := r.margen;
    if v_que = 'venta' then
      if r.margen is not null or r.precio <= 0 then continue; end if;
      v_x := case when v_modo = 'pct' then r.precio * (1 + v_valor / 100) else r.precio + v_valor end;
      if v_x <= 0 then continue; end if;
      v_precio := public.redondear_precio(v_x, v_red);
    elsif v_que = 'costo' then
      if r.costo <= 0 then continue; end if;
      v_x := case when v_modo = 'pct' then r.costo * (1 + v_valor / 100) else r.costo + v_valor end;
      if v_x <= 0 then continue; end if;
      v_costo := round(v_x, 2);
      if r.margen is not null then v_precio := public.precio_por_margen(v_neg, v_costo, r.margen); end if;
    elsif v_margen is not null then
      if r.costo <= 0 then continue; end if;
      v_precio := public.precio_por_margen(v_neg, r.costo, v_margen); v_mg := v_margen;
    else
      if r.margen is null then continue; end if;
      v_mg := null;
    end if;
    insert into public.aumento_cambios (negocio_id, aumento_id, producto_id, precio_antes, costo_antes, precio_despues, costo_despues, margen_antes, margen_despues)
      values (v_neg, v_id, r.id, r.precio, r.costo, v_precio, v_costo, r.margen, v_mg);
    update public.productos set precio = v_precio, costo = v_costo, margen = v_mg where id = r.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Ninguno de estos productos cambia con esto' using errcode = 'P0001'; end if;
  return jsonb_build_object('id', v_id, 'cantidad', v_n, 'saltados', cardinality(v_ids) - v_n);
end;
$$;

-- El margen de un solo producto, desde su ficha (el precio ya se guardó con guardar_producto). null = precio fijo.
create or replace function public.margen_producto(p_id bigint, p_margen numeric)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r public.productos;
begin
  perform public.requiere_admin();
  r := public.requiere_producto(p_id);
  if p_margen is not null and (p_margen < 0 or p_margen > 1000) then raise exception 'El margen tiene que estar entre 0 y 1000' using errcode = '22023'; end if;
  update public.productos set margen = round(p_margen, 2) where id = r.id returning * into r;
  return public.producto_json(r, true);
end;
$$;

-- Deshacer: vuelven precio, costo y margen de antes, en los que no cambiaron después
create or replace function public.deshacer_aumento(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); a public.aumentos; v_total integer; v_rev integer;
begin
  select * into a from public.aumentos where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró el aumento' using errcode = 'P0002'; end if;
  if a.deshecho then raise exception 'Ese aumento ya se deshizo' using errcode = 'P0001'; end if;
  select count(*) into v_total from public.aumento_cambios where aumento_id = a.id;
  perform 1 from public.productos where id in (select producto_id from public.aumento_cambios where aumento_id = a.id) order by id for update;
  update public.productos pr set precio = c.precio_antes, costo = c.costo_antes, margen = c.margen_antes
    from public.aumento_cambios c
    where c.aumento_id = a.id and pr.id = c.producto_id and pr.precio = c.precio_despues and pr.costo = c.costo_despues
      and pr.margen is not distinct from c.margen_despues;
  get diagnostics v_rev = row_count;
  update public.aumentos set deshecho = true, deshecho_fecha = now(), deshecho_por = v_u where id = a.id;
  return jsonb_build_object('revertidos', v_rev, 'saltados', v_total - v_rev);
end;
$$;

revoke all on function public.precio_por_margen(uuid, numeric, numeric), public.precio_sigue_costo(), public.ajustar_precios(jsonb),
  public.margen_producto(bigint, numeric) from public, anon, authenticated;
grant execute on function public.ajustar_precios(jsonb), public.margen_producto(bigint, numeric) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 21, 'hora', now());
$$;
