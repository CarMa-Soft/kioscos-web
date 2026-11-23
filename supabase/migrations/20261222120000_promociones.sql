-- =====================================================================
-- Promociones por cantidad (Productos → Promociones; se aplican solas en Vender).
-- Cada promoción tiene uno o más productos (las unidades se juntan: "3 alfajores cualquiera") y un tipo:
--   lleva_paga  lleva N, paga M (3x2, 2x1): en cada grupo de N, las N − M más baratas salen gratis
--   precio      N por $X (2 por $1.500): cada grupo de N cuesta X (si ya cuesta menos, nada)
--   unidad_pct  la N-ésima con % menos (la 2ª al 50%): en cada grupo, la más barata
--   desde_pct   llevando N o más, % menos en todas (con N = 1, una oferta simple)
-- Vigencia: desde / hasta (opcionales, con la fecha del negocio), días de la semana (vacío = todos) y formas de pago
-- (vacío = todas; si no, todos los pagos de la venta tienen que ser de esas formas; la seña de un encargo no cuenta).
--
-- La cuenta (la misma en vender.js; la que vale es esta):
--   - Entran los renglones de productos por unidad a precio de lista (un precio cambiado a mano o por kilo, no).
--   - Las unidades se ordenan de la más cara a la más barata (a igual precio, en el orden de los renglones) y se arman
--     grupos de N desde la más cara; lo que sobra (las más baratas) queda fuera de la promoción.
--   - Todo en centavos enteros: un % se redondea por unidad; en "N por $X" lo que se descuenta se reparte entre las
--     unidades del grupo en proporción a su precio y la última se lleva la diferencia del redondeo.
--   - Varias promociones: se aplica primero la que más descuenta; sus renglones ya no entran en otra; y así.
--   - El cajero puede quitar una (p_sin_promos). La venta manda lo que calculó (p_promos): si la base calcula otra cosa
--     (cambió una promoción, o el día), corta con hint 'promos' sin registrar nada.
--   - El descuento queda en cada renglón (venta_items.promo, y su importe ya rebajado): las devoluciones, los reportes
--     por producto y la ganancia lo toman solos. No cuenta para el tope de descuento del empleado.
-- =====================================================================
create table public.promociones (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 60),
  tipo text not null check (tipo in ('lleva_paga', 'precio', 'unidad_pct', 'desde_pct')),
  cantidad integer not null check (cantidad between 1 and 100),
  paga integer,
  pct integer check (pct between 1 and 100),
  precio numeric(14, 2) check (precio > 0),
  productos bigint[] not null check (cardinality(productos) between 1 and 300),
  desde date,
  hasta date,
  dias smallint[] not null default '{}',
  formas text[] not null default '{}',
  activa boolean not null default true,
  creada timestamptz not null default now(),
  unique (id, negocio_id),
  check (hasta is null or desde is null or hasta >= desde),
  check (dias <@ '{1,2,3,4,5,6,7}'::smallint[]),
  check (case tipo when 'lleva_paga' then cantidad >= 2 and paga between 1 and cantidad - 1
                   when 'precio' then cantidad >= 2 and precio is not null
                   when 'unidad_pct' then cantidad >= 2 and pct is not null
                   else pct is not null end)
);
create index promociones_negocio on public.promociones (negocio_id);
alter table public.promociones enable row level security;
revoke all on public.promociones from anon, authenticated;

alter table public.venta_items add column promo numeric(14, 2) not null default 0,
  add column promocion_id bigint, add column promo_nombre text;
alter table public.venta_items add constraint venta_items_promocion foreign key (promocion_id, negocio_id)
  references public.promociones (id, negocio_id) on delete set null (promocion_id);
alter table public.ventas add column descuento_promos numeric(14, 2) not null default 0;

