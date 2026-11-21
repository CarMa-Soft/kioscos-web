-- =====================================================================
-- Cambiar el precio desde la tabla de Productos (sin abrir la ficha). Solo el dueño. El precio que se pone manda: si el
-- producto tenía margen automático, queda con precio fijo (si no, el próximo costo lo volvería a cambiar). El historial de
-- precios lo anota el disparador de siempre (anotar_cambio_precio). El stock se cambia con ajustar_stock.
-- =====================================================================
create or replace function public.cambiar_precio(p_id bigint, p_precio numeric)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); r public.productos;
begin
  perform public.requiere_admin();
  if p_precio is null or p_precio < 0 then raise exception 'El precio no puede ser negativo' using errcode = '22023'; end if;
  select * into r from public.productos where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
  update public.productos set precio = round(p_precio, 2), margen = null where id = r.id returning * into r;
  return public.producto_json(r, true);
end;
$$;
revoke all on function public.cambiar_precio(bigint, numeric) from public, anon, authenticated;
grant execute on function public.cambiar_precio(bigint, numeric) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 35, 'hora', now());
$$;
