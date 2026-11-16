-- =====================================================================
-- Etapa 4c: etiquetas de balanza, cierre de caja por billetes y turnos anteriores
--
-- Balanza: la pantalla lee la etiqueta EAN-13 (prefijo + PLU + 5 dígitos de peso o importe + verificador) con el
-- catálogo del navegador. Si la etiqueta trae el importe, el renglón manda ese importe y la base controla que coincida
-- con kilos × precio (con la tolerancia del redondeo de los kilos): no sirve para cobrar menos.
-- Cierre: se cuentan los billetes por valor (lista editable en Ajustes) y el total lo calcula la base. El faltante o
-- sobrante, si se elige registrarlo, queda como movimiento de caja marcado "ajuste".
-- =====================================================================

alter table public.turnos add column billetes jsonb;            -- { detalle: { "20000": 3, ... }, otros: 1500 }
alter table public.caja add column ajuste boolean not null default false;

-- ---------------------------------------------------------------------
-- Configuración
-- ---------------------------------------------------------------------
create or replace function public.config_balanza(p_neg uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select c.valor from public.config c where c.negocio_id = p_neg and c.clave = 'balanza' and jsonb_typeof(c.valor) = 'object'),
    '{"activa": false, "prefijo": "20", "tipo": "peso"}'::jsonb);
$$;

create or replace function public.lista_billetes(p_neg uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select c.valor from public.config c where c.negocio_id = p_neg and c.clave = 'billetes' and jsonb_typeof(c.valor) = 'array'),
    '[20000, 10000, 2000, 1000, 500, 200, 100, 50, 20, 10]'::jsonb);
$$;

