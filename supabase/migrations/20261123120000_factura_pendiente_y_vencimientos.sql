-- =====================================================================
-- Etapa 5b: factura pendiente, fecha de factura y vencimiento, aplicación de pagos a facturas (como la app local, #4 y #31)
--
-- Factura pendiente: la mercadería llega sin factura; la compra suma el stock y queda pendiente (el número cargado es el
-- del remito). Después, "Agregar factura" pone el número, las fechas y corrige costos y precios SIN mover el stock.
-- Fechas: fecha_factura (la que importa) y vencimiento (por defecto fecha + plazo del proveedor); compras.fecha es
-- cuándo se registró. Sin factura todavía, el vencimiento se estima.
-- Aplicación (aplicaciones_prov): qué parte de cada crédito (pago, nota de crédito = ajuste que resta) cubre cada deuda
-- (una compra, o un ajuste que suma, como el saldo inicial). Siempre: pendiente de las deudas − libre de los créditos = saldo.
-- =====================================================================

alter table public.compras
  add column factura_pendiente boolean not null default false,
  add column remito text,
  add column factura_fecha timestamptz,                    -- cuándo se cargó la factura que llegó después
  add column factura_por bigint,
  add column fecha_factura date,
  add column vencimiento date,
  add foreign key (factura_por, negocio_id) references public.usuarios (id, negocio_id);
alter table public.compra_items add column costo_remito numeric(14, 2);   -- el costo que tenía antes de llegar la factura
alter table public.cc_prov add column vencimiento date;                  -- el de un saldo inicial / ajuste que suma

create table public.aplicaciones_prov (
  id bigint generated always as identity primary key,
  negocio_id uuid not null,
  proveedor_id bigint not null,
  credito_id bigint not null,                               -- pago o nota de crédito (cc_prov)
  compra_id bigint,                                         -- la deuda: una compra…
  deuda_id bigint,                                          -- …o un ajuste que suma (cc_prov)
  monto numeric(14, 2) not null check (monto > 0),
  fecha timestamptz not null default now(),
  usuario_id bigint,
  check ((compra_id is null) <> (deuda_id is null)),
  foreign key (proveedor_id, negocio_id) references public.proveedores (id, negocio_id),
  foreign key (credito_id, negocio_id) references public.cc_prov (id, negocio_id),
  foreign key (compra_id, negocio_id) references public.compras (id, negocio_id),
  foreign key (deuda_id, negocio_id) references public.cc_prov (id, negocio_id),
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index aplicaciones_prov_credito on public.aplicaciones_prov (credito_id);
create index aplicaciones_prov_compra on public.aplicaciones_prov (compra_id);
create index aplicaciones_prov_deuda on public.aplicaciones_prov (deuda_id);
alter table public.aplicaciones_prov enable row level security;
revoke all on public.aplicaciones_prov from anon, authenticated;

-- ---------------------------------------------------------------------
-- Deudas y créditos de un proveedor
-- ---------------------------------------------------------------------
create or replace function public.hoy_negocio(p_neg uuid)
returns date language sql stable security definer set search_path = '' as $$
  select (now() at time zone public.zona_horaria(p_neg))::date;
$$;

-- Deudas: compras no anuladas que dejaron movimientos en la cuenta, y ajustes que suman sin compra (saldo inicial)
create or replace function public.deudas_proveedor(p_proveedor bigint)
returns table (compra_id bigint, deuda_id bigint, comprobante text, remito text, factura_pendiente boolean, fecha_factura date,
               vencimiento date, fecha timestamptz, importe numeric, aplicado numeric, pendiente numeric)
language sql stable security definer set search_path = '' as $$
  with tz as (select public.zona_horaria(negocio_id) as z from public.proveedores where id = p_proveedor),
  d as (
    select c.id as compra_id, null::bigint as deuda_id, c.comprobante, c.remito, c.factura_pendiente,
      coalesce(c.fecha_factura, (c.fecha at time zone (select z from tz))::date) as fecha_factura,
      coalesce(c.vencimiento, c.fecha_factura, (c.fecha at time zone (select z from tz))::date) as vencimiento, c.fecha,
      (select coalesce(sum(m.monto), 0) from public.cc_prov m where m.compra_id = c.id and m.tipo in ('compra', 'ajuste')) as importe,
      (select coalesce(sum(a.monto), 0) from public.aplicaciones_prov a where a.compra_id = c.id) as aplicado
    from public.compras c
    where c.proveedor_id = p_proveedor and not c.anulada and exists (select 1 from public.cc_prov m where m.compra_id = c.id)
    union all
    select null, m.id, m.concepto, null, false, (m.fecha at time zone (select z from tz))::date,
      coalesce(m.vencimiento, (m.fecha at time zone (select z from tz))::date), m.fecha, m.monto,
      (select coalesce(sum(a.monto), 0) from public.aplicaciones_prov a where a.deuda_id = m.id)
    from public.cc_prov m where m.proveedor_id = p_proveedor and m.tipo = 'ajuste' and m.compra_id is null and m.monto > 0 and not m.anulado)
  select compra_id, deuda_id, comprobante, remito, factura_pendiente, fecha_factura, vencimiento, fecha, importe, aplicado, importe - aplicado
  from d order by vencimiento, fecha;
$$;

-- Créditos: pagos y notas de crédito (ajustes que restan sin compra), no anulados y de compras no anuladas
create or replace function public.creditos_proveedor(p_proveedor bigint)
returns table (id bigint, compra_id bigint, fecha timestamptz, importe numeric, aplicado numeric, libre numeric)
language sql stable security definer set search_path = '' as $$
  select m.id, m.compra_id, m.fecha, -m.monto,
    (select coalesce(sum(a.monto), 0) from public.aplicaciones_prov a where a.credito_id = m.id),
    -m.monto - (select coalesce(sum(a.monto), 0) from public.aplicaciones_prov a where a.credito_id = m.id)
  from public.cc_prov m
  where m.proveedor_id = p_proveedor and not m.anulado and m.monto < 0
    and (m.tipo = 'pago' or (m.tipo = 'ajuste' and m.compra_id is null))
    and (m.compra_id is null or not (select c.anulada from public.compras c where c.id = m.compra_id))
  order by m.id;
$$;

create or replace function public.aplicar(p_neg uuid, p_proveedor bigint, p_credito bigint, p_compra bigint, p_deuda bigint, p_monto numeric, p_usuario bigint)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.aplicaciones_prov (negocio_id, proveedor_id, credito_id, compra_id, deuda_id, monto, usuario_id)
  select p_neg, p_proveedor, p_credito, p_compra, p_deuda, round(p_monto, 2), p_usuario where round(p_monto, 2) > 0;
$$;

-- Reparte lo que hay sin aplicar: primero cada crédito que viene de una compra (pago con la caja) va a esa compra;
-- después, lo libre a las deudas que vencen primero
create or replace function public.aplicar_automatico(p_proveedor bigint, p_usuario bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := (select negocio_id from public.proveedores where id = p_proveedor); cr record; dd record; v_libre numeric; v_m numeric;
begin
  for cr in select * from public.creditos_proveedor(p_proveedor) where compra_id is not null and libre > 0.004 loop
    select * into dd from public.deudas_proveedor(p_proveedor) x where x.compra_id = cr.compra_id and x.pendiente > 0.004;
    if found then perform public.aplicar(v_neg, p_proveedor, cr.id, dd.compra_id, null, least(cr.libre, dd.pendiente), p_usuario); end if;
  end loop;
  for cr in select * from public.creditos_proveedor(p_proveedor) where libre > 0.004 loop
    v_libre := cr.libre;
    for dd in select * from public.deudas_proveedor(p_proveedor) where pendiente > 0.004 loop
      exit when v_libre <= 0.004;
      v_m := least(v_libre, dd.pendiente);
      perform public.aplicar(v_neg, p_proveedor, cr.id, dd.compra_id, dd.deuda_id, v_m, p_usuario);
      v_libre := v_libre - v_m;
    end loop;
  end loop;
end;
$$;

-- Aplica una lista pedida desde la pantalla ([{ compra_id | deuda_id, monto }]) con los créditos libres (el pago dado,
-- o los más viejos). Corta si una deuda no es del proveedor, si se pasa de lo pendiente o de lo que hay para aplicar.
create or replace function public.aplicar_lista(p_neg uuid, p_proveedor bigint, p_lista jsonb, p_credito bigint, p_usuario bigint)
returns numeric language plpgsql volatile security definer set search_path = '' as $$
declare x jsonb; dd record; v_m numeric; v_total numeric := 0; cr record; v_falta numeric; v_usar numeric;
begin
  if p_lista is null or jsonb_typeof(p_lista) <> 'array' then return 0; end if;
  for x in select value from jsonb_array_elements(p_lista) loop
    v_m := round(public.num(x, 'monto', 'Monto aplicado'), 2);
    if v_m is null or v_m <= 0 then continue; end if;
    select * into dd from public.deudas_proveedor(p_proveedor) d
      where (d.compra_id = nullif(x ->> 'compra_id', '')::bigint) or (d.deuda_id = nullif(x ->> 'deuda_id', '')::bigint);
    if not found then raise exception 'Hay una factura que no es de este proveedor' using errcode = 'P0002'; end if;
    if v_m > dd.pendiente + 0.004 then
      raise exception 'A % le quedan % por pagar', coalesce(nullif(dd.comprobante, ''), 'una factura'), dd.pendiente using errcode = '22023';
    end if;
    v_falta := v_m;
    for cr in select * from public.creditos_proveedor(p_proveedor) c where c.libre > 0.004 and (p_credito is null or c.id = p_credito) loop
      exit when v_falta <= 0.004;
      v_usar := least(cr.libre, v_falta);
      perform public.aplicar(p_neg, p_proveedor, cr.id, dd.compra_id, dd.deuda_id, v_usar, p_usuario);
      v_falta := v_falta - v_usar;
    end loop;
    if v_falta > 0.004 then
      raise exception '%', case when p_credito is null then 'No hay tanto a cuenta sin aplicar' else 'Lo aplicado a las facturas suma más que el pago' end
        using errcode = '22023';
    end if;
    v_total := v_total + v_m;
  end loop;
  return v_total;
end;
$$;

-- Si una compra quedó con más aplicado que su importe (la factura vino por menos), se libera lo que sobra
create or replace function public.recortar_aplicaciones(p_compra bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_sobra numeric; a record;
begin
  v_sobra := (select coalesce(sum(monto), 0) from public.aplicaciones_prov where compra_id = p_compra)
           - (select coalesce(sum(monto), 0) from public.cc_prov where compra_id = p_compra and tipo in ('compra', 'ajuste'));
  for a in select * from public.aplicaciones_prov where compra_id = p_compra order by id desc loop
    exit when v_sobra <= 0.004;
    if a.monto <= v_sobra + 0.004 then delete from public.aplicaciones_prov where id = a.id; v_sobra := v_sobra - a.monto;
    else update public.aplicaciones_prov set monto = round(a.monto - v_sobra, 2) where id = a.id; v_sobra := 0; end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Compras
-- ---------------------------------------------------------------------
create or replace function public.compra_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'fecha', c.fecha, 'proveedor_id', c.proveedor_id,
    'proveedor', (select p.nombre from public.proveedores p where p.id = c.proveedor_id),
    'comprobante', c.comprobante, 'remito', c.remito, 'factura_pendiente', c.factura_pendiente, 'fecha_factura', c.fecha_factura,
    'vencimiento', c.vencimiento, 'factura_fecha', c.factura_fecha, 'factura_por', case when c.factura_por is not null then public.nombre_usuario(c.factura_por) end,
    'notas', c.notas, 'total', c.total, 'pagada_caja', c.pagada_caja, 'forma', c.forma,
    'usuario', public.nombre_usuario(c.usuario_id), 'anulada', c.anulada, 'anulada_fecha', c.anulada_fecha,
    'anulada_por', case when c.anulada then public.nombre_usuario(c.anulada_por) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'costo', i.costo, 'costo_remito', i.costo_remito, 'precio_nuevo', i.precio_nuevo, 'costo_anterior', i.costo_anterior,
                         'precio_anterior', i.precio_anterior) order by i.id)
                       from public.compra_items i where i.compra_id = c.id), '[]'::jsonb))
  from public.compras c where c.id = p_id;