-- ---------------------------------------------------------------------
-- La cuenta
-- ---------------------------------------------------------------------
-- Lo que descuenta una promoción sobre los renglones (p_lineas: [{k, producto_id, cantidad, precio}]) que no están en p_usadas.
-- Devuelve [{k, descuento}] de cada renglón que entró en un grupo (con 0 también: ya no entra en otra promoción).
create or replace function public.promo_descuentos(pr public.promociones, p_lineas jsonb, p_usadas int[])
returns jsonb language sql stable security definer set search_path = '' as $$
  with l as (
    select x.k, x.cantidad, x.precio from jsonb_to_recordset(p_lineas) as x(k int, producto_id bigint, cantidad numeric, precio numeric)
    where x.producto_id = any (pr.productos) and not (x.k = any (coalesce(p_usadas, '{}')))
  ), u as (
    select l.k, round(l.precio * 100)::bigint as c, row_number() over (order by l.precio desc, l.k, s) as n
    from l cross join generate_series(1, l.cantidad::int) s
  ), g as (
    select u.k, u.c, (u.n - 1) / pr.cantidad as grp, (u.n - 1) % pr.cantidad + 1 as pos
    from u, (select count(*) as un from u) t
    where case when pr.tipo = 'desde_pct' then t.un >= pr.cantidad else u.n <= (t.un / pr.cantidad) * pr.cantidad end
  ), gs as (
    select g.*, sum(g.c) over (partition by g.grp) as sc from g
  ), p1 as (
    select gs.*, case when pr.tipo = 'precio' and gs.sc > 0 then greatest(gs.sc - round(pr.precio * 100)::bigint, 0) else 0 end as dg from gs
  ), p2 as (
    select p1.*, case when pr.tipo = 'precio' and p1.pos < pr.cantidad and p1.sc > 0 then round(p1.c * p1.dg::numeric / p1.sc) else 0 end as sh from p1
  ), d as (
    select p2.k, case pr.tipo
        when 'desde_pct' then round(p2.c * pr.pct / 100.0)
        when 'unidad_pct' then case when p2.pos = pr.cantidad then round(p2.c * pr.pct / 100.0) else 0 end
        when 'lleva_paga' then case when p2.pos > pr.paga then p2.c else 0 end
        else case when p2.pos = pr.cantidad then p2.dg - sum(p2.sh) over (partition by p2.grp) else p2.sh end
      end as dc
    from p2
  )
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'descuento', round(t / 100.0, 2)) order by k), '[]'::jsonb)
  from (select k, sum(dc) as t from d group by k) x;
$$;

-- Las promociones que valen hoy en el negocio (fecha y día de la semana del negocio)
create or replace function public.promos_de_hoy(p_neg uuid)
returns setof public.promociones language sql stable security definer set search_path = '' as $$
  select p.* from public.promociones p, (select public.hoy_negocio(p_neg) as hoy) h
  where p.negocio_id = p_neg and p.activa and (p.desde is null or p.desde <= h.hoy) and (p.hasta is null or p.hasta >= h.hoy)
    and (cardinality(p.dias) = 0 or extract(isodow from h.hoy)::smallint = any (p.dias))
  order by p.id;
$$;

