-- =====================================================================
-- Importar productos desde una planilla (Excel o CSV), para arrancar sin cargar uno por uno. Solo el dueño.
-- p_filas: [{ fila, nombre, codigo, precio, costo, stock, categoria }] (la pantalla ya leyó la planilla y armó esto; hasta 2000
-- por llamada). Cada fila:
--   · si el código ya es de un producto (principal o alternativo), o no trae código y el nombre ya existe: es ese producto.
--     Con p_actualizar, se le pone el precio y el costo de la planilla (y la categoría, si trae); el precio de la planilla
--     manda, así que deja de tener margen automático. El stock no se toca (para eso, Entradas y salidas o la ficha).
--     Sin p_actualizar, se saltea.
--   · si no: se crea (con su stock inicial, como al cargarlo a mano).
-- La categoría se busca por nombre y, si no existe, se crea. Una fila con error no corta las demás: vuelve en 'errores'.
-- =====================================================================
create or replace function public.importar_productos(p_filas jsonb, p_actualizar boolean default true)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin();
  f jsonb; v_fila int; v_nombre text; v_codigo text; v_precio numeric; v_costo numeric; v_stock numeric; v_cat_nombre text;
  v_cat bigint; v_id bigint; r public.productos;
  v_creados int := 0; v_actualizados int := 0; v_salteados int := 0; v_errores jsonb := '[]';
begin
  if jsonb_typeof(p_filas) <> 'array' then raise exception 'Faltan las filas' using errcode = '22023'; end if;
  if jsonb_array_length(p_filas) > 2000 then raise exception 'Son muchas filas juntas: de a 2000 como máximo' using errcode = '22023'; end if;
  perform 1 from public.negocios where id = v_neg for update;
  for f in select * from jsonb_array_elements(p_filas) loop
    v_fila := coalesce(nullif(f ->> 'fila', '')::int, 0);
    begin
      v_nombre := left(btrim(regexp_replace(coalesce(f ->> 'nombre', ''), '\s+', ' ', 'g')), 120);
      v_codigo := nullif(regexp_replace(coalesce(f ->> 'codigo', ''), '\s', '', 'g'), '');
      if v_codigo is not null and length(v_codigo) > 40 then raise exception 'El código es demasiado largo'; end if;
      v_precio := round(public.num(f, 'precio', 'Precio'), 2);
      v_costo := round(public.num(f, 'costo', 'Costo'), 2);
      v_stock := round(public.num(f, 'stock', 'Stock'), 3);
      if v_precio < 0 or v_costo < 0 then raise exception 'El precio y el costo no pueden ser negativos'; end if;
      v_cat_nombre := nullif(left(btrim(coalesce(f ->> 'categoria', '')), 60), '');
      v_cat := null;
      if v_cat_nombre is not null then
        select id into v_cat from public.categorias where negocio_id = v_neg and lower(btrim(nombre)) = lower(v_cat_nombre);
        if v_cat is null then insert into public.categorias (negocio_id, nombre) values (v_neg, v_cat_nombre) returning id into v_cat; end if;
      end if;
      -- ¿ya existe?
      v_id := null;
      if v_codigo is not null then
        select id into v_id from public.productos where negocio_id = v_neg and lower(codigo) = lower(v_codigo);
        if v_id is null then select producto_id into v_id from public.producto_codigos where negocio_id = v_neg and lower(codigo) = lower(v_codigo); end if;
      elsif v_nombre <> '' then
        select id into v_id from public.productos where negocio_id = v_neg and lower(nombre) = lower(v_nombre) order by activo desc, id limit 1;
      end if;
      if v_id is not null then
        if not p_actualizar then v_salteados := v_salteados + 1; continue; end if;
        update public.productos set
            precio = coalesce(v_precio, precio), costo = coalesce(v_costo, costo),
            margen = case when v_precio is not null then null else margen end,
            categoria_id = coalesce(v_cat, categoria_id), actualizado = now()
          where id = v_id;
        v_actualizados := v_actualizados + 1;
      else
        if v_nombre = '' then raise exception 'Falta el nombre'; end if;
        if v_precio is null then raise exception 'Falta el precio'; end if;
        insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, stock)
          values (v_neg, v_nombre, v_codigo, v_cat, coalesce(v_costo, 0), v_precio, coalesce(v_stock, 0))
          returning * into r;
        if coalesce(v_stock, 0) <> 0 then
          insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, r.id, v_stock, 'Stock inicial', v_u);
        end if;
        v_creados := v_creados + 1;
      end if;
    exception when others then
      v_errores := v_errores || jsonb_build_object('fila', v_fila, 'nombre', v_nombre, 'motivo', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('creados', v_creados, 'actualizados', v_actualizados, 'salteados', v_salteados, 'errores', v_errores);
end;
$$;
revoke all on function public.importar_productos(jsonb, boolean) from public, anon, authenticated;
grant execute on function public.importar_productos(jsonb, boolean) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 31, 'hora', now());
$$;