$$;

-- Igual que en 5a, más: factura_pendiente (el número es del remito), fecha_factura (por defecto hoy) y vencimiento
-- (por defecto fecha + plazo del proveedor). Pagada con la caja: el pago queda aplicado a esta compra.
create or replace function public.registrar_compra(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores; t public.turnos;
  c public.compras; it jsonb; x public.productos; v_cant numeric; v_costo numeric; v_precio numeric; v_suma numeric := 0; v_total numeric;
  v_forma text := ''; v_concepto text; v_pago bigint; v_prov bigint := nullif(p ->> 'proveedor_id', '')::bigint;
  v_pend boolean := coalesce((p ->> 'factura_pendiente')::boolean, false); v_ff date; v_venc date; v_nro text;
begin
  perform 1 from public.negocios where id = v_neg for update;
  if v_prov is not null then r := public.requiere_proveedor(v_prov); end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' or jsonb_array_length(p -> 'items') = 0 then
    raise exception 'La compra no tiene productos' using errcode = '22023';
  end if;
  if coalesce((p ->> 'pagar_caja')::boolean, false) then
    v_forma := coalesce(nullif(p ->> 'forma', ''), 'Efectivo');
    if not (v_forma = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    t := public.requiere_turno();
  end if;
  begin
    v_ff := case when v_pend then null else coalesce(nullif(p ->> 'fecha_factura', '')::date, public.hoy_negocio(v_neg)) end;
    v_venc := coalesce(nullif(p ->> 'vencimiento', '')::date, coalesce(v_ff, public.hoy_negocio(v_neg)) + coalesce(r.plazo, 0));
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'Revisá las fechas' using errcode = '22023';
  end;
  v_nro := left(btrim(coalesce(p ->> 'comprobante', '')), 60);
  insert into public.compras (negocio_id, proveedor_id, comprobante, remito, factura_pendiente, fecha_factura, vencimiento, notas, total, pagada_caja, forma, usuario_id, turno_id)
    values (v_neg, r.id, case when v_pend then '' else v_nro end, case when v_pend then nullif(v_nro, '') end, v_pend, v_ff, v_venc,
            nullif(left(btrim(coalesce(p ->> 'notas', '')), 300), ''), 0, t.id is not null, v_forma, v_u, t.id)
    returning * into c;
  v_concepto := 'Compra' || coalesce(' a ' || r.nombre, '') || case when v_nro <> '' then ' (' || case when v_pend then 'remito ' else '' end || v_nro || ')' else '' end;

  for it in select value from jsonb_array_elements(p -> 'items') loop
    select * into x from public.productos where id = nullif(it ->> 'producto_id', '')::bigint and negocio_id = v_neg for update;
    if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
    v_cant := round(public.num(it, 'cantidad', 'Cantidad de ' || x.nombre), 3);
    if v_cant is null or v_cant <= 0 then raise exception 'Cantidad en 0 en %', x.nombre using errcode = '22023'; end if;
    v_costo := round(coalesce(public.num(it, 'costo', 'Costo de ' || x.nombre), 0), 2);
    if v_costo < 0 then raise exception 'El costo de % no puede ser negativo', x.nombre using errcode = '22023'; end if;
    v_precio := round(public.num(it, 'precio_nuevo', 'Precio de ' || x.nombre), 2);
    if v_precio < 0 then raise exception 'El precio de % no puede ser negativo', x.nombre using errcode = '22023'; end if;
    insert into public.compra_items (negocio_id, compra_id, producto_id, nombre, cantidad, costo, precio_nuevo, costo_anterior, precio_anterior)
      values (v_neg, c.id, x.id, x.nombre, v_cant, v_costo, v_precio, x.costo, x.precio);
    update public.productos set stock = stock + v_cant, costo = case when v_costo > 0 then v_costo else costo end,
        precio = coalesce(v_precio, precio), proveedor_id = coalesce(proveedor_id, r.id)
      where id = x.id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, x.id, v_cant, v_concepto, v_u);
    if r.id is not null then
      insert into public.producto_proveedores (negocio_id, producto_id, proveedor_id, ultimo_costo, ultima_compra)
        values (v_neg, x.id, r.id, nullif(v_costo, 0), now())
        on conflict (producto_id, proveedor_id) do update set ultimo_costo = coalesce(excluded.ultimo_costo, public.producto_proveedores.ultimo_costo),
          ultima_compra = excluded.ultima_compra;
    end if;
    v_suma := v_suma + round(v_cant * v_costo, 2);
  end loop;
  v_total := round(coalesce(public.num(p, 'total', 'Total'), v_suma), 2);
  if v_total < 0 then raise exception 'El total no puede ser negativo' using errcode = '22023'; end if;
  update public.compras set total = v_total where id = c.id;

  if t.id is not null and v_total > 0 then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, compra_id)
      values (v_neg, t.id, v_u, 'egreso', v_concepto, v_total, v_forma, c.id);
  end if;
  if r.id is not null and v_total > 0 then
    insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
      values (v_neg, r.id, 'compra', v_total, 'Compra' || case when v_nro <> '' then ' ' || case when v_pend then 'remito ' else '' end || v_nro else '' end, c.id, v_u);
    if t.id is not null then
      insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, compra_id, turno_id, usuario_id)
        values (v_neg, r.id, 'pago', -v_total, 'Pagada con la caja', v_forma, true, c.id, t.id, v_u) returning id into v_pago;
      perform public.aplicar(v_neg, r.id, v_pago, c.id, null, v_total, v_u);
    end if;
  end if;
  return public.compra_json(c.id);
