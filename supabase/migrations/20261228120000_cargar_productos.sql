-- =====================================================================
-- Cargar productos (una sola pantalla para recorrer la góndola): en la misma lista van los del catálogo general y los que no
-- están en él (productos propios). agregar_desde_catalogo acepta items { "nuevo": true, "nombre", "codigo", "precio", "costo",
-- "stock", "categoria_id" }: se crean como en la ficha, con el stock inicial, y "a revisar" si les falta costo o categoría.
-- =====================================================================
create or replace function public.agregar_desde_catalogo(p_items jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint; v_stock numeric; it jsonb; g public.catalogo_general; r public.productos; v_cat bigint; v_precio numeric;
  v_nombre text; v_codigo text; v_otro text; v_costo numeric;
  v_creados jsonb := '[]'; v_ya jsonb := '[]';
begin
  v_u := public.requiere_admin();
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Elegí los productos' using errcode = '22023'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'Se pueden agregar hasta 500 productos por vez' using errcode = '22023'; end if;
  for it in select value from jsonb_array_elements(p_items) loop
    g := null;
    if coalesce((it ->> 'nuevo')::boolean, false) then
      -- producto propio (no está en el catálogo general)
      v_nombre := left(btrim(coalesce(it ->> 'nombre', '')), 120);
      if v_nombre = '' then raise exception 'Falta el nombre de un producto nuevo' using errcode = '22023'; end if;
      v_codigo := nullif(btrim(coalesce(it ->> 'codigo', '')), '');
      if v_codigo is not null and v_codigo ~ '\s' then raise exception 'El código de "%" no puede tener espacios', v_nombre using errcode = '22023'; end if;
      if v_codigo is not null then
        select nombre into v_otro from (
          select p.nombre from public.productos p where p.negocio_id = v_neg and lower(p.codigo) = any (public.codigo_variantes(lower(v_codigo)))
          union all
          select p.nombre from public.producto_codigos c join public.productos p on p.id = c.producto_id
            where c.negocio_id = v_neg and lower(c.codigo) = any (public.codigo_variantes(lower(v_codigo)))) x limit 1;
        if v_otro is not null then raise exception 'El código % ya lo tiene "%"', v_codigo, v_otro using errcode = '23505'; end if;
      end if;
    else
      select * into g from public.catalogo_general where codigo = it ->> 'codigo';
      if not found then raise exception 'El código % no está en el catálogo general', it ->> 'codigo' using errcode = 'P0002'; end if;
      v_nombre := left(g.nombre, 120); v_codigo := g.codigo;
    end if;
    v_precio := round(public.num(it, 'precio', 'Precio'), 2);
    if v_precio is null or v_precio < 0 then raise exception 'Falta el precio de "%"', v_nombre using errcode = '22023'; end if;
    v_costo := coalesce(round(public.num(it, 'costo', 'Costo'), 2), 0);
    if v_costo < 0 then raise exception 'El costo de "%" no puede ser negativo', v_nombre using errcode = '22023'; end if;
    v_stock := round(coalesce(public.num(it, 'stock', 'Stock'), 0), 3);
    if v_stock < 0 then raise exception 'El stock de "%" no puede ser negativo', v_nombre using errcode = '22023'; end if;
    if v_stock <> trunc(v_stock) then raise exception 'El stock de "%" tiene que ser entero', v_nombre using errcode = '22023'; end if;
    v_cat := nullif(it ->> 'categoria_id', '')::bigint;
    if g.codigo is not null and it ->> 'categoria' = 'sugerida' then v_cat := public.categoria_por_nombre(v_neg, g.categoria, true); end if;
    if v_cat is not null and not exists (select 1 from public.categorias where id = v_cat and negocio_id = v_neg) then
      raise exception 'Categoría no encontrada' using errcode = 'P0002';
    end if;
    if g.codigo is not null and (public.catalogo_general_json(g, v_neg) ->> 'ya')::boolean then v_ya := v_ya || to_jsonb(g.nombre); continue; end if;
    -- sin costo o sin categoría queda "a revisar" (Productos → A revisar), como lo creado en la caja
    insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, marca, contenido, unidad, stock, a_revisar)
      values (v_neg, v_nombre, v_codigo, v_cat, v_costo, v_precio, g.marca, g.contenido, g.unidad, v_stock, v_costo = 0 or v_cat is null)
      returning * into r;
    -- el stock que ya hay en el local, como al crear un producto desde la ficha
    if v_stock <> 0 then
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, r.id, v_stock, 'Stock inicial', v_u);
    end if;
    v_creados := v_creados || public.producto_json(r, true);
  end loop;
  return jsonb_build_object('creados', jsonb_array_length(v_creados), 'ya', v_ya, 'productos', v_creados);
end;
$$;


create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 45, 'hora', now());
$$;
