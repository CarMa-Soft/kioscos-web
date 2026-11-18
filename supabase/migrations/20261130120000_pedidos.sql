-- =====================================================================
-- Pedidos a proveedores (solo dueño)
-- Los productos activos con stock bajo (stock ≤ mínimo) o sin stock (≤ 0) se arman solos en un pedido por proveedor: el
-- habitual del producto o, si no tiene, el último al que se le compró; si no, "sin proveedor". De cada uno se ve la
-- cantidad propuesta (hasta el doble del mínimo; sin mínimo, lo que falta para tener 1) y el último costo de ese proveedor.
-- - Cambiar el proveedor de un producto lo deja como su habitual (y pasa al pedido de ese proveedor).
-- - La cantidad se puede cambiar. Quitar un producto lo pasa a "Pendientes de pedir", de donde se lo vuelve al pedido.
-- - No hace falta marcar un pedido como recibido: cargar la compra borra lo que se guardó de esos productos (cantidad,
--   pendiente), y si con eso superan el mínimo ya no aparecen. Lo guardado de los que ya no hace falta pedir se limpia solo.
-- =====================================================================

create table public.pedido_items (
  negocio_id uuid not null,
  producto_id bigint not null,
  cantidad numeric(14, 3) check (cantidad > 0),   -- null = la propuesta
  pendiente boolean not null default false,       -- se quitó del pedido: queda en "Pendientes de pedir"
  actualizado timestamptz not null default now(),
  primary key (producto_id),
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete cascade
);
create index pedido_items_negocio on public.pedido_items (negocio_id);
alter table public.pedido_items enable row level security;
revoke all on public.pedido_items from anon, authenticated;

-- Al cargar una compra, lo guardado del pedido de esos productos se olvida
create or replace function public.olvidar_pedido_comprado()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.pedido_items where producto_id = new.producto_id;
  return new;
end;
$$;
create trigger compra_items_olvida_pedido after insert on public.compra_items for each row execute function public.olvidar_pedido_comprado();

-- Cantidad propuesta: hasta el doble del mínimo; sin mínimo, lo que falta para tener 1. Por kilo con 3 decimales; si no, entera.
create or replace function public.cantidad_propuesta(p_stock numeric, p_min numeric, p_por_peso boolean)
returns numeric language sql immutable set search_path = '' as $$
  select case when p_por_peso then round(x, 3) else ceil(x) end
  from (select greatest(case when p_min > 0 then 2 * p_min - p_stock else 1 - p_stock end, case when p_por_peso then 0.001 else 1 end) as x) t;
$$;

-- El pedido: { proveedores: [{ id, nombre, telefono, items }], sin_proveedor: [items], pendientes: [items] }
-- item: { producto_id, nombre, codigo, codigo_proveedor, por_peso, stock, stock_min, sin_stock, cantidad, propuesta,
--         ultimo_costo, ultima_compra, costo, proveedor_id }
create or replace function public.pedidos()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_items jsonb;
begin
  perform public.requiere_admin();
  -- lo guardado de productos que ya no hace falta pedir (o dados de baja) se limpia
  delete from public.pedido_items pi using public.productos pr
    where pi.negocio_id = v_neg and pr.id = pi.producto_id and (not pr.activo or pr.stock > greatest(pr.stock_min, 0));
  with faltan as (
    select pr.*, coalesce(pr.proveedor_id, (select pp.proveedor_id from public.producto_proveedores pp
                    where pp.producto_id = pr.id order by pp.ultima_compra desc nulls last limit 1)) as prov
    from public.productos pr
    where pr.negocio_id = v_neg and pr.activo and pr.stock <= greatest(pr.stock_min, 0)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'producto_id', f.id, 'nombre', f.nombre, 'codigo', f.codigo, 'codigo_proveedor', pp.codigo_proveedor, 'por_peso', f.por_peso,
      'stock', f.stock, 'stock_min', f.stock_min, 'sin_stock', f.stock <= 0,
      'propuesta', public.cantidad_propuesta(f.stock, f.stock_min, f.por_peso),
      'cantidad', coalesce(pi.cantidad, public.cantidad_propuesta(f.stock, f.stock_min, f.por_peso)),
      'pendiente', coalesce(pi.pendiente, false),
      'ultimo_costo', pp.ultimo_costo, 'ultima_compra', pp.ultima_compra, 'costo', f.costo, 'proveedor_id', f.prov,
      'proveedor', (select nombre from public.proveedores where id = f.prov))
    order by lower(f.nombre)), '[]'::jsonb) into v_items
  from faltan f
    left join public.producto_proveedores pp on pp.producto_id = f.id and pp.proveedor_id = f.prov
    left join public.pedido_items pi on pi.producto_id = f.id;
  return jsonb_build_object(
    'proveedores', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'telefono', p.telefono,
        'items', (select jsonb_agg(i) from jsonb_array_elements(v_items) i where (i ->> 'proveedor_id')::bigint = p.id and not (i ->> 'pendiente')::boolean))
      order by lower(p.nombre))
      from public.proveedores p where p.negocio_id = v_neg and exists (select 1 from jsonb_array_elements(v_items) i
        where (i ->> 'proveedor_id')::bigint = p.id and not (i ->> 'pendiente')::boolean)), '[]'::jsonb),
    'sin_proveedor', coalesce((select jsonb_agg(i) from jsonb_array_elements(v_items) i where i -> 'proveedor_id' = 'null'::jsonb and not (i ->> 'pendiente')::boolean), '[]'::jsonb),
    'pendientes', coalesce((select jsonb_agg(i) from jsonb_array_elements(v_items) i where (i ->> 'pendiente')::boolean), '[]'::jsonb),
    'negocio', (select nombre from public.negocios where id = v_neg));