end;
$$;

-- Agregar la factura a una compra pendiente: número, fechas, costos y precios. NO mueve el stock.
-- p: { id, comprobante, fecha_factura?, vencimiento?, total?, notas?, items: [{ id (renglón), costo, precio_nuevo? }] }
-- El costo del producto cambia solo si esta es su compra más reciente. Si el total cambió, la diferencia va a la cuenta.
create or replace function public.cargar_factura_compra(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); c public.compras; x jsonb; i public.compra_items;
  v_costo numeric; v_precio numeric; v_total numeric; v_dif numeric; v_ff date; v_venc date; v_plazo integer; v_nro text := left(btrim(coalesce(p ->> 'comprobante', '')), 60);
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into c from public.compras where id = nullif(p ->> 'id', '')::bigint and negocio_id = v_neg for update;
  if not found then raise exception 'Compra no encontrada' using errcode = 'P0002'; end if;
  if c.anulada then raise exception 'La compra está anulada' using errcode = 'P0001'; end if;
  if not c.factura_pendiente then raise exception 'Esta compra ya tiene la factura cargada' using errcode = 'P0001'; end if;
  if v_nro = '' then raise exception 'Poné el número de la factura' using errcode = '22023'; end if;
  for x in select value from jsonb_array_elements(coalesce(p -> 'items', '[]')) loop
    select * into i from public.compra_items where id = nullif(x ->> 'id', '')::bigint and compra_id = c.id;
    if not found then raise exception 'Hay un producto que no es de esta compra' using errcode = 'P0002'; end if;
    v_costo := round(public.num(x, 'costo', 'Costo de ' || i.nombre), 2);
    if v_costo is not null and v_costo < 0 then raise exception 'El costo de % no puede ser negativo', i.nombre using errcode = '22023'; end if;
    if v_costo is not null and v_costo <> i.costo then
      update public.compra_items set costo = v_costo, costo_remito = coalesce(costo_remito, i.costo) where id = i.id;
      if v_costo > 0 and not exists (select 1 from public.compra_items ci join public.compras k on k.id = ci.compra_id
                                     where ci.producto_id = i.producto_id and k.id > c.id and not k.anulada) then
        update public.productos set costo = v_costo where id = i.producto_id;
      end if;
      if c.proveedor_id is not null and v_costo > 0 and not exists (select 1 from public.compra_items ci join public.compras k on k.id = ci.compra_id
                                     where ci.producto_id = i.producto_id and k.proveedor_id = c.proveedor_id and k.id > c.id and not k.anulada) then
        update public.producto_proveedores set ultimo_costo = v_costo where producto_id = i.producto_id and proveedor_id = c.proveedor_id;
      end if;
    end if;
    v_precio := round(public.num(x, 'precio_nuevo', 'Precio de ' || i.nombre), 2);
    if v_precio is not null then
      if v_precio <= 0 then raise exception 'Revisá el precio de %', i.nombre using errcode = '22023'; end if;
      update public.compra_items set precio_nuevo = v_precio where id = i.id;
      update public.productos set precio = v_precio where id = i.producto_id;
    end if;
  end loop;
  v_total := round(coalesce(public.num(p, 'total', 'Total'), (select sum(round(cantidad * costo, 2)) from public.compra_items where compra_id = c.id)), 2);
  if v_total < 0 then raise exception 'El total no puede ser negativo' using errcode = '22023'; end if;
  v_plazo := (select plazo from public.proveedores where id = c.proveedor_id);
  begin
    v_ff := coalesce(nullif(p ->> 'fecha_factura', '')::date, public.hoy_negocio(v_neg));
    v_venc := coalesce(nullif(p ->> 'vencimiento', '')::date, v_ff + coalesce(v_plazo, 0));
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'Revisá las fechas' using errcode = '22023';
  end;
  update public.compras set comprobante = v_nro, fecha_factura = v_ff, vencimiento = v_venc, total = v_total, factura_pendiente = false,
      factura_fecha = now(), factura_por = v_u, notas = case when p ? 'notas' then nullif(left(btrim(coalesce(p ->> 'notas', '')), 300), '') else notas end
    where id = c.id;
  -- la caja no se toca; con proveedor, la diferencia queda en su cuenta (más deuda, o a favor)
  v_dif := v_total - c.total;
  if c.proveedor_id is not null and abs(v_dif) > 0.004 and exists (select 1 from public.cc_prov where compra_id = c.id) then
    insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
      values (v_neg, c.proveedor_id, 'ajuste', v_dif, 'Factura ' || v_nro || ': el total cambió', c.id, v_u);
    if v_dif < 0 then perform public.recortar_aplicaciones(c.id); end if;
  end if;
  return public.compra_json(c.id) || jsonb_build_object('diferencia', v_dif);
