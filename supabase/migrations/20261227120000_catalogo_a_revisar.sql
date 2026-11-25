-- =====================================================================
-- Lo agregado desde el catálogo general sin costo o sin categoría queda "a revisar" (Productos → A revisar), como lo que se
-- crea en la caja: así el dueño se acuerda de completarlo. Al guardarlo desde la ficha deja de estarlo (guardar_producto).
-- =====================================================================
create or replace function public.agregar_desde_catalogo(p_items jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint; v_stock numeric; it jsonb; g public.catalogo_general; r public.productos; v_cat bigint; v_precio numeric;
  v_creados jsonb := '[]'; v_ya jsonb := '[]';
begin
  v_u := public.requiere_admin();
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Elegí los productos' using errcode = '22023'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'Se pueden agregar hasta 500 productos por vez' using errcode = '22023'; end if;
  for it in select value from jsonb_array_elements(p_items) loop
    select * into g from public.catalogo_general where codigo = it ->> 'codigo';
    if not found then raise exception 'El código % no está en el catálogo general', it ->> 'codigo' using errcode = 'P0002'; end if;
    v_precio := round(public.num(it, 'precio', 'Precio'), 2);
    if v_precio is null or v_precio < 0 then raise exception 'Falta el precio de "%"', g.nombre using errcode = '22023'; end if;
    v_stock := round(coalesce(public.num(it, 'stock', 'Stock'), 0), 3);
    if v_stock < 0 then raise exception 'El stock de "%" no puede ser negativo', g.nombre using errcode = '22023'; end if;
    if v_stock <> trunc(v_stock) then raise exception 'El stock de "%" tiene que ser entero', g.nombre using errcode = '22023'; end if;
    v_cat := nullif(it ->> 'categoria_id', '')::bigint;
    if it ->> 'categoria' = 'sugerida' then v_cat := public.categoria_por_nombre(v_neg, g.categoria, true); end if;
    if v_cat is not null and not exists (select 1 from public.categorias where id = v_cat and negocio_id = v_neg) then
      raise exception 'Categoría no encontrada' using errcode = 'P0002';
    end if;
    if (public.catalogo_general_json(g, v_neg) ->> 'ya')::boolean then v_ya := v_ya || to_jsonb(g.nombre); continue; end if;
    -- sin costo o sin categoría queda "a revisar" (Productos → A revisar), como lo creado en la caja
    insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, marca, contenido, unidad, stock, a_revisar)
      values (v_neg, left(g.nombre, 120), g.codigo, v_cat, coalesce(round(public.num(it, 'costo', 'Costo'), 2), 0), v_precio, g.marca, g.contenido, g.unidad, v_stock,
              coalesce(round(public.num(it, 'costo', 'Costo'), 2), 0) = 0 or v_cat is null)
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
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 44, 'hora', now());
$$;
