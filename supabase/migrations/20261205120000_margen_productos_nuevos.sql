-- =====================================================================
-- Margen automático para productos nuevos (Productos → Precios y márgenes → Configuración, antes en Ajustes)
-- config 'margen' (40 de fábrica; 0 = sin margen automático): los productos que se crean al cargar una compra desde la
-- factura quedan con ese margen automático (su precio sigue al costo). La pantalla hace lo mismo con el alta rápida en
-- la compra y con "Nuevo producto" (margen_producto). guardar_margen ya aceptaba 0.
-- =====================================================================

create or replace function public.registrar_compra_factura(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v_prov bigint; v_cuit text;
  l jsonb; k integer := 0; v_prod bigint; v_barras text; v_codigo text; v_unid numeric; v_items jsonb := '[]'::jsonb;
  v_creados integer := 0; v_ids jsonb := '[]'::jsonb; r jsonb; v_nuevos bigint[] := '{}';
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
      v_creados := v_creados + 1; v_nuevos := v_nuevos || v_prod;
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
  -- los nuevos quedan con el margen automático de la configuración (después de la compra: el precio que se eligió no cambia)
  update public.productos set margen = nullif(public.margen_precios(v_neg), 0) where id = any (v_nuevos) and costo > 0;
  return r || jsonb_build_object('creados', v_creados, 'productos', v_ids);
end;
$$;


create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 22, 'hora', now());
$$;