end;
$$;

-- Producto del negocio, para las funciones de abajo
create or replace function public.requiere_producto(p_id bigint)
returns public.productos language plpgsql stable security definer set search_path = '' as $$
declare r public.productos;
begin
  select * into r from public.productos where id = p_id and negocio_id = public.requiere_negocio();
  if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
  return r;
end;
$$;

-- Cantidad a pedir (null o vacío = volver a la propuesta)
create or replace function public.pedido_cantidad(p_producto_id bigint, p_cantidad numeric)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare r public.productos;
begin
  perform public.requiere_admin();
  r := public.requiere_producto(p_producto_id);
  if p_cantidad is not null and p_cantidad <= 0 then raise exception 'La cantidad tiene que ser mayor a 0' using errcode = '22023'; end if;
  insert into public.pedido_items (negocio_id, producto_id, cantidad) values (r.negocio_id, r.id, round(p_cantidad, 3))
    on conflict (producto_id) do update set cantidad = excluded.cantidad, actualizado = now();
end;
$$;

-- Quitar del pedido (pasa a "Pendientes de pedir") o volver a ponerlo
create or replace function public.pedido_pendiente(p_producto_id bigint, p_pendiente boolean)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare r public.productos;
begin
  perform public.requiere_admin();
  r := public.requiere_producto(p_producto_id);
  insert into public.pedido_items (negocio_id, producto_id, pendiente) values (r.negocio_id, r.id, coalesce(p_pendiente, false))
    on conflict (producto_id) do update set pendiente = excluded.pendiente, actualizado = now();
end;
$$;

-- Cambiar el proveedor: queda como el habitual del producto (y lo saca de "Pendientes de pedir")
create or replace function public.pedido_proveedor(p_producto_id bigint, p_proveedor_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare r public.productos;
begin
  perform public.requiere_admin();
  r := public.requiere_producto(p_producto_id);
  perform public.requiere_proveedor(p_proveedor_id);
  update public.productos set proveedor_id = p_proveedor_id where id = r.id;
  update public.pedido_items set pendiente = false, actualizado = now() where producto_id = r.id;
end;
$$;

revoke all on function public.olvidar_pedido_comprado(), public.cantidad_propuesta(numeric, numeric, boolean), public.pedidos(),
  public.requiere_producto(bigint), public.pedido_cantidad(bigint, numeric), public.pedido_pendiente(bigint, boolean),
  public.pedido_proveedor(bigint, bigint) from public, anon, authenticated;
grant execute on function public.pedidos(), public.pedido_cantidad(bigint, numeric), public.pedido_pendiente(bigint, boolean),
  public.pedido_proveedor(bigint, bigint) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 17, 'hora', now());
$$;