end;
$$;

-- Anular: además de lo de 5a, se deshacen las aplicaciones de esta factura y las de sus créditos (aunque estuvieran en otra)
create or replace function public.anular_compra(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); c public.compras; t public.turnos; i record; v_neto numeric;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into c from public.compras where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'Compra no encontrada' using errcode = 'P0002'; end if;
  if c.anulada then raise exception 'La compra ya estaba anulada' using errcode = 'P0001'; end if;
  if c.pagada_caja and c.total > 0 then t := public.requiere_turno(); end if;
  for i in select * from public.compra_items where compra_id = c.id loop
    update public.productos set stock = stock - i.cantidad where id = i.producto_id;
    insert into public.movimientos_stock (negocio_id, producto_id, cantidad, motivo, usuario_id) values (v_neg, i.producto_id, -i.cantidad, 'Anulación de compra', v_u);
  end loop;
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, compra_id)
      values (v_neg, t.id, v_u, 'ingreso', 'Anulación de compra', c.total, coalesce(nullif(c.forma, ''), 'Efectivo'), c.id);
  end if;
  if c.proveedor_id is not null then
    select coalesce(sum(monto), 0) into v_neto from public.cc_prov where compra_id = c.id;
    if v_neto <> 0 then
      insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, compra_id, usuario_id)
        values (v_neg, c.proveedor_id, 'anulacion', -v_neto, 'Anulación de compra' || case when c.comprobante <> '' then ' ' || c.comprobante else '' end, c.id, v_u);
    end if;
  end if;
  delete from public.aplicaciones_prov where compra_id = c.id or credito_id in (select id from public.cc_prov where compra_id = c.id);
  update public.compras set anulada = true, anulada_fecha = now(), anulada_por = v_u where id = c.id;
  return public.compra_json(c.id);