-- Todas las promociones de una venta: [{k, promocion_id, nombre, descuento}] (los renglones con 0 también)
create or replace function public.promos_venta(p_neg uuid, p_lineas jsonb, p_formas text[], p_sin bigint[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  pr public.promociones; v_usadas int[] := '{}'; v_aplicadas bigint[] := '{}'; v_res jsonb := '[]';
  v_d jsonb; v_t numeric; v_mejor public.promociones; v_mejor_id bigint; v_mejor_t numeric; v_mejor_d jsonb;
begin
  loop
    v_mejor_id := null; v_mejor_t := 0;
    for pr in select * from public.promos_de_hoy(p_neg) loop
      continue when pr.id = any (coalesce(p_sin, '{}')) or pr.id = any (v_aplicadas)
        or (cardinality(pr.formas) > 0 and not (coalesce(p_formas, '{}') <@ pr.formas));
      v_d := public.promo_descuentos(pr, p_lineas, v_usadas);
      select coalesce(sum((x ->> 'descuento')::numeric), 0) into v_t from jsonb_array_elements(v_d) x;
      if v_t > v_mejor_t then v_mejor := pr; v_mejor_id := pr.id; v_mejor_t := v_t; v_mejor_d := v_d; end if;
    end loop;
    exit when v_mejor_id is null;
    v_aplicadas := v_aplicadas || v_mejor_id;
    v_usadas := v_usadas || array(select (x ->> 'k')::int from jsonb_array_elements(v_mejor_d) x);
    v_res := v_res || (select jsonb_agg(x || jsonb_build_object('promocion_id', v_mejor.id, 'nombre', v_mejor.nombre)) from jsonb_array_elements(v_mejor_d) x);
  end loop;
  return v_res;
end;
$$;

-- ---------------------------------------------------------------------
-- Armar las promociones (solo el dueño) y las de hoy para Vender (todos)
-- ---------------------------------------------------------------------
create or replace function public.promo_json(p public.promociones)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'tipo', p.tipo, 'cantidad', p.cantidad, 'paga', p.paga, 'pct', p.pct,
    'precio', p.precio, 'productos', to_jsonb(p.productos), 'desde', p.desde, 'hasta', p.hasta, 'dias', to_jsonb(p.dias),
    'formas', to_jsonb(p.formas), 'activa', p.activa);
$$;

create or replace function public.promociones()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  return jsonb_build_object('hoy', public.hoy_negocio(v_neg),
    'promociones', coalesce((select jsonb_agg(public.promo_json(p) order by p.activa desc, p.nombre) from public.promociones p where p.negocio_id = v_neg), '[]'::jsonb));
end;
$$;

create or replace function public.promociones_vigentes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_usuario();
  return coalesce((select jsonb_agg(public.promo_json(p) order by p.id) from public.promos_de_hoy(v_neg) p), '[]'::jsonb);
end;
$$;

-- p: { id? , nombre, tipo, cantidad, paga, pct, precio, productos: [id], desde, hasta, dias: [1..7], formas: [texto], activa }
create or replace function public.guardar_promocion(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_id bigint := nullif(p ->> 'id', '')::bigint; r public.promociones;
  v_prods bigint[]; v_dias smallint[]; v_formas text[]; v_tipo text := p ->> 'tipo'; v_n int; v_paga int; v_pct int; v_precio numeric;
begin
  perform public.requiere_admin();
  if jsonb_typeof(p -> 'productos') is distinct from 'array' then raise exception 'Elegí los productos de la promoción' using errcode = '22023'; end if;
  v_prods := array(select distinct x::bigint from jsonb_array_elements_text(p -> 'productos') x);
  if cardinality(v_prods) = 0 then raise exception 'Elegí los productos de la promoción' using errcode = '22023'; end if;
  if (select count(*) from public.productos where negocio_id = v_neg and id = any (v_prods)) <> cardinality(v_prods) then
    raise exception 'Producto no encontrado' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.productos where id = any (v_prods) and por_peso) then
    raise exception 'Las promociones por cantidad son de productos por unidad (no por kilo)' using errcode = '22023';
  end if;
  v_dias := array(select distinct x::smallint from jsonb_array_elements_text(coalesce(p -> 'dias', '[]')) x order by 1);
  v_formas := array(select distinct left(btrim(x), 40) from jsonb_array_elements_text(coalesce(p -> 'formas', '[]')) x where btrim(x) <> '');
  if btrim(coalesce(p ->> 'nombre', '')) = '' then raise exception 'Poné el nombre de la promoción' using errcode = '22023'; end if;
  if v_tipo is null or v_tipo not in ('lleva_paga', 'precio', 'unidad_pct', 'desde_pct') then raise exception 'Tipo de promoción inválido' using errcode = '22023'; end if;
  v_n := public.num(p, 'cantidad', 'Cantidad');
  if v_n is null or v_n < 1 or v_n > 100 or public.num(p, 'cantidad', 'Cantidad') <> v_n then
    raise exception 'La cantidad tiene que ser un número entero entre 1 y 100' using errcode = '22023';
  end if;
  if v_tipo = 'precio' and (public.num(p, 'precio', 'Precio') is null or public.num(p, 'precio', 'Precio') <= 0) then
    raise exception 'Poné el precio de la promoción' using errcode = '22023';
  end if;
  if v_tipo in ('unidad_pct', 'desde_pct') and public.num(p, 'pct', 'Porcentaje') is null then
    raise exception 'Poné el porcentaje de descuento' using errcode = '22023';
  end if;
  v_paga := case when v_tipo = 'lleva_paga' then public.num(p, 'paga', 'Paga') end;
  v_pct := case when v_tipo in ('unidad_pct', 'desde_pct') then public.num(p, 'pct', 'Porcentaje') end;
  v_precio := case when v_tipo = 'precio' then round(public.num(p, 'precio', 'Precio'), 2) end;
  if v_tipo = 'lleva_paga' and (v_paga is null or v_paga < 1 or v_paga >= v_n) then
    raise exception 'En "lleva N, paga M", M tiene que ser menor que N' using errcode = '22023';
  end if;
  if v_tipo in ('lleva_paga', 'precio', 'unidad_pct') and v_n < 2 then raise exception 'La cantidad tiene que ser 2 o más' using errcode = '22023'; end if;
  if v_pct is not null and (v_pct < 1 or v_pct > 100 or public.num(p, 'pct', 'Porcentaje') <> v_pct) then
    raise exception 'El porcentaje tiene que ser un número entero entre 1 y 100' using errcode = '22023';
  end if;
  if nullif(p ->> 'hasta', '')::date < nullif(p ->> 'desde', '')::date then
    raise exception 'La fecha "hasta" es anterior a "desde"' using errcode = '22023';
  end if;
  if v_id is null then
    insert into public.promociones (negocio_id, nombre, tipo, cantidad, paga, pct, precio, productos, desde, hasta, dias, formas, activa)
      values (v_neg, btrim(coalesce(p ->> 'nombre', '')), v_tipo, v_n, v_paga, v_pct, v_precio, v_prods,
              nullif(p ->> 'desde', '')::date, nullif(p ->> 'hasta', '')::date, v_dias, v_formas, coalesce((p ->> 'activa')::boolean, true))
      returning * into r;
  else
    update public.promociones set nombre = btrim(coalesce(p ->> 'nombre', '')), tipo = v_tipo, cantidad = v_n, paga = v_paga, pct = v_pct,
        precio = v_precio, productos = v_prods, desde = nullif(p ->> 'desde', '')::date, hasta = nullif(p ->> 'hasta', '')::date,
        dias = v_dias, formas = v_formas, activa = coalesce((p ->> 'activa')::boolean, true)
      where id = v_id and negocio_id = v_neg returning * into r;
    if not found then raise exception 'Promoción no encontrada' using errcode = 'P0002'; end if;
  end if;
  return public.promo_json(r);
end;
$$;

create or replace function public.borrar_promocion(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.requiere_admin();
  delete from public.promociones where id = p_id and negocio_id = public.requiere_negocio();
  if not found then raise exception 'Promoción no encontrada' using errcode = 'P0002'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- La venta: aplica las promociones
-- ---------------------------------------------------------------------
drop function public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb);
create or replace function public.registrar_venta(p_clave uuid, p_items jsonb, p_pagos jsonb, p_paga_con numeric default null,
  p_cliente_id bigint default null, p_forzar_limite boolean default false, p_descuento numeric default 0, p_autorizacion uuid default null,
  p_entrega jsonb default null, p_encargos jsonb default null, p_sin_promos bigint[] default null, p_promos numeric default null)
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
        values (v_neg, v.id, p.id, p.nombre, v_cant, v_precio, v_importe, p.costo, p.por_peso, p.categoria_id, p.precio)
        returning id into v_item;
      v_ids := v_ids || v_item;
      if not p.por_peso and v_etiqueta is null and v_precio = p.precio then
        v_lineas := v_lineas || jsonb_build_object('k', cardinality(v_ids), 'producto_id', p.id, 'cantidad', v_cant, 'precio', v_precio);
      end if;
      -- lo que no hay en stock y se entrega después: se cobra igual, pero del stock sale solo lo que se lleva ahora
      v_pend := round(coalesce(public.num(it, 'pendiente', 'Pendiente de entrega'), 0), 3);
      if v_pend < 0 or v_pend > v_cant then raise exception 'Lo pendiente de entrega de "%" no puede pasar lo vendido', p.nombre using errcode = '22023'; end if;
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
  if jsonb_array_length(v_lineas) > 0 then
    for pp in select value from jsonb_array_elements(public.promos_venta(v_neg, v_lineas, v_fp, p_sin_promos)) loop
      v_pd := (pp ->> 'descuento')::numeric;
      continue when v_pd <= 0;
      update public.venta_items set promo = v_pd, importe = importe - v_pd, promocion_id = (pp ->> 'promocion_id')::bigint, promo_nombre = pp ->> 'nombre'
        where id = v_ids[(pp ->> 'k')::int];
      v_promos := v_promos + v_pd;
    end loop;
  end if;
  if p_promos is not null and abs(p_promos - v_promos) > 0.005 then
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
      insert into public.caja (negocio_id, turno_id, usuario_id, tipo, concepto, monto, forma, venta_id)
        values (v_neg, t.id, v_u, 'ingreso', 'Venta #' || v.numero, v_b + v_rec, v_forma, v.id);
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


create or replace function public.venta_json(p_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'numero', v.numero, 'fecha', v.fecha, 'usuario', public.nombre_usuario(v.usuario_id),
    'turno_id', v.turno_id, 'subtotal', v.subtotal, 'descuento', v.descuento, 'descuento_renglones', v.descuento_renglones, 'descuento_promos', v.descuento_promos,
    'recargo', v.recargo, 'total', v.total, 'paga_con', v.paga_con,
    'autorizo', case when v.autorizo_id is not null then public.nombre_usuario(v.autorizo_id) end,
    'cliente', (select jsonb_build_object('id', c.id, 'nombre', c.nombre) from public.clientes c where c.id = v.cliente_id),
    'anulada', v.anulada, 'anulada_fecha', v.anulada_fecha, 'anulada_por', case when v.anulada then public.nombre_usuario(v.anulada_por) end,
    'motivo_anulacion', v.motivo_anulacion,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'producto_id', i.producto_id, 'nombre', i.nombre, 'cantidad', i.cantidad,
                         'precio', i.precio, 'precio_lista', i.precio_lista, 'importe', i.importe, 'por_peso', i.por_peso, 'promo', i.promo, 'promo_nombre', i.promo_nombre,
                         'devuelto', public.devuelto_item(i.id)) order by i.id)
                       from public.venta_items i where i.venta_id = v.id), '[]'::jsonb),
    'pagos', coalesce((select jsonb_agg(jsonb_build_object('forma', p.forma, 'monto', p.monto, 'recargo', p.recargo, 'pct_recargo', p.pct_recargo) order by p.id)
                       from public.venta_pagos p where p.venta_id = v.id), '[]'::jsonb),
    'devuelto', public.devuelto_venta(v.id),
    'pendientes', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'cantidad', e.cantidad, 'a_nombre', e.a_nombre) order by e.id)
      from public.entregas_pendientes e where e.venta_id = v.id and e.estado = 'pendiente'), '[]'::jsonb),
    'devoluciones', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'numero', d.numero, 'etiqueta', public.etiqueta_devolucion(d.numero),
        'fecha', d.fecha, 'usuario', public.nombre_usuario(d.usuario_id),
        'autorizo', case when d.autorizo_id is not null then public.nombre_usuario(d.autorizo_id) end,
        'forma', d.forma, 'total', d.total, 'motivo', d.motivo,
        'items', (select jsonb_agg(jsonb_build_object('nombre', x.nombre, 'cantidad', x.cantidad, 'importe', x.importe, 'vuelve_stock', x.vuelve_stock,
                    'por_peso', x.por_peso) order by x.id) from public.devolucion_items x where x.devolucion_id = d.id)) order by d.id)
      from public.devoluciones d where d.venta_id = v.id), '[]'::jsonb))
  from public.ventas v where v.id = p_id;
$$;


revoke all on function public.promo_descuentos(public.promociones, jsonb, int[]), public.promos_de_hoy(uuid),
  public.promos_venta(uuid, jsonb, text[], bigint[]), public.promo_json(public.promociones), public.promociones(),
  public.promociones_vigentes(), public.guardar_promocion(jsonb), public.borrar_promocion(bigint), public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb, bigint[], numeric)
  from public, anon, authenticated;
grant execute on function public.promociones(), public.promociones_vigentes(), public.guardar_promocion(jsonb), public.borrar_promocion(bigint),
  public.registrar_venta(uuid, jsonb, jsonb, numeric, bigint, boolean, numeric, uuid, jsonb, jsonb, bigint[], numeric) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 39, 'hora', now());
$$;