-- Balanza y billetes del cierre (solo dueño)
create or replace function public.guardar_ajustes_caja(p_balanza jsonb, p_billetes jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_bal jsonb; v_prefijo text; v_tipo text; v_bil jsonb;
begin
  perform public.requiere_admin();
  v_prefijo := left(regexp_replace(coalesce(p_balanza ->> 'prefijo', '20'), '\D', '', 'g'), 2);
  if length(v_prefijo) = 0 then v_prefijo := '20'; end if;
  v_tipo := coalesce(p_balanza ->> 'tipo', 'peso');
  if v_tipo not in ('peso', 'importe', 'importe_centavos') then raise exception 'Tipo de etiqueta inválido' using errcode = '22023'; end if;
  v_bal := jsonb_build_object('activa', coalesce((p_balanza ->> 'activa')::boolean, false), 'prefijo', v_prefijo, 'tipo', v_tipo);
  select coalesce(jsonb_agg(v order by v desc), '[]'::jsonb) into v_bil from (
    select distinct trim_scale(round(public.num(jsonb_build_object('x', x), 'x', 'Billete'), 2)) as v from jsonb_array_elements_text(coalesce(p_billetes, '[]')) x
  ) b where v > 0;
  if jsonb_array_length(v_bil) = 0 then raise exception 'Cargá al menos un billete' using errcode = '22023'; end if;
  if jsonb_array_length(v_bil) > 20 then raise exception 'Demasiados billetes' using errcode = '22023'; end if;
  insert into public.config (negocio_id, clave, valor) values (v_neg, 'balanza', v_bal), (v_neg, 'billetes', v_bil)
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
  return jsonb_build_object('balanza', v_bal, 'billetes', v_bil);
end;
$$;

-- Lo que la pantalla necesita del cobro y de la caja
create or replace function public.config_cobro(p_neg uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('formas_pago', to_jsonb(public.formas_pago(p_neg)),
    'recargos', coalesce((select jsonb_object_agg(f, public.pct_recargo(p_neg, f)) from unnest(public.formas_pago(p_neg) || array['Fiado']) f
                          where public.pct_recargo(p_neg, f) > 0), '{}'::jsonb),
    'tope_descuento', public.tope_descuento(p_neg),
    'balanza', public.config_balanza(p_neg),
    'billetes', public.lista_billetes(p_neg));
$$;

-- ---------------------------------------------------------------------
-- Venta: importe de la etiqueta de balanza
-- ---------------------------------------------------------------------
-- Igual que en la etapa 4b. Lo nuevo: un renglón de un producto por peso puede traer 'importe' (el de la etiqueta):
-- se cobra ese importe si coincide con kilos × precio dentro del redondeo de los kilos (medio gramo).
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false, p_descuento numeric default 0, p_autorizacion uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v public.ventas; c public.clientes;
  it jsonb; p public.productos; pg jsonb; v_formas text[]; v_cant numeric; v_precio numeric; v_importe numeric; v_etiqueta numeric;
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
      -- etiqueta de balanza con importe: vale ese importe si coincide con kilos × precio (redondeo de medio gramo)
      v_etiqueta := round(public.num(it, 'importe', 'Importe'), 2);
      if v_etiqueta is not null then
        if not p.por_peso then raise exception 'Solo un producto por peso puede llevar el importe de la etiqueta' using errcode = '22023'; end if;
        if abs(v_etiqueta - v_cant * v_precio) > v_precio * 0.0005 + 0.01 then
          raise exception 'El importe de la etiqueta de "%" no coincide con el peso y el precio', p.nombre using errcode = '22023';
        end if;
        v_importe := v_etiqueta;
      end if;
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

-- ---------------------------------------------------------------------
-- Cierre por billetes
-- ---------------------------------------------------------------------
drop function public.cerrar_turno(numeric, numeric, text);

-- Cerrar el turno: lo cierra quien lo abrió o el dueño. Con p_billetes ({ "20000": 3, ... }) el contado lo calcula la
-- base (billetes + p_otros); si no, vale p_contado. Con p_registrar_ajuste, la diferencia queda como movimiento de caja.
create or replace function public.cerrar_turno(p_contado numeric default null, p_retiro numeric default 0, p_notas text default null,
  p_billetes jsonb default null, p_otros numeric default 0, p_registrar_ajuste boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos; v_esperado numeric;
  v_contado numeric; v_dif numeric; v_det jsonb := '{}'; k text; x text; v_valor numeric; v_cant numeric; v_suma numeric := 0;
  v_nota text := nullif(left(btrim(coalesce(p_notas, '')), 500), '');
begin
  perform 1 from public.negocios where id = v_neg for update;
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  if not found then raise exception 'No hay ningún turno abierto' using errcode = 'P0001'; end if;
  if t.usuario_id <> v_u and not public.es_admin() then
    raise exception 'Solo quien abrió el turno (o el dueño) puede cerrarlo' using errcode = '42501';
  end if;
  if p_billetes is not null then
    if jsonb_typeof(p_billetes) <> 'object' then raise exception 'El conteo de billetes no es válido' using errcode = '22023'; end if;
    for k, x in select key, value #>> '{}' from jsonb_each(p_billetes) loop
      begin v_valor := k::numeric; v_cant := x::numeric; exception when others then v_valor := null; end;
      if v_valor is null or v_valor <= 0 or v_cant < 0 or v_cant <> trunc(v_cant) then
        raise exception 'El conteo de billetes no es válido' using errcode = '22023';
      end if;
      if v_cant > 0 then v_det := v_det || jsonb_build_object(k, v_cant); v_suma := v_suma + v_valor * v_cant; end if;
    end loop;
    if coalesce(p_otros, 0) < 0 then raise exception 'Monedas y otros no puede ser negativo' using errcode = '22023'; end if;
    v_contado := round(v_suma + coalesce(p_otros, 0), 2);
  else
    if p_contado is null or p_contado < 0 then raise exception 'Poné el efectivo contado' using errcode = '22023'; end if;
    v_contado := round(p_contado, 2);
  end if;
  if coalesce(p_retiro, 0) < 0 or coalesce(p_retiro, 0) > v_contado then
    raise exception 'El retiro no puede ser mayor a lo contado' using errcode = '22023';
  end if;
  v_esperado := public.efectivo_esperado(t.id);
  v_dif := v_contado - v_esperado;
  update public.turnos set cierre = now(), esperado = v_esperado, contado = v_contado, diferencia = v_dif,
      retiro = round(coalesce(p_retiro, 0), 2), notas = v_nota, cerrado_por = v_u,
      billetes = case when p_billetes is not null then jsonb_build_object('detalle', v_det, 'otros', round(coalesce(p_otros, 0), 2)) end
    where id = t.id;
  -- faltante o sobrante en los movimientos del turno (el esperado guardado no cambia: el cierre sigue mostrando la diferencia real)
  if coalesce(p_registrar_ajuste, false) and abs(v_dif) >= 0.01 then
    insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, ajuste)
      values (v_neg, t.id, v_u, case when v_dif > 0 then 'ingreso' else 'egreso' end,
        case when v_dif > 0 then 'Sobrante' else 'Faltante' end || ' de caja al cierre' || coalesce(' — ' || left(v_nota, 80), ''),
        abs(round(v_dif, 2)), 'Efectivo', true);
  end if;
  return public.turno_json(t.id);
end;
$$;

-- ---------------------------------------------------------------------
-- Turnos anteriores
-- ---------------------------------------------------------------------
create or replace function public.turno_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', t.id, 'usuario', public.nombre_usuario(t.usuario_id), 'apertura', t.apertura, 'cierre', t.cierre,
    'inicial', t.inicial, 'esperado', t.esperado, 'contado', t.contado, 'diferencia', t.diferencia, 'retiro', t.retiro,
    'notas', t.notas, 'billetes', t.billetes, 'cerrado_por', public.nombre_usuario(t.cerrado_por),
    'ventas', (select count(*) from public.ventas v where v.turno_id = t.id and not v.anulada),
    'total_ventas', coalesce((select sum(v.total) from public.ventas v where v.turno_id = t.id and not v.anulada), 0),
    'por_forma', coalesce((select jsonb_object_agg(forma, total) from (
        select c.forma, sum(case when c.tipo = 'ingreso' then c.monto else -c.monto end) as total
        from public.caja c where c.turno_id = t.id group by c.forma) x), '{}'::jsonb),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object('fecha', c.fecha, 'tipo', c.tipo, 'concepto', c.concepto, 'monto', c.monto,
        'forma', c.forma, 'ajuste', c.ajuste, 'usuario', public.nombre_usuario(c.usuario_id)) order by c.id)
      from public.caja c where c.turno_id = t.id), '[]'::jsonb))
  from public.turnos t where t.id = p_id;