end;
$$;

-- Lista: las últimas 300 y todas las que esperan factura, por fecha de la factura
create or replace function public.compras()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_tz text;
begin
  perform public.requiere_admin();
  v_tz := public.zona_horaria(v_neg);
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.fecha, 'proveedor_id', c.proveedor_id,
      'proveedor', (select p.nombre from public.proveedores p where p.id = c.proveedor_id),
      'comprobante', c.comprobante, 'remito', c.remito, 'factura_pendiente', c.factura_pendiente, 'fecha_factura', c.fecha_factura,
      'vencimiento', c.vencimiento, 'total', c.total, 'pagada_caja', c.pagada_caja, 'forma', c.forma, 'anulada', c.anulada,
      'items', (select count(*) from public.compra_items i where i.compra_id = c.id))
      order by coalesce(c.fecha_factura, (c.fecha at time zone v_tz)::date) desc, c.id desc)
    from public.compras c where c.negocio_id = v_neg
      and (c.id >= coalesce((select id from public.compras where negocio_id = v_neg order by id desc offset 299 limit 1), 0)
           or (c.factura_pendiente and not c.anulada))), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- Cuenta del proveedor: pagos con aplicación, aplicar, ajustes con vencimiento
-- ---------------------------------------------------------------------
create or replace function public.cuenta_proveedor(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r public.proveedores;
begin
  perform public.requiere_admin();
  r := public.requiere_proveedor(p_id);
  return public.proveedor_json(r) || jsonb_build_object(
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'fecha', m.fecha, 'tipo', m.tipo, 'monto', m.monto, 'concepto', m.concepto,
        'forma', m.forma, 'de_caja', m.de_caja, 'compra_id', m.compra_id, 'anulado', m.anulado, 'vencimiento', coalesce(m.vencimiento, c.vencimiento),
        'fecha_factura', c.fecha_factura, 'usuario', public.nombre_usuario(m.usuario_id)) order by m.id)
      from public.cc_prov m left join public.compras c on c.id = m.compra_id where m.proveedor_id = r.id), '[]'::jsonb),
    'deudas', coalesce((select jsonb_agg(to_jsonb(d) order by d.vencimiento, d.fecha) from public.deudas_proveedor(r.id) d where d.pendiente > 0.004), '[]'::jsonb),
    'sin_aplicar', (select coalesce(sum(greatest(libre, 0)), 0) from public.creditos_proveedor(r.id)));
