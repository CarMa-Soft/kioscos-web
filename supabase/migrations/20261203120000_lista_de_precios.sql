-- =====================================================================
-- Lista de precios (Productos → Lista de precios, solo dueño): un listado legible para imprimir o etiquetar, filtrado por
-- los productos que llegaron en ciertas compras, los que cambiaron de precio desde una fecha, categoría o proveedor.
-- Para "cambiaron de precio" se lleva el historial de precios y costos de cada producto (cambios_precio), cargado por un
-- trigger desde cualquier lado (ficha, compra, aumento, factura). Lo de antes se completa con las compras que cambiaron
-- el precio y los aumentos que no se deshicieron.
-- =====================================================================

create table public.cambios_precio (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  producto_id bigint not null,
  fecha timestamptz not null default now(),
  precio_antes numeric(14, 2), precio_despues numeric(14, 2),
  costo_antes numeric(14, 2), costo_despues numeric(14, 2),
  foreign key (producto_id, negocio_id) references public.productos (id, negocio_id) on delete cascade
);
create index cambios_precio_producto on public.cambios_precio (producto_id, fecha);
create index cambios_precio_negocio on public.cambios_precio (negocio_id, fecha);
alter table public.cambios_precio enable row level security;
revoke all on public.cambios_precio from anon, authenticated;

create or replace function public.anotar_cambio_precio()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.precio is distinct from old.precio or new.costo is distinct from old.costo then
    insert into public.cambios_precio (negocio_id, producto_id, precio_antes, precio_despues, costo_antes, costo_despues)
      values (new.negocio_id, new.id, old.precio, new.precio, old.costo, new.costo);
  end if;
  return new;
end;
$$;
create trigger productos_cambio_precio after update of precio, costo on public.productos
  for each row execute function public.anotar_cambio_precio();

-- Lo que ya se sabía: compras que cambiaron el precio y aumentos vigentes
insert into public.cambios_precio (negocio_id, producto_id, fecha, precio_antes, precio_despues, costo_antes, costo_despues)
  select i.negocio_id, i.producto_id, c.fecha, i.precio_anterior, i.precio_nuevo, i.costo_anterior, i.costo
  from public.compra_items i join public.compras c on c.id = i.compra_id
  where not c.anulada and i.precio_nuevo is not null and i.precio_nuevo is distinct from i.precio_anterior;
insert into public.cambios_precio (negocio_id, producto_id, fecha, precio_antes, precio_despues, costo_antes, costo_despues)
  select x.negocio_id, x.producto_id, a.fecha, x.precio_antes, x.precio_despues, x.costo_antes, x.costo_despues
  from public.aumento_cambios x join public.aumentos a on a.id = x.aumento_id
  where not a.deshecho and x.precio_despues is distinct from x.precio_antes;

-- p: { categoria_id, proveedor_id, compra_ids: [id], compras_desde: fecha, precio_desde: fecha, texto }
-- Todo opcional; se combinan (y). Devuelve los productos activos con costo, precio y, si se filtró por precio, el
-- precio de antes del primer cambio desde esa fecha; si se filtró por compras, cuándo llegaron.
create or replace function public.lista_precios(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_tz text;
  v_cat bigint := nullif(p ->> 'categoria_id', '')::bigint; v_prov bigint := nullif(p ->> 'proveedor_id', '')::bigint;
  v_compras bigint[]; v_cdesde timestamptz; v_pdesde timestamptz;
  v_texto text := lower(btrim(coalesce(p ->> 'texto', '')));
begin
  perform public.requiere_admin();
  v_tz := public.zona_horaria(v_neg);
  if jsonb_typeof(p -> 'compra_ids') = 'array' and jsonb_array_length(p -> 'compra_ids') > 0 then
    select array_agg((x #>> '{}')::bigint) into v_compras from jsonb_array_elements(p -> 'compra_ids') x;
  end if;
  -- las fechas son días del negocio: desde el comienzo de ese día en su zona horaria
  if nullif(p ->> 'compras_desde', '') is not null then v_cdesde := ((p ->> 'compras_desde')::date)::timestamp at time zone v_tz; end if;
  if nullif(p ->> 'precio_desde', '') is not null then v_pdesde := ((p ->> 'precio_desde')::date)::timestamp at time zone v_tz; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre, 'codigo', x.codigo, 'por_peso', x.por_peso,
      'categoria', x.categoria, 'costo', x.costo, 'precio', x.precio, 'stock', x.stock,
      'precio_antes', x.precio_antes, 'cambio', x.cambio, 'llego', x.llego) order by lower(x.nombre))
    from (
      select pr.*, (select nombre from public.categorias where id = pr.categoria_id) as categoria,
        (select cp.precio_antes from public.cambios_precio cp where cp.producto_id = pr.id and cp.fecha >= v_pdesde
           and cp.precio_antes is distinct from cp.precio_despues order by cp.fecha, cp.id limit 1) as precio_antes,
        (select max(cp.fecha) from public.cambios_precio cp where cp.producto_id = pr.id and cp.fecha >= v_pdesde
           and cp.precio_antes is distinct from cp.precio_despues) as cambio,
        (select max(c.fecha) from public.compra_items i join public.compras c on c.id = i.compra_id
           where i.producto_id = pr.id and not c.anulada
             and (v_compras is null or c.id = any (v_compras)) and (v_cdesde is null or c.fecha >= v_cdesde)) as llego
      from public.productos pr
      where pr.negocio_id = v_neg and pr.activo
        and (v_cat is null or pr.categoria_id = v_cat)
        and (v_prov is null or pr.proveedor_id = v_prov
             or exists (select 1 from public.producto_proveedores pp where pp.producto_id = pr.id and pp.proveedor_id = v_prov))
        and (v_texto = '' or lower(pr.nombre) like '%' || v_texto || '%' or lower(coalesce(pr.codigo, '')) like '%' || v_texto || '%')
    ) x
    where (v_pdesde is null or x.cambio is not null)
      and (v_compras is null and v_cdesde is null or x.llego is not null)), '[]'::jsonb);
end;
$$;

revoke all on function public.anotar_cambio_precio(), public.lista_precios(jsonb) from public, anon, authenticated;
grant execute on function public.lista_precios(jsonb) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 20, 'hora', now());
$$;
