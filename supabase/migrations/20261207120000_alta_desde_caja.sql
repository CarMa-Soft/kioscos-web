-- =====================================================================
-- Alta rápida desde caja: un producto que pasa por caja y no está cargado se crea ahí mismo con lo mínimo
-- (nombre, código y precio) y queda "a revisar": el dueño completa después en Productos el costo, la categoría
-- y el stock real. Mientras tanto su stock no se cuenta para Pedidos.
-- "Varios" (venta sin producto) se puede desactivar por negocio (config 'varios' = false).
-- =====================================================================
alter table public.productos add column a_revisar boolean not null default false;
create index productos_a_revisar on public.productos (negocio_id) where a_revisar;

create or replace function public.producto_json(p public.productos, p_costo boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'codigo', p.codigo, 'categoria_id', p.categoria_id,
    'precio', p.precio, 'stock', p.stock, 'stock_min', p.stock_min, 'por_peso', p.por_peso, 'plu', p.plu,
    'favorito', p.favorito, 'activo', p.activo, 'actualizado', p.actualizado, 'proveedor_id', p.proveedor_id, 'margen', p.margen, 'a_revisar', p.a_revisar,
    'codigos', coalesce((select jsonb_agg(c.codigo order by c.id) from public.producto_codigos c where c.producto_id = p.id), '[]'::jsonb))
    || case when p_costo then jsonb_build_object('costo', p.costo) else '{}'::jsonb end;
$$;

