-- =====================================================================
-- Ventas sin conexión: si se corta internet, Vender guarda la venta en la PC y la sube cuando vuelve (o al cerrar la caja).
-- registrar_venta acepta p_sin_conexion { fecha, usuario_id, promos: [{ k, promocion_id, descuento }] } y en cada renglón
-- "lista" (el precio de lista que tenía la PC). La venta queda con la fecha y hora en que se hizo y marcada sin_conexion.
-- La clave de siempre evita que se registre dos veces (por ejemplo, si se cortó justo después de grabarla).
-- =====================================================================
alter table public.ventas add column sin_conexion boolean not null default false;

drop function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb, bigint[], numeric);
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false, p_descuento numeric default 0, p_autorizacion uuid default null,
  p_entrega jsonb default null, p_encargos jsonb default null, p_sin_promos bigint[] default null, p_promos numeric default null,
  p_sin_conexion jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas; c public.clientes;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_precio numeric; v_importe numeric; v_etiqueta numeric;
  v_sub numeric := 0; v_desc_ren numeric := 0; v_desc numeric; v_base numeric; v_bases numeric := 0; v_b numeric; v_pct numeric;
  v_rec numeric; v_recargo numeric := 0; v_fiado numeric := 0; v_pid bigint; v_saldo numeric; v_forma text;
  v_manual numeric; v_alista numeric; v_pct_desc numeric; v_tope numeric; v_aut bigint;
  v_item bigint; v_pend numeric; v_ent_nombre text; v_ent_tel text;
  v_enc public.encargos; v_enc_ids bigint[] := '{}'; v_sena_disp numeric := 0; v_sena numeric := 0;
  v_enc_cant jsonb := '{}'; v_ec numeric; v_resto_sena numeric; v_us numeric; v_stock numeric;
  v_ids bigint[] := '{}'; v_lineas jsonb := '[]'; v_fp text[]; pp jsonb; v_pd numeric; v_promos numeric := 0;
  v_off boolean := coalesce(jsonb_typeof(p_sin_conexion) = 'object', false); v_fecha timestamptz := now(); v_lista numeric; v_ou bigint; v_pk int; v_pnombre text;