$$;

-- Los últimos turnos cerrados: el dueño ve todos; el empleado, los suyos
create or replace function public.turnos_anteriores()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); v_admin boolean := public.es_admin();
begin
  return coalesce((select jsonb_agg(x order by (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', t.id, 'usuario', public.nombre_usuario(t.usuario_id), 'apertura', t.apertura, 'cierre', t.cierre,
      'esperado', t.esperado, 'contado', t.contado, 'diferencia', t.diferencia, 'retiro', t.retiro,
      'total_ventas', coalesce((select sum(v.total) from public.ventas v where v.turno_id = t.id and not v.anulada), 0)) as x
    from public.turnos t where t.negocio_id = v_neg and t.cierre is not null and (v_admin or t.usuario_id = v_u)
    order by t.id desc limit 100) s), '[]'::jsonb);
end;
$$;

create or replace function public.turno(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); t public.turnos;
begin
  select * into t from public.turnos where id = p_id and negocio_id = v_neg;
  if not found or (t.usuario_id <> v_u and not public.es_admin()) then raise exception 'Turno no encontrado' using errcode = 'P0002'; end if;
  return public.turno_json(t.id);
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------
revoke all on function public.config_balanza(uuid), public.lista_billetes(uuid), public.guardar_ajustes_caja(jsonb, jsonb),
  public.cerrar_turno(numeric, numeric, text, jsonb, numeric, boolean), public.turno_json(bigint), public.turnos_anteriores(), public.turno(bigint)
  from public, anon, authenticated;
grant execute on function public.guardar_ajustes_caja(jsonb, jsonb), public.cerrar_turno(numeric, numeric, text, jsonb, numeric, boolean),
  public.turnos_anteriores(), public.turno(bigint)
  to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 6, 'hora', now());
$$;