-- Cualquier usuario (también el empleado, para no trabar la caja). p: { nombre, codigo, precio }
create or replace function public.alta_desde_caja(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario();
  v_codigo text := nullif(btrim(coalesce(p ->> 'codigo', '')), '');
  v_nombre text := left(btrim(coalesce(p ->> 'nombre', '')), 120);
  v_precio numeric := round(public.num(p, 'precio', 'Precio'), 2);
  v_otro text; r public.productos;
begin
  if v_precio is null or v_precio <= 0 then raise exception 'Poné el precio' using errcode = '22023'; end if;
  if v_codigo is not null and v_codigo !~ '^\S{1,40}$' then
    raise exception 'El código no puede tener espacios ni pasar de 40 caracteres' using errcode = '22023';
  end if;
  if v_codigo is not null then
    v_otro := coalesce((select nombre from public.productos where negocio_id = v_neg and lower(codigo) = lower(v_codigo) limit 1),
      (select pr.nombre from public.producto_codigos c join public.productos pr on pr.id = c.producto_id
        where c.negocio_id = v_neg and lower(c.codigo) = lower(v_codigo) limit 1));
    if v_otro is not null then raise exception 'El código % ya lo tiene "%"', v_codigo, v_otro using errcode = '23505'; end if;
  end if;
  if v_nombre = '' then v_nombre := case when v_codigo is null then 'Producto sin nombre' else 'Producto ' || v_codigo end; end if;
  if (select count(*) from public.productos where negocio_id = v_neg and a_revisar) >= 500 then
    raise exception 'Hay 500 productos creados en caja sin revisar: revisalos en Productos antes de crear más' using errcode = 'P0001';
  end if;
  insert into public.productos (negocio_id, nombre, codigo, precio, a_revisar) values (v_neg, v_nombre, v_codigo, v_precio, true)
    returning * into r;
  return public.producto_json(r, public.es_admin());
end;
$$;

create or replace function public.guardar_producto(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin();
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_nombre text := btrim(coalesce(p ->> 'nombre', ''));
  v_codigo text := nullif(btrim(coalesce(p ->> 'codigo', '')), '');
  v_plu text := nullif(btrim(coalesce(p ->> 'plu', '')), '');
  v_cat bigint := nullif(p ->> 'categoria_id', '')::bigint;
  v_stock numeric := round(public.num(p, 'stock', 'Stock'), 3);
  v_otro text; v_actual public.productos; r public.productos;
begin
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if v_codigo is not null and v_codigo ~ '\s' then raise exception 'El código no puede tener espacios' using errcode = '22023'; end if;
  if v_plu is not null and v_plu !~ '^\d{1,6}$' then raise exception 'El código de balanza tiene que ser de 1 a 6 números' using errcode = '22023'; end if;
  if v_cat is not null and not exists (select 1 from public.categorias where id = v_cat and negocio_id = v_neg) then
    raise exception 'Categoría no encontrada' using errcode = 'P0002';
  end if;
  if v_codigo is not null then
    select nombre into v_otro from public.productos where negocio_id = v_neg and lower(codigo) = lower(v_codigo) and id is distinct from v_id;
    if v_otro is not null then raise exception 'El código % ya lo tiene "%"', v_codigo, v_otro using errcode = '23505'; end if;
  end if;
  if v_plu is not null and exists (select 1 from public.productos where negocio_id = v_neg and plu = v_plu and id is distinct from v_id) then
    raise exception 'El código de balanza % ya está usado', v_plu using errcode = '23505';
  end if;

  if v_id is null then
    insert into public.productos (negocio_id, nombre, codigo, categoria_id, costo, precio, stock, stock_min, por_peso, plu, favorito)
    values (v_neg, v_nombre, v_codigo, v_cat,
      coalesce(round(public.num(p, 'costo', 'Costo'), 2), 0), coalesce(round(public.num(p, 'precio', 'Precio'), 2), 0),
      coalesce(v_stock, 0), coalesce(round(public.num(p, 'stock_min', 'Stock mínimo'), 3), 0),
      coalesce((p ->> 'por_peso')::boolean, false), v_plu, coalesce((p ->> 'favorito')::boolean, false))
    returning * into r;
    if coalesce(v_stock, 0) <> 0 then
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, r.id, v_stock, 'Stock inicial', v_u);
    end if;
  else
    select * into v_actual from public.productos where id = v_id and negocio_id = v_neg for update;
    if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
    update public.productos set nombre = v_nombre, codigo = v_codigo, categoria_id = v_cat,
        costo = coalesce(round(public.num(p, 'costo', 'Costo'), 2), costo), precio = coalesce(round(public.num(p, 'precio', 'Precio'), 2), precio),
        stock = coalesce(v_stock, stock), stock_min = coalesce(round(public.num(p, 'stock_min', 'Stock mínimo'), 3), stock_min),
        por_peso = coalesce((p ->> 'por_peso')::boolean, por_peso), plu = v_plu,
        favorito = coalesce((p ->> 'favorito')::boolean, favorito), activo = coalesce((p ->> 'activo')::boolean, activo),
        a_revisar = false   -- el dueño lo revisó y lo guardó desde la ficha
      where id = v_id returning * into r;
    if v_stock is not null and v_stock <> v_actual.stock then
      insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id)
        values (v_neg, r.id, v_stock - v_actual.stock, 'Corrección desde la ficha', v_u);
    end if;
  end if;
  return public.producto_json(r, true);
end;
$$;