begin
  if p_clave is null then raise exception 'Falta la clave de la venta' using errcode = '22023'; end if;
  perform 1 from public.negocios where id = v_neg for update;     -- una venta a la vez por negocio
  select * into v from public.ventas where negocio_id = v_neg and clave = p_clave;
  if found then return public.venta_json(v.id) || jsonb_build_object('repetida', true); end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene productos' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 300 then raise exception 'La venta tiene demasiados renglones' using errcode = '22023'; end if;
  if jsonb_typeof(p_pagos) is distinct from 'array' or jsonb_array_length(p_pagos) = 0 then
    raise exception 'Falta la forma de pago' using errcode = '22023';
  end if;
  if p_cliente_id is not null then
    c := public.requiere_cliente(p_cliente_id);
    if not c.activo then raise exception '"%" está dado de baja', c.nombre using errcode = 'P0001'; end if;
  end if;
  t := public.requiere_turno();
  -- venta hecha sin conexión que se sube después: con la fecha y hora en que se hizo y a nombre de quien la hizo. Los precios
  -- y las promociones son los que tenía la PC en ese momento (lo que se cobró). Sin fiado, encargos ni entregas para después.
  if v_off then
    begin v_fecha := (p_sin_conexion ->> 'fecha')::timestamptz; exception when others then v_fecha := null; end;
    if v_fecha is null or v_fecha > now() + interval '10 minutes' or v_fecha < now() - interval '7 days' then
      raise exception 'La fecha de la venta sin conexión no es válida' using errcode = '22023';
    end if;
    v_fecha := least(v_fecha, now());
    v_ou := nullif(p_sin_conexion ->> 'usuario_id', '')::bigint;
    if v_ou is not null and exists (select 1 from public.usuarios where id = v_ou and negocio_id = v_neg) then v_u := v_ou; end if;
    if jsonb_typeof(p_encargos) = 'array' and jsonb_array_length(p_encargos) > 0 or jsonb_typeof(p_entrega) = 'object' then
      raise exception 'Una venta sin conexión no puede tener encargos ni entregas para después' using errcode = '22023';
    end if;
  end if;
  -- formas de pago de la venta (sin la seña): para las promociones que valen solo con ciertas formas
  v_fp := array(select distinct x.value ->> 'forma' from jsonb_array_elements(p_pagos) x(value)
    where coalesce(x.value ->> 'forma', '') <> 'Seña'
      and coalesce(public.num(x.value, 'base', 'Monto del pago'), public.num(x.value, 'monto', 'Monto del pago')) >= 0.005);
  -- encargos que se entregan con esta venta: su seña (que ya entró a la caja) se puede usar como pago "Seña"
  if p_encargos is not null and jsonb_typeof(p_encargos) <> 'null' then
    if jsonb_typeof(p_encargos) <> 'array' then raise exception 'Encargos inválidos' using errcode = '22023'; end if;
    -- cada elemento: el id (todo lo pendiente) o { id, cantidad } (una parte: lo que llegó)
    select coalesce(jsonb_object_agg(q.k, q.cant_enc), '{}') into v_enc_cant from (
      select coalesce(x ->> 'id', x #>> '{}') as k, sum(round(coalesce(public.num(case when jsonb_typeof(x) = 'object' then x end, 'cantidad', 'Cantidad'), -1), 3)) as cant_enc
      from jsonb_array_elements(p_encargos) x group by 1) q;
    v_enc_ids := array(select k::bigint from jsonb_object_keys(v_enc_cant) k);
    for v_enc in select * from public.encargos where negocio_id = v_neg and id = any (v_enc_ids) order by id for update loop
      if v_enc.estado <> 'pendiente' then raise exception 'El encargo #% ya no está pendiente', v_enc.numero using errcode = 'P0001'; end if;
      v_ec := (v_enc_cant ->> v_enc.id::text)::numeric;
      if v_ec < 0 then v_ec := v_enc.cantidad - v_enc.entregado; v_enc_cant := v_enc_cant || jsonb_build_object(v_enc.id::text, v_ec); end if;
      if v_ec <= 0 or v_ec > v_enc.cantidad - v_enc.entregado then
        raise exception 'Del encargo #% quedan % por entregar', v_enc.numero, trim_scale(v_enc.cantidad - v_enc.entregado) using errcode = '22023';
      end if;
      v_sena_disp := v_sena_disp + v_enc.sena - v_enc.sena_usada;
    end loop;
    -- solo se entrega lo que llegó: lo encargado de cada producto no puede pasar su stock
    for v_enc in select * from public.encargos where negocio_id = v_neg and id = any (v_enc_ids) loop
      select stock into v_stock from public.productos where id = v_enc.producto_id;
      if (select sum((v_enc_cant ->> e2.id::text)::numeric) from public.encargos e2 where e2.id = any (v_enc_ids) and e2.producto_id = v_enc.producto_id) > v_stock then
        raise exception 'De "%" hay % en stock: entregá del encargo solo lo que llegó', v_enc.nombre, trim_scale(greatest(v_stock, 0)) using errcode = 'P0001';
      end if;
    end loop;
    if (select count(*) from public.encargos where negocio_id = v_neg and id = any (v_enc_ids)) <> cardinality(v_enc_ids) then
      raise exception 'Encargo no encontrado' using errcode = 'P0002';
    end if;
  end if;
  -- a nombre de quién queda lo que se entrega después: el cliente o el nombre que se escribió al cobrar
  v_ent_nombre := coalesce(nullif(left(btrim(coalesce(p_entrega ->> 'nombre', '')), 80), ''), c.nombre);
  v_ent_tel := nullif(left(btrim(coalesce(p_entrega ->> 'telefono', '')), 40), '');

  insert into public.ventas (negocio_id, numero, clave, usuario_id, turno_id, subtotal, total, cliente_id, fecha, sin_conexion)
    values (v_neg, coalesce((select max(numero) from public.ventas where negocio_id = v_neg), 0) + 1, p_clave, v_u, t.id, 0, 0, c.id, v_fecha, v_off)
    returning * into v;

  for it in select value from jsonb_array_elements(p_items) loop
    v_pid := nullif(it ->> 'producto_id', '')::bigint;
    if v_pid is not null then
      select * into p from public.productos where id = v_pid and negocio_id = v_neg for update;
      if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
      if not p.activo and not v_off then raise exception '"%" está dado de baja', p.nombre using errcode = 'P0001'; end if;
      v_cant := round(public.num(it, 'cantidad', 'Cantidad'), 3);
      if v_cant is null or v_cant <= 0 then raise exception 'Hay una cantidad en 0' using errcode = '22023'; end if;
      if not p.por_peso and v_cant <> trunc(v_cant) then
        raise exception 'La cantidad de "%" tiene que ser entera', p.nombre using errcode = '22023';
      end if;
      v_precio := coalesce(round(public.num(it, 'precio', 'Precio'), 2), p.precio);
      if v_precio < 0 then raise exception 'El precio de "%" no puede ser negativo', p.nombre using errcode = '22023'; end if;
      -- el precio de lista: el de ahora, o el que tenía la PC cuando se vendió sin conexión
      v_lista := p.precio;
      if v_off then v_lista := coalesce(round(public.num(it, 'lista', 'Precio de lista'), 2), p.precio); end if;
      if v_lista < 0 then raise exception 'El precio de lista de "%" no puede ser negativo', p.nombre using errcode = '22023'; end if;
      v_importe := round(v_cant * v_precio, 2);
      -- etiqueta de balanza con importe: vale ese importe si coincide con kilos × precio (redondeo de medio gramo)
      v_etiqueta := round(public.num(it, 'importe', 'Importe'), 2);
      if v_etiqueta is not null then
        if not p.por_peso then raise exception 'Solo un producto por peso puede llevar el importe de la etiqueta' using errcode = '22023'; end if;
        if abs(v_etiqueta - v_cant * v_precio) > v_precio * 0.0005 + 0.01 then
          raise exception 'El importe de la etiqueta de "%" no coincide con el peso y el precio', p.nombre using errcode = '22023';
        end if;
        v_importe := v_etiqueta;
      end if;
      if v_lista > v_precio then v_desc_ren := v_desc_ren + round((v_lista - v_precio) * v_cant, 2); end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe, costo, por_peso, categoria_id, precio_lista)
        values (v_neg, v.id, p.id, p.nombre, v_cant, v_precio, v_importe, p.costo, p.por_peso, p.categoria_id, v_lista)
        returning id into v_item;
      v_ids := v_ids || v_item;
      if not p.por_peso and v_etiqueta is null and v_precio = v_lista then
        v_lineas := v_lineas || jsonb_build_object('k', cardinality(v_ids), 'producto_id', p.id, 'cantidad', v_cant, 'precio', v_precio);
      end if;
      -- lo que no hay en stock y se entrega después: se cobra igual, pero del stock sale solo lo que se lleva ahora
      v_pend := round(coalesce(public.num(it, 'pendiente', 'Pendiente de entrega'), 0), 3);
      if v_pend < 0 or v_pend > v_cant then raise exception 'Lo pendiente de entrega de "%" no puede pasar lo vendido', p.nombre using errcode = '22023'; end if;
      if v_pend > 0 and v_off then raise exception 'Una venta sin conexión no puede tener entregas para después' using errcode = '22023'; end if;
      if v_pend > 0 then
        if v_ent_nombre is null then raise exception 'Falta a nombre de quién queda lo que se entrega después' using errcode = '22023'; end if;
        insert into public.entregas_pendientes (negocio_id, venta_id, venta_item_id, producto_id, nombre, cantidad, cliente_id, a_nombre, telefono, usuario_id)
          values (v_neg, v.id, v_item, p.id, p.nombre, v_pend, c.id, v_ent_nombre, v_ent_tel, v_u);
      end if;
      update public.productos set stock = stock - (v_cant - v_pend) where id = p.id;
    else
      v_importe := round(public.num(it, 'importe', 'Importe'), 2);
      if v_importe is null or v_importe <= 0 then raise exception 'El importe de "Varios" tiene que ser mayor a 0' using errcode = '22023'; end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe)
        values (v_neg, v.id, null, coalesce(nullif(left(btrim(it ->> 'nombre'), 120), ''), 'Varios'), 1, v_importe, v_importe)
        returning id into v_item;
      v_ids := v_ids || v_item;
    end if;
    v_sub := v_sub + v_importe;
  end loop;

  -- promociones: el descuento queda en cada renglón (y su importe, rebajado)
  if v_off then
    -- sin conexión: las que calculó la PC con las promociones de ese día ([{ k, promocion_id, descuento }])
    for pp in select value from jsonb_array_elements(case when jsonb_typeof(p_sin_conexion -> 'promos') = 'array' then p_sin_conexion -> 'promos' else '[]'::jsonb end) loop
      v_pd := round(public.num(pp, 'descuento', 'Descuento de la promoción'), 2);
      continue when v_pd is null or v_pd <= 0;
      v_pk := nullif(pp ->> 'k', '')::int;
      if v_pk is null or v_pk < 1 or v_pk > cardinality(v_ids) then raise exception 'Promoción en un renglón que no existe' using errcode = '22023'; end if;
      select nombre into v_pnombre from public.promociones where id = nullif(pp ->> 'promocion_id', '')::bigint and negocio_id = v_neg;
      if not found then raise exception 'Promoción no encontrada' using errcode = 'P0002'; end if;
      update public.venta_items set promo = v_pd, importe = importe - v_pd, promocion_id = (pp ->> 'promocion_id')::bigint, promo_nombre = v_pnombre
        where id = v_ids[v_pk] and producto_id is not null and promo = 0 and importe >= v_pd;
      if not found then raise exception 'La promoción de un renglón no es válida' using errcode = '22023'; end if;
      v_promos := v_promos + v_pd;
    end loop;
  elsif jsonb_array_length(v_lineas) > 0 then
    for pp in select value from jsonb_array_elements(public.promos_venta(v_neg, v_lineas, v_fp, p_sin_promos)) loop
      v_pd := (pp ->> 'descuento')::numeric;
      continue when v_pd <= 0;
      update public.venta_items set promo = v_pd, importe = importe - v_pd, promocion_id = (pp ->> 'promocion_id')::bigint, promo_nombre = pp ->> 'nombre'
        where id = v_ids[(pp ->> 'k')::int];
      v_promos := v_promos + v_pd;
    end loop;
  end if;
  if not v_off and p_promos is not null and abs(p_promos - v_promos) > 0.005 then
    raise exception 'Las promociones cambiaron: ahora descuentan %. Revisá el total y cobrá de nuevo', v_promos using errcode = 'P0001', hint = 'promos';
  end if;
  v_sub := v_sub - v_promos;

  v_desc := least(round(coalesce(p_descuento, 0), 2), v_sub);
  if v_desc < 0 then raise exception 'El descuento no puede ser negativo' using errcode = '22023'; end if;
  v_base := v_sub - v_desc;
  v_manual := v_desc + v_desc_ren; v_alista := v_sub + v_desc_ren;
  if v_manual > 0.004 and v_alista > 0 and not public.es_admin() then
    v_pct_desc := round(v_manual / v_alista * 100, 1);
    v_tope := public.tope_descuento(v_neg);
    if v_pct_desc > v_tope then
      if p_autorizacion is not null then v_aut := public.usar_autorizacion(p_autorizacion); end if;
      if v_aut is null then
        raise exception '%', format('El descuento es del %s%% y tu tope es %s%%: necesita la autorización del dueño', trim_scale(v_pct_desc), trim_scale(v_tope))
          using errcode = 'P0001', hint = 'autorizacion';
      end if;
    end if;
  end if;

  v_formas := public.formas_pago(v_neg);
  for pg in select value from jsonb_array_elements(p_pagos) loop
    v_b := round(coalesce(public.num(pg, 'base', 'Monto del pago'), public.num(pg, 'monto', 'Monto del pago')), 2);
    if v_b is null or v_b <= 0 then continue; end if;
    v_forma := coalesce(pg ->> 'forma', '');
    if v_off and v_forma in ('Fiado', 'Seña') then raise exception 'Una venta sin conexión no puede ser fiada' using errcode = '22023'; end if;
    if v_forma not in ('Fiado', 'Seña') and not (v_forma = any (v_formas)) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    if v_forma = 'Fiado' and c.id is null then raise exception 'Para fiar hay que elegir el cliente' using errcode = '22023'; end if;
    v_pct := case when v_forma = 'Seña' then 0 else public.pct_recargo(v_neg, v_forma) end;
    v_rec := case when v_pct > 0 then round(v_b * v_pct / 100, 0) else 0 end;
    insert into public.venta_pagos (negocio_id, venta_id, forma, monto, recargo, pct_recargo) values (v_neg, v.id, v_forma, v_b + v_rec, v_rec, v_pct);
    if v_forma = 'Fiado' then
      v_fiado := v_fiado + v_b + v_rec;
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id, turno_id)
        values (v_neg, c.id, 'cargo', v_b + v_rec, 'Compra #' || v.numero, v.id, v_u, t.id);
    elsif v_forma = 'Seña' then
      v_sena := v_sena + v_b;   -- ya entró a la caja cuando se dejó la seña
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id, fecha)
        values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_b + v_rec, v_forma, v.id, v_fecha);
    end if;
    v_bases := v_bases + v_b; v_recargo := v_recargo + v_rec;
  end loop;
  if abs(v_bases - v_base) > 0.005 then
    raise exception 'Los pagos (%) no suman el total (%)', v_bases, v_base using errcode = '22023';
  end if;
  if v_sena > v_sena_disp + 0.005 then
    raise exception 'La seña que se usa (%) pasa la de los encargos (%)', v_sena, v_sena_disp using errcode = '22023';
  end if;
  -- lo entregado de cada encargo, y la seña usada repartida del encargo más viejo al más nuevo
  v_resto_sena := v_sena;
  for v_enc in select * from public.encargos where negocio_id = v_neg and id = any (v_enc_ids) order by id loop
    v_ec := (v_enc_cant ->> v_enc.id::text)::numeric;
    v_us := least(v_resto_sena, v_enc.sena - v_enc.sena_usada);
    v_resto_sena := v_resto_sena - v_us;
    insert into public.encargo_entregas (negocio_id, encargo_id, venta_id, cantidad, sena) values (v_neg, v_enc.id, v.id, v_ec, v_us);
    update public.encargos set entregado = entregado + v_ec, sena_usada = sena_usada + v_us, venta_id = v.id,
        estado = case when entregado + v_ec >= cantidad then 'entregado' else 'pendiente' end,
        cerrado = case when entregado + v_ec >= cantidad then now() end, cerrado_por = case when entregado + v_ec >= cantidad then v_u end
      where id = v_enc.id;
  end loop;
  if v_fiado > 0 and c.limite > 0 and not coalesce(p_forzar_limite, false) then
    v_saldo := public.saldo_cliente(c.id);
    if v_saldo > c.limite then
      raise exception '% pasaría su límite de fiado (%): quedaría debiendo %', c.nombre, c.limite, v_saldo using errcode = 'P0001', hint = 'limite';
    end if;
  end if;

  update public.ventas set subtotal = v_sub, descuento = v_desc, descuento_renglones = v_desc_ren, descuento_promos = v_promos, recargo = v_recargo,
      total = v_base + v_recargo, autorizo_id = v_aut, paga_con = case when p_paga_con > 0 then round(p_paga_con, 2) end
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

revoke all on function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb, bigint[], numeric, jsonb) from public, anon, authenticated;
grant execute on function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb, bigint[], numeric, jsonb) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 46, 'hora', now());
$$;