end;
$$;

drop function public.pagar_proveedor(bigint, numeric, boolean, text, text);
-- p_aplicaciones: [{ compra_id | deuda_id, monto }] (a qué facturas va el pago); lo que sobra queda a cuenta, sin aplicar
create or replace function public.pagar_proveedor(p_proveedor_id bigint, p_monto numeric, p_de_caja boolean, p_forma text,
  p_concepto text default null, p_aplicaciones jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores; t public.turnos; v_forma text; v_mov bigint;
begin
  perform 1 from public.negocios where id = v_neg for update;
  r := public.requiere_proveedor(p_proveedor_id);
  if coalesce(p_monto, 0) <= 0 then raise exception 'El monto tiene que ser mayor a 0' using errcode = '22023'; end if;
  if coalesce(p_de_caja, false) then
    if not (coalesce(p_forma, '') = any (public.formas_pago(v_neg))) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    t := public.requiere_turno(); v_forma := p_forma;
  else
    v_forma := coalesce(nullif(left(btrim(p_forma), 40), ''), 'Aparte');
  end if;
  insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, turno_id, usuario_id)
    values (v_neg, r.id, 'pago', -round(p_monto, 2), coalesce(nullif(left(btrim(p_concepto), 120), ''), 'Pago'), v_forma, coalesce(p_de_caja, false), t.id, v_u)
    returning id into v_mov;
  perform public.aplicar_lista(v_neg, r.id, p_aplicaciones, v_mov, v_u);
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, cc_prov_id)
      values (v_neg, t.id, v_u, 'egreso', 'Pago a ' || r.nombre, round(p_monto, 2), v_forma, v_mov);
  end if;
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

