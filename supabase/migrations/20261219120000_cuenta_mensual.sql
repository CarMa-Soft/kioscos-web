-- =====================================================================
-- Cuenta mensual del cliente: muchos comercios fían por mes calendario (se cierra a fin de mes y se paga a principios del
-- siguiente). clientes.vence_dia (1 a 28): lo comprado en cada mes vence ese día del mes siguiente. null = por días
-- (clientes.plazo, o el general: 30). Lo cambia solo el dueño, desde la ficha del cliente.
-- =====================================================================
alter table public.clientes add column vence_dia smallint check (vence_dia between 1 and 28);

create or replace function public.cliente_json(c public.clientes)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'nombre', c.nombre, 'telefono', c.telefono, 'direccion', c.direccion,
    'limite', c.limite, 'plazo', c.plazo, 'vence_dia', c.vence_dia, 'notas', c.notas, 'activo', c.activo, 'saldo', public.saldo_cliente(c.id));
$$;

create or replace function public.guardar_cliente(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_nombre text := btrim(coalesce(p ->> 'nombre', '')); v_limite numeric := round(public.num(p, 'limite', 'Límite'), 2);
  v_hay_plazo boolean := p ? 'plazo'; v_plazo numeric := public.num(p, 'plazo', 'Plazo');
  v_hay_dia boolean := p ? 'vence_dia'; v_dia numeric := public.num(p, 'vence_dia', 'Día de vencimiento');
  c public.clientes; r public.clientes;
begin
  perform public.requiere_usuario();
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if v_limite < 0 then raise exception 'El límite no puede ser negativo' using errcode = '22023'; end if;
  if v_plazo is not null and (v_plazo < 0 or v_plazo > 365 or v_plazo <> trunc(v_plazo)) then
    raise exception 'El plazo tiene que ser de 0 a 365 días' using errcode = '22023';
  end if;
  if v_dia is not null and (v_dia < 1 or v_dia > 28 or v_dia <> trunc(v_dia)) then
    raise exception 'El día de vencimiento tiene que ser del 1 al 28' using errcode = '22023';
  end if;
  if exists (select 1 from public.clientes where negocio_id = v_neg and activo and lower(btrim(nombre)) = lower(v_nombre) and id is distinct from v_id) then
    raise exception 'Ya hay un cliente con ese nombre' using errcode = '23505';
  end if;
  if v_id is not null then c := public.requiere_cliente(v_id); end if;
  if not public.es_admin() and v_limite is distinct from coalesce(c.limite, 0) and v_limite is not null then
    raise exception 'El límite de fiado lo cambia solo el dueño' using errcode = '42501';
  end if;
  if not public.es_admin() and v_hay_plazo and v_plazo::integer is distinct from c.plazo then
    raise exception 'El plazo lo cambia solo el dueño' using errcode = '42501';
  end if;
  if not public.es_admin() and v_hay_dia and v_dia::integer is distinct from c.vence_dia then
    raise exception 'El plazo lo cambia solo el dueño' using errcode = '42501';
  end if;
  if v_id is null then
    insert into public.clientes (negocio_id, nombre, telefono, direccion, limite, plazo, vence_dia, notas)
      values (v_neg, v_nombre, nullif(btrim(p ->> 'telefono'), ''), nullif(btrim(p ->> 'direccion'), ''), coalesce(v_limite, 0),
        case when v_hay_plazo then v_plazo::integer end, case when v_hay_dia then v_dia::integer end, nullif(btrim(p ->> 'notas'), ''))
      returning * into r;
  else
    update public.clientes set nombre = v_nombre, telefono = nullif(btrim(p ->> 'telefono'), ''), direccion = nullif(btrim(p ->> 'direccion'), ''),
        limite = coalesce(v_limite, limite), plazo = case when v_hay_plazo then v_plazo::integer else plazo end,
        vence_dia = case when v_hay_dia then v_dia::integer else vence_dia end, notas = nullif(btrim(p ->> 'notas'), '')
      where id = v_id returning * into r;
    -- con otro plazo cambian los vencimientos (se calculan al mostrarlos); lo aplicado no cambia
  end if;
  return public.cliente_json(r);
end;
$$;

create or replace function public.deudas_cliente(p_cliente bigint)
returns table (venta_id bigint, deuda_id bigint, numero integer, concepto text, fecha timestamptz, vencimiento date,
               importe numeric, aplicado numeric, pendiente numeric, pagada timestamptz)
language sql stable security definer set search_path = '' as $$
  with cl as (select coalesce(c.plazo, public.plazo_clientes(c.negocio_id)) as plazo, c.vence_dia, public.zona_horaria(c.negocio_id) as z
              from public.clientes c where c.id = p_cliente),
  v as (select m.venta_id, sum(m.monto) as s, min(m.id) as primero from public.cc m where m.cliente_id = p_cliente and m.venta_id is not null group by m.venta_id),
  d as (
    select v.venta_id, null::bigint as deuda_id, ve.numero, 'Compra #' || ve.numero as concepto, ve.fecha, v.s as importe, v.primero as orden
      from v join public.ventas ve on ve.id = v.venta_id where v.s > 0
    union all
    select null, m.id, null, m.concepto, m.fecha, m.monto, m.id
      from public.cc m where m.cliente_id = p_cliente and m.venta_id is null and m.tipo = 'ajuste' and m.monto > 0)
  select d.venta_id, d.deuda_id, d.numero, d.concepto, d.fecha,
    -- cuenta mensual: lo de cada mes vence el día vence_dia del mes siguiente; si no, la fecha + el plazo en días
    case when (select vence_dia from cl) is not null
      then (date_trunc('month', (d.fecha at time zone (select z from cl))::date) + interval '1 month')::date + ((select vence_dia from cl) - 1)
      else (d.fecha at time zone (select z from cl))::date + (select plazo from cl) end as vencimiento,
    d.importe, x.aplicado, d.importe - x.aplicado, case when d.importe - x.aplicado <= 0.004 then x.ultima end
  from d cross join lateral (
    select coalesce(sum(a.monto), 0) as aplicado, max(a.fecha) as ultima from public.aplicaciones_cli a
    where (d.venta_id is not null and a.venta_id = d.venta_id) or (d.deuda_id is not null and a.deuda_id = d.deuda_id)) x
  order by 6, d.fecha, d.orden;   -- con la misma fecha, en el orden en que se cargaron
$$;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 36, 'hora', now());
$$;
