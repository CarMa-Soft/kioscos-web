-- =====================================================================
-- Etapa 4b: descuentos, recargos por forma de pago y autorización del dueño
--
-- Orden de la cuenta (como en la app local, #24): primero los descuentos manuales sobre el precio de lista
-- (rebajas en los renglones y descuento general), después el recargo de cada forma de pago sobre lo que cubre.
--   subtotal = suma de los renglones (con su precio cobrado)
--   base = subtotal − descuento general
--   cada pago: base que cubre + recargo (pct de su forma, redondeado a pesos enteros) = monto
--   total = base + recargos
-- Tope del empleado: descuentos manuales (general + renglones) en % de lo que valía la venta a precio de lista.
-- Por encima hace falta la autorización de un dueño: un paso aparte (autorizar_dueno) que controla el PIN con el
-- mismo bloqueo que el ingreso y deja un permiso de un solo uso, que la venta consume.
-- =====================================================================

alter table public.ventas
  add column descuento numeric(14, 2) not null default 0 check (descuento >= 0),
  add column descuento_renglones numeric(14, 2) not null default 0,
  add column recargo numeric(14, 2) not null default 0 check (recargo >= 0),
  add column autorizo_id bigint,
  add foreign key (autorizo_id, negocio_id) references public.usuarios (id, negocio_id);
alter table public.venta_pagos
  add column recargo numeric(14, 2) not null default 0,
  add column pct_recargo numeric(5, 2) not null default 0;

-- Permisos de un solo uso que da un dueño con su PIN para algo que el empleado no puede hacer solo
create table public.autorizaciones (
  token uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  cuenta uuid not null references auth.users (id) on delete cascade,
  solicitante_id bigint not null,
  dueno_id bigint not null,
  vence timestamptz not null,
  foreign key (solicitante_id, negocio_id) references public.usuarios (id, negocio_id) on delete cascade,
  foreign key (dueno_id, negocio_id) references public.usuarios (id, negocio_id) on delete cascade
);
alter table public.autorizaciones enable row level security;
revoke all on public.autorizaciones from anon, authenticated;

-- ---------------------------------------------------------------------
-- Configuración del cobro
-- ---------------------------------------------------------------------

-- % de recargo de una forma de pago (Efectivo nunca lleva: los precios de lista son para efectivo)
create or replace function public.pct_recargo(p_neg uuid, p_forma text)
returns numeric language sql stable security definer set search_path = '' as $$
  select case when p_forma = 'Efectivo' then 0 else coalesce((
    select least(greatest((c.valor ->> p_forma)::numeric, 0), 100) from public.config c
    where c.negocio_id = p_neg and c.clave = 'recargos' and jsonb_typeof(c.valor -> p_forma) = 'number'), 0) end;
$$;

create or replace function public.tope_descuento(p_neg uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select (c.valor #>> '{}')::numeric from public.config c
    where c.negocio_id = p_neg and c.clave = 'tope_descuento' and jsonb_typeof(c.valor) = 'number'), 10);
$$;

-- Formas de pago, recargos y tope (solo dueño). Efectivo siempre está y va primero; Fiado no se lista (es aparte).
create or replace function public.guardar_ajustes_cobro(p_formas jsonb, p_recargos jsonb, p_tope numeric)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_formas text[] := array['Efectivo']; f text; v_rec jsonb := '{}'; v numeric;
begin
  perform public.requiere_admin();
  if jsonb_typeof(p_formas) is distinct from 'array' then raise exception 'Formas de pago inválidas' using errcode = '22023'; end if;
  for f in select btrim(x) from jsonb_array_elements_text(p_formas) x loop
    if f = '' or f = 'Fiado' or f = any (v_formas) then continue; end if;
    if length(f) > 40 then raise exception 'El nombre de la forma de pago es muy largo' using errcode = '22023'; end if;
    v_formas := v_formas || f;
  end loop;
  if array_length(v_formas, 1) > 12 then raise exception 'Demasiadas formas de pago' using errcode = '22023'; end if;
  for f in select unnest(v_formas[2:] || array['Fiado']) loop
    v := round(public.num(coalesce(p_recargos, '{}'), f, 'Recargo de ' || f), 2);
    if v is null or v = 0 then continue; end if;
    if v < 0 or v > 100 then raise exception 'El recargo de % tiene que ser entre 0 y 100%%', f using errcode = '22023'; end if;
    v_rec := v_rec || jsonb_build_object(f, v);
  end loop;
  if p_tope is null or p_tope < 0 or p_tope > 100 then raise exception 'El tope de descuento tiene que ser entre 0 y 100%%' using errcode = '22023'; end if;
  insert into public.config (negocio_id, clave, valor) values
    (v_neg, 'formas_pago', to_jsonb(v_formas)), (v_neg, 'recargos', v_rec), (v_neg, 'tope_descuento', to_jsonb(round(p_tope, 2)))
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
  return jsonb_build_object('formas_pago', to_jsonb(v_formas), 'recargos', v_rec, 'tope_descuento', round(p_tope, 2));
end;
$$;

-- ---------------------------------------------------------------------
-- Autorización del dueño
-- ---------------------------------------------------------------------

-- El dueño pone su PIN en la PC para autorizar algo del usuario que está usando la app. Devuelve { token } o { error }
-- (no lanza error, para que quede anotado el intento fallido: 5 seguidos bloquean a ese dueño 5 minutos).
create or replace function public.autorizar_dueno(p_dueno_id bigint, p_pin text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); d public.usuarios; v_token uuid;
begin
  select * into d from public.usuarios where id = p_dueno_id and negocio_id = v_neg and activo and rol = 'admin' for update;
  if not found then return jsonb_build_object('error', 'Dueño no encontrado'); end if;
  if d.bloqueado_hasta > now() then
    return jsonb_build_object('error', format('Demasiados intentos: probá de nuevo en %s minuto(s)', ceil(extract(epoch from d.bloqueado_hasta - now()) / 60)));
  end if;
  if coalesce(p_pin, '') = '' or extensions.crypt(p_pin, d.pin_hash) <> d.pin_hash then
    update public.usuarios
      set intentos = case when intentos + 1 >= 5 then 0 else intentos + 1 end,
          bloqueado_hasta = case when intentos + 1 >= 5 then now() + interval '5 minutes' else bloqueado_hasta end
      where id = d.id;
    return jsonb_build_object('error', 'PIN incorrecto');
  end if;
  update public.usuarios set intentos = 0, bloqueado_hasta = null where id = d.id;
  delete from public.autorizaciones where vence <= now();
  insert into public.autorizaciones (negocio_id, cuenta, solicitante_id, dueno_id, vence)
    values (v_neg, auth.uid(), v_u, d.id, now() + interval '5 minutes') returning token into v_token;
  return jsonb_build_object('token', v_token);
end;
$$;

-- Consume un permiso: tiene que ser de este negocio, esta cuenta y este usuario, y no estar vencido. Devuelve el dueño.
create or replace function public.usar_autorizacion(p_token uuid)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_dueno bigint;
begin
  delete from public.autorizaciones
    where token = p_token and negocio_id = public.mi_negocio() and cuenta = auth.uid() and solicitante_id = public.usuario_actual_id() and vence > now()
    returning dueno_id into v_dueno;
  return v_dueno;
end;
$$;

-- ---------------------------------------------------------------------
-- Venta
-- ---------------------------------------------------------------------
create or replace function public.venta_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'usuario', public.nombre_usuario(v.usuario_id),
    'turno_id', v.turno_id, 'subtotal', v.subtotal, 'descuento', v.descuento, 'descuento_renglones', v.descuento_renglones,
    'recargo', v.recargo, 'total', v.total, 'paga_con', v.paga_con,
    'autorizo', case when v.autorizo_id is not null then public.nombre_usuario(v.autorizo_id) end,
    'cliente', (select jsonb_build_object('id', c.id, 'nombre', c.nombre) from public.clientes c where c.id = v.cliente_id),
    'anulada', v.anulada, 'anulada_fecha', v.anulada_fecha, 'anulada_por', case when v.anulada then public.nombre_usuario(v.anulada_por) end,
    'motivo_anulacion', v.motivo_anulacion,
    'items', coalesce((select jsonb_agg(jsonb_build_object('producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'precio', i.precio, 'precio_lista', i.precio_lista, 'importe', i.importe, 'por_peso', i.por_peso) order by i.id)
                       from public.venta_items i where i.venta_id = v.id), '[]'::jsonb),
    'pagos', coalesce((select jsonb_agg(jsonb_build_object('forma', p.forma, 'monto', p.monto, 'recargo', p.recargo, 'pct_recargo', p.pct_recargo) order by p.id)
                       from public.venta_pagos p where p.venta_id = v.id), '[]'::jsonb))
  from public.ventas v where v.id = p_id;
$$;

drop function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean);

-- p_items: [{ producto_id, cantidad, precio? }] (precio = el cobrado en este renglón; si no viene, el de lista)
--          o [{ nombre, importe }] para "Varios".
-- p_descuento: descuento general en pesos. p_pagos: [{ forma, base }] (base = lo que cubre de la venta, sin recargo;
-- las bases suman subtotal − descuento). p_autorizacion: permiso de autorizar_dueno, si el descuento pasa el tope.
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false, p_descuento numeric default 0, p_autorizacion uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas; c public.clientes;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_precio numeric; v_importe numeric;
  v_sub numeric := 0; v_desc_ren numeric := 0; v_desc numeric; v_base numeric; v_bases numeric := 0; v_b numeric; v_pct numeric;
  v_rec numeric; v_recargo numeric := 0; v_fiado numeric := 0; v_pid bigint; v_saldo numeric; v_forma text;
  v_manual numeric; v_alista numeric; v_pct_desc numeric; v_tope numeric; v_aut bigint;
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

  insert into public.ventas (negocio_id, numero, clave, usuario_id, turno_id, subtotal, total, cliente_id)
    values (v_neg, coalesce((select max(numero) from public.ventas where negocio_id = v_neg), 0) + 1, p_clave, v_u, t.id, 0, 0, c.id)
    returning * into v;

  -- Renglones
  for it in select value from jsonb_array_elements(p_items) loop
    v_pid := nullif(it ->> 'producto_id', '')::bigint;
    if v_pid is not null then
      select * into p from public.productos where id = v_pid and negocio_id = v_neg for update;
      if not found then raise exception 'Producto no encontrado' using errcode = 'P0002'; end if;
      if not p.activo then raise exception '"%" está dado de baja', p.nombre using errcode = 'P0001'; end if;
      v_cant := round(public.num(it, 'cantidad', 'Cantidad'), 3);
      if v_cant is null or v_cant <= 0 then raise exception 'Hay una cantidad en 0' using errcode = '22023'; end if;
      if not p.por_peso and v_cant <> trunc(v_cant) then
        raise exception 'La cantidad de "%" tiene que ser entera', p.nombre using errcode = '22023';
      end if;
      v_precio := coalesce(round(public.num(it, 'precio', 'Precio'), 2), p.precio);
      if v_precio < 0 then raise exception 'El precio de "%" no puede ser negativo', p.nombre using errcode = '22023'; end if;
      v_importe := round(v_cant * v_precio, 2);
      -- lo rebajado en el renglón: precio de lista − precio cobrado (si se cobró más caro, no cuenta)
      if p.precio > v_precio then v_desc_ren := v_desc_ren + round((p.precio - v_precio) * v_cant, 2); end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe, costo, por_peso, categoria_id, precio_lista)
        values (v_neg, v.id, p.id, p.nombre, v_cant, v_precio, v_importe, p.costo, p.por_peso, p.categoria_id, p.precio);
      update public.productos set stock = stock - v_cant where id = p.id;
    else
      v_importe := round(public.num(it, 'importe', 'Importe'), 2);
      if v_importe is null or v_importe <= 0 then raise exception 'El importe de "Varios" tiene que ser mayor a 0' using errcode = '22023'; end if;
      insert into public.venta_items (negocio_id, venta_id, producto_id, nombre, cantidad, precio, importe)
        values (v_neg, v.id, null, coalesce(nullif(left(btrim(it ->> 'nombre'), 120), ''), 'Varios'), 1, v_importe, v_importe);
    end if;
    v_sub := v_sub + v_importe;
  end loop;

  -- Descuentos y tope del empleado
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
        raise exception '%', format('El descuento es del %s%% y tu tope es %s%%: necesita la autorización del dueño', v_pct_desc, v_tope)
          using errcode = 'P0001', hint = 'autorizacion';
      end if;
    end if;
  end if;

  -- Pagos: cada uno con su recargo
  v_formas := public.formas_pago(v_neg);
  for pg in select value from jsonb_array_elements(p_pagos) loop
    v_b := round(coalesce(public.num(pg, 'base', 'Monto del pago'), public.num(pg, 'monto', 'Monto del pago')), 2);
    if v_b is null or v_b <= 0 then continue; end if;
    v_forma := coalesce(pg ->> 'forma', '');
    if v_forma <> 'Fiado' and not (v_forma = any (v_formas)) then raise exception 'Forma de pago inválida' using errcode = '22023'; end if;
    if v_forma = 'Fiado' and c.id is null then raise exception 'Para fiar hay que elegir el cliente' using errcode = '22023'; end if;
    v_pct := public.pct_recargo(v_neg, v_forma);
    v_rec := case when v_pct > 0 then round(v_b * v_pct / 100, 0) else 0 end;
    insert into public.venta_pagos (negocio_id, venta_id, forma, monto, recargo, pct_recargo) values (v_neg, v.id, v_forma, v_b + v_rec, v_rec, v_pct);
    if v_forma = 'Fiado' then
      v_fiado := v_fiado + v_b + v_rec;
      insert into public.cc (negocio_id, cliente_id, tipo, monto, concepto, venta_id, usuario_id, turno_id)
        values (v_neg, c.id, 'cargo', v_b + v_rec, 'Compra #' || v.numero, v.id, v_u, t.id);
    else
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_b + v_rec, v_forma, v.id);
    end if;
    v_bases := v_bases + v_b; v_recargo := v_recargo + v_rec;
  end loop;
  if abs(v_bases - v_base) > 0.005 then
    raise exception 'Los pagos (%) no suman el total (%)', v_bases, v_base using errcode = '22023';
  end if;
  if v_fiado > 0 and c.limite > 0 and not coalesce(p_forzar_limite, false) then
    v_saldo := public.saldo_cliente(c.id);
    if v_saldo > c.limite then
      raise exception '% pasaría su límite de fiado (%): quedaría debiendo %', c.nombre, c.limite, v_saldo using errcode = 'P0001', hint = 'limite';
    end if;
  end if;

  update public.ventas set subtotal = v_sub, descuento = v_desc, descuento_renglones = v_desc_ren, recargo = v_recargo,
      total = v_base + v_recargo, autorizo_id = v_aut, paga_con = case when p_paga_con > 0 then round(p_paga_con, 2) end
    where id = v.id;
  return public.venta_json(v.id);