create or replace function public.pedidos()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_items jsonb;
begin
  perform public.requiere_admin();
  -- lo guardado de productos que ya no hace falta pedir (o dados de baja) se limpia
  delete from public.pedido_items pi using public.productos pr
    where pi.negocio_id = v_neg and pr.id = pi.producto_id and (not pr.activo or pr.stock - public.comprometido(pr.id) > greatest(pr.stock_min, 0));
  with faltan as (
    select pr.*, public.comprometido(pr.id) as comprometido, coalesce(pr.proveedor_id, (select pp.proveedor_id from public.producto_proveedores pp
                    where pp.producto_id = pr.id order by pp.ultima_compra desc nulls last limit 1)) as prov
    from public.productos pr
    where pr.negocio_id = v_neg and pr.activo and not pr.a_revisar   -- los creados en caja: su stock todavía no se contó
      and pr.stock - public.comprometido(pr.id) <= greatest(pr.stock_min, 0)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'producto_id', f.id, 'nombre', f.nombre, 'codigo', f.codigo, 'codigo_proveedor', pp.codigo_proveedor, 'por_peso', f.por_peso,
      'stock', f.stock, 'stock_min', f.stock_min, 'sin_stock', f.stock <= 0,
      'propuesta', public.cantidad_propuesta(f.stock - f.comprometido, f.stock_min, f.por_peso),
      'cantidad', coalesce(pi.cantidad, public.cantidad_propuesta(f.stock - f.comprometido, f.stock_min, f.por_peso)),
      'pendiente', coalesce(pi.pendiente, false),
      'para_entregar', f.comprometido,
      'entregas', (select string_agg(trim_scale(e.cantidad)::text || ' a ' || e.a_nombre || ' (venta #' || vv.numero || ')', ', ' order by e.id)
                   from public.entregas_pendientes e join public.ventas vv on vv.id = e.venta_id where e.producto_id = f.id and e.estado = 'pendiente'),
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

-- Reportes: cuánto se vendió como "Varios"
create or replace function public.reporte(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_tz text; v_d1 timestamptz; v_d2 timestamptz; r jsonb;
begin
  perform public.requiere_admin();
  if p_desde is null or p_hasta is null or p_hasta < p_desde then raise exception 'Rango de fechas inválido' using errcode = '22023'; end if;
  if p_hasta - p_desde > 400 then raise exception 'El período no puede pasar de 400 días' using errcode = '22023'; end if;
  v_tz := public.zona_horaria(v_neg);
  v_d1 := p_desde::timestamp at time zone v_tz;
  v_d2 := (p_hasta + 1)::timestamp at time zone v_tz;

  with
  vs as (select * from public.ventas where negocio_id = v_neg and not anulada and fecha >= v_d1 and fecha < v_d2),
  ds as (select dv.*, vv.usuario_id as vendedor from public.devoluciones dv join public.ventas vv on vv.id = dv.venta_id
         where dv.negocio_id = v_neg and not vv.anulada and dv.fecha >= v_d1 and dv.fecha < v_d2),
  vis as (select i.*, case when vs.subtotal > 0 then i.importe * vs.total / vs.subtotal else i.importe end as imp
          from public.venta_items i join vs on vs.id = i.venta_id),
  dis as (select x.*, case when x.vuelve_stock then x.cantidad * x.costo else 0 end as costo_rec
          from public.devolucion_items x join ds on ds.id = x.devolucion_id),
  -- ventas (+) y devoluciones (−) juntas, para agrupar
  mov as (select fecha, total, usuario_id as vendedor from vs union all select fecha, -total, vendedor from ds)
  select jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'tickets', (select count(*) from vs),
    -- lo vendido como "Varios" (sin producto): para ver si se está usando de más
    'varios', jsonb_build_object('importe', round((select coalesce(sum(imp), 0) from vis where producto_id is null), 2),
      'renglones', (select count(*) from vis where producto_id is null)),
    'vendido', (select coalesce(sum(total), 0) from vs),
    'total', (select coalesce(sum(total), 0) from mov),
    'costo', round((select coalesce(sum(cantidad * costo), 0) from vis) - (select coalesce(sum(costo_rec), 0) from dis), 2),
    'devoluciones', jsonb_build_object('total', (select coalesce(sum(total), 0) from ds), 'cantidad', (select count(*) from ds),
      'perdidas', round((select coalesce(sum(cantidad * costo), 0) from dis where not vuelve_stock), 2)),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'total', t) order by dia), '[]'::jsonb)
                from (select (fecha at time zone v_tz)::date as dia, sum(total) as t from mov group by 1) x),
    'por_hora', (select coalesce(jsonb_agg(jsonb_build_object('hora', h, 'total', t) order by h), '[]'::jsonb)
                 from (select extract(hour from fecha at time zone v_tz)::int as h, sum(total) as t from mov group by 1) x),
    'por_forma', (select coalesce(jsonb_agg(jsonb_build_object('forma', forma, 'total', t) order by t desc), '[]'::jsonb)
                  from (select forma, sum(m) as t from (
                          select p.forma, p.monto as m from public.venta_pagos p join vs on vs.id = p.venta_id
                          union all select forma, -total from ds) y group by forma) x),
    'por_usuario', (select coalesce(jsonb_agg(jsonb_build_object('nombre', public.nombre_usuario(vendedor), 'total', t) order by t desc), '[]'::jsonb)
                    from (select vendedor, sum(total) as t from mov group by vendedor) x),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'por_peso', por_peso, 'cantidad', cantidad,
                    'importe', round(importe, 2), 'costo', round(costo, 2)) order by importe desc), '[]'::jsonb)
                  from (select max(nombre) as nombre, bool_or(por_peso) as por_peso, sum(c) as cantidad, sum(i) as importe, sum(k) as costo
                        from (select coalesce(producto_id::text, 'v:' || nombre) as clave, nombre, por_peso, cantidad as c, imp as i, cantidad * costo as k from vis
                              union all
                              select coalesce(producto_id::text, 'v:' || nombre), nombre, por_peso, -cantidad, -importe, -costo_rec from dis) y
                        group by clave order by sum(i) desc limit 100) x),
    'por_categoria', (select coalesce(jsonb_agg(jsonb_build_object('categoria', coalesce(c.nombre, 'Sin categoría'), 'importe', round(x.importe, 2),
                        'costo', round(x.costo, 2)) order by x.importe desc), '[]'::jsonb)
                      from (select categoria_id, sum(i) as importe, sum(k) as costo
                            from (select categoria_id, imp as i, cantidad * costo as k from vis
                                  union all select categoria_id, -importe, -costo_rec from dis) y group by categoria_id) x
                      left join public.categorias c on c.id = x.categoria_id),
    'descuentos', (select jsonb_build_object('general', coalesce(sum(descuento), 0), 'renglones', coalesce(sum(descuento_renglones), 0),
                     'recargo', coalesce(sum(recargo), 0),
                     'ventas_con_descuento', count(*) filter (where descuento > 0 or descuento_renglones > 0),
                     'autorizadas', count(*) filter (where autorizo_id is not null)) from vs),
    'recargos_por_forma', (select coalesce(jsonb_agg(jsonb_build_object('forma', forma, 'recargo', t) order by t desc), '[]'::jsonb)
                           from (select p.forma, sum(p.recargo) as t from public.venta_pagos p join vs on vs.id = p.venta_id
                                 where p.recargo > 0 group by p.forma) x),
    'descuentos_por_usuario', (select coalesce(jsonb_agg(jsonb_build_object('nombre', public.nombre_usuario(usuario_id), 'general', g, 'renglones', rg,
                                 'ventas', n) order by g + rg desc), '[]'::jsonb)
                               from (select usuario_id, sum(descuento) as g, sum(descuento_renglones) as rg, count(*) as n from vs
                                     where descuento > 0 or descuento_renglones > 0 group by usuario_id) x),
    'autorizaciones', (select coalesce(jsonb_agg(jsonb_build_object('numero', numero, 'fecha', fecha, 'vendio', public.nombre_usuario(usuario_id),
                         'autorizo', public.nombre_usuario(autorizo_id), 'descuento', descuento + descuento_renglones, 'subtotal', subtotal) order by id desc), '[]'::jsonb)
                       from (select * from vs where autorizo_id is not null order by id desc limit 100) x),
    'mercaderia', (select jsonb_build_object('costo', round(coalesce(sum(greatest(stock, 0) * costo), 0), 2),
                     'venta', round(coalesce(sum(greatest(stock, 0) * precio), 0), 2))
                   from public.productos where negocio_id = v_neg and activo),
    'fiado_pendiente', public.fiado_pendiente(v_neg)
  ) into r;
  return r;
end;
$$;

-- "Varios" desactivado en el negocio: la venta sin producto no se registra
create or replace function public.venta_items_varios()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.producto_id is null and (select c.valor from public.config c where c.negocio_id = new.negocio_id and c.clave = 'varios') = 'false'::jsonb then
    raise exception 'La venta como "Varios" está desactivada: creá el producto desde la caja' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger venta_items_varios before insert on public.venta_items for each row execute function public.venta_items_varios();

revoke all on function public.alta_desde_caja(jsonb), public.venta_items_varios() from public, anon, authenticated;
grant execute on function public.alta_desde_caja(jsonb) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 24, 'hora', now());
$$;
