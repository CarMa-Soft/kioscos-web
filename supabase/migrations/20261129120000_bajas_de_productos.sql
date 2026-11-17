-- Productos: eliminar solo los que no tienen movimientos (los demás quedan dados de baja) y poder ver los dados de baja
-- para volver a activarlos.

-- Un producto tiene movimientos si aparece en una venta, una devolución, una compra, una devolución a proveedor, una
-- entrada o salida, o un ajuste de stock. No cuentan "Stock inicial" ni "Corrección desde la ficha": los anota
-- guardar_producto al cargar o editar la ficha, y si contaran ningún producto se podría borrar, ni uno cargado por error.
create or replace function public.producto_con_movimientos(p_id bigint)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.venta_items where producto_id = p_id)
      or exists (select 1 from public.devolucion_items where producto_id = p_id)
      or exists (select 1 from public.compra_items where producto_id = p_id)
      or exists (select 1 from public.devolucion_compra_items where producto_id = p_id)
      or exists (select 1 from public.remito_items where producto_id = p_id)
      or exists (select 1 from public.movimientos_stock where producto_id = p_id
                   and motivo not in ('Stock inicial', 'Corrección desde la ficha'));
$$;
revoke all on function public.producto_con_movimientos(bigint) from public, anon, authenticated;

create or replace function public.eliminar_producto(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if not exists (select 1 from public.productos where id = p_id and negocio_id = v_neg) then
    raise exception 'Producto no encontrado' using errcode = 'P0002';
  end if;
  if public.producto_con_movimientos(p_id) then
    update public.productos set activo = false where id = p_id and negocio_id = v_neg;
    return jsonb_build_object('desactivado', true);
  end if;
  delete from public.productos where id = p_id and negocio_id = v_neg;
  return jsonb_build_object('eliminado', true);
end;
$$;

-- Los dados de baja (solo el dueño, con costos): el catálogo completo trae solo los activos.
create or replace function public.productos_de_baja()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return coalesce((select jsonb_agg(public.producto_json(p, true) order by lower(p.nombre))
                   from public.productos p where p.negocio_id = v_neg and not p.activo), '[]'::jsonb);
end;
$$;
revoke all on function public.productos_de_baja() from public, anon, authenticated;
grant execute on function public.productos_de_baja() to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 16, 'hora', now());
$$;