end;
$$;

-- La caja también informa los recargos y el tope (para que la pantalla haga la misma cuenta)
create or replace function public.config_cobro(p_neg uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('formas_pago', to_jsonb(public.formas_pago(p_neg)),
    'recargos', coalesce((select jsonb_object_agg(f, public.pct_recargo(p_neg, f)) from unnest(public.formas_pago(p_neg) || array['Fiado']) f
                          where public.pct_recargo(p_neg, f) > 0), '{}'::jsonb),
    'tope_descuento', public.tope_descuento(p_neg));
$$;

create or replace function public.estado_caja()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); t public.turnos;
begin
  perform public.requiere_usuario();
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then
    return public.config_cobro(v_neg) || jsonb_build_object('turno', null);
  end if;
  return public.config_cobro(v_neg) || jsonb_build_object(
    'turno', jsonb_build_object('id', t.id, 'usuario_id', t.usuario_id, 'usuario', public.nombre_usuario(t.usuario_id),
      'apertura', t.apertura, 'inicial', t.inicial, 'esperado', public.efectivo_esperado(t.id)),
    'por_forma', coalesce((select jsonb_object_agg(forma, total) from (
        select c.forma, sum(case when c.tipo = 'ingreso' then c.monto else -c.monto end) as total
        from public.caja c where c.turno_id = t.id group by c.forma) x), '{}'::jsonb),
    'fiado', coalesce((select sum(p.monto) from public.venta_pagos p join public.ventas v on v.id = p.venta_id
        where v.turno_id = t.id and not v.anulada and p.forma = 'Fiado'), 0),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.fecha, 'tipo', c.tipo, 'concepto', c.concepto,
        'monto', c.monto, 'forma', c.forma, 'venta_id', c.venta_id, 'manual', c.manual, 'usuario', public.nombre_usuario(c.usuario_id)) order by c.id desc)
      from public.caja c where c.turno_id = t.id), '[]'::jsonb),
    'ventas', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'total', v.total,
        'anulada', v.anulada, 'usuario', public.nombre_usuario(v.usuario_id),
        'cliente', (select c.nombre from public.clientes c where c.id = v.cliente_id),
        'fiado', exists (select 1 from public.venta_pagos p where p.venta_id = v.id and p.forma = 'Fiado'),
        'descuento', v.descuento + v.descuento_renglones, 'recargo', v.recargo,
        'resumen', (select string_agg(i.nombre, ', ' order by i.id) from public.venta_items i where i.venta_id = v.id)) order by v.id desc)
      from public.ventas v where v.turno_id = t.id), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.pct_recargo(uuid, text), public.tope_descuento(uuid), public.guardar_ajustes_cobro(jsonb, jsonb, numeric),
  public.autorizar_dueno(bigint, text), public.usar_autorizacion(uuid), public.config_cobro(uuid),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid)
  from public, anon, authenticated;

grant execute on function public.guardar_ajustes_cobro(jsonb, jsonb, numeric), public.autorizar_dueno(bigint, text),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid)
  to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 5, 'hora', now());
$$;