-- Aplicar lo que está a cuenta (pagos que sobraron, notas de crédito) a facturas, sin mover plata
create or replace function public.aplicar_proveedor(p_proveedor_id bigint, p_aplicaciones jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores;
begin
  perform 1 from public.negocios where id = v_neg for update;
  r := public.requiere_proveedor(p_proveedor_id);
  if coalesce(public.aplicar_lista(v_neg, r.id, p_aplicaciones, null, v_u), 0) = 0 then raise exception 'Elegí a qué facturas aplicarlo' using errcode = '22023'; end if;
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

drop function public.ajuste_proveedor(bigint, numeric, text);
create or replace function public.ajuste_proveedor(p_proveedor_id bigint, p_monto numeric, p_concepto text default null, p_vencimiento date default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); r public.proveedores;
begin
  r := public.requiere_proveedor(p_proveedor_id);
  if coalesce(round(p_monto, 2), 0) = 0 then raise exception 'El monto no puede ser 0' using errcode = '22023'; end if;
  insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, usuario_id, vencimiento)
    values (v_neg, r.id, 'ajuste', round(p_monto, 2),
      coalesce(nullif(left(btrim(p_concepto), 120), ''), case when p_monto > 0 then 'Saldo inicial' else 'Ajuste' end), v_u,
      case when p_monto > 0 then p_vencimiento end);
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

-- Anular un pago o ajuste: además, se deshacen sus aplicaciones (esas facturas vuelven a quedar pendientes)
create or replace function public.anular_mov_proveedor(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); m public.cc_prov; r public.proveedores; t public.turnos; v_mov bigint;
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into m from public.cc_prov where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró el movimiento' using errcode = 'P0002'; end if;
  if m.tipo not in ('pago', 'ajuste') or m.compra_id is not null then raise exception 'Ese movimiento es de una compra: anulá la compra' using errcode = 'P0001'; end if;
  if m.anulado then raise exception 'Ese movimiento ya estaba anulado' using errcode = 'P0001'; end if;
  r := public.requiere_proveedor(m.proveedor_id);
  if m.de_caja then t := public.requiere_turno(); end if;
  insert into public.cc_prov (negocio_id, proveedor_id, tipo, monto, concepto, forma, de_caja, turno_id, usuario_id, anula_id)
    values (v_neg, r.id, 'anulacion', -m.monto, 'Anulación: ' || m.concepto, m.forma, m.de_caja, t.id, v_u, m.id) returning id into v_mov;
  if t.id is not null then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, cc_prov_id)
      values (v_neg, t.id, v_u, 'ingreso', 'Anulación pago a ' || r.nombre, -m.monto, m.forma, v_mov);
  end if;
  update public.cc_prov set anulado = true where id = m.id;
  delete from public.aplicaciones_prov where credito_id = m.id or deuda_id = m.id;
  return jsonb_build_object('saldo', public.saldo_proveedor(r.id));
end;
$$;

-- Qué hay que pagar hasta una fecha, por proveedor, con lo ya vencido
create or replace function public.vencimientos(p_hasta date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_hoy date; v_hasta date;
begin
  perform public.requiere_admin();
  v_hoy := public.hoy_negocio(v_neg);
  v_hasta := coalesce(p_hasta, v_hoy);
  return jsonb_build_object('hoy', v_hoy, 'hasta', v_hasta, 'proveedores', coalesce((select jsonb_agg(x order by x ->> 'primero') from (
    select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'telefono', p.telefono,
      'deudas', (select jsonb_agg(to_jsonb(d) order by d.vencimiento) from public.deudas_proveedor(p.id) d where d.pendiente > 0.004 and d.vencimiento <= v_hasta),
      'total', (select sum(d.pendiente) from public.deudas_proveedor(p.id) d where d.pendiente > 0.004 and d.vencimiento <= v_hasta),
      'primero', (select min(d.vencimiento) from public.deudas_proveedor(p.id) d where d.pendiente > 0.004 and d.vencimiento <= v_hasta),
      'sin_aplicar', (select coalesce(sum(greatest(c.libre, 0)), 0) from public.creditos_proveedor(p.id) c)) as x
    from public.proveedores p where p.negocio_id = v_neg) s where s.x -> 'deudas' <> 'null'::jsonb), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- Una sola vez: los pagos que ya había en las cuentas se aplican a las facturas
-- ---------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select id from public.proveedores loop perform public.aplicar_automatico(p.id, null); end loop;
end $$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.hoy_negocio(uuid), public.deudas_proveedor(bigint), public.creditos_proveedor(bigint),
  public.aplicar(uuid, bigint, bigint, bigint, bigint, numeric, bigint), public.aplicar_automatico(bigint, bigint),
  public.aplicar_lista(uuid, bigint, jsonb, bigint, bigint), public.recortar_aplicaciones(bigint),
  public.cargar_factura_compra(jsonb), public.pagar_proveedor(bigint, numeric, boolean, text, text, jsonb), public.aplicar_proveedor(bigint, jsonb),
  public.ajuste_proveedor(bigint, numeric, text, date), public.vencimientos(date)
  from public, anon, authenticated;
grant execute on function public.cargar_factura_compra(jsonb), public.pagar_proveedor(bigint, numeric, boolean, text, text, jsonb),
  public.aplicar_proveedor(bigint, jsonb), public.ajuste_proveedor(bigint, numeric, text, date), public.vencimientos(date)
  to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 10, 'hora', now());
$$;
