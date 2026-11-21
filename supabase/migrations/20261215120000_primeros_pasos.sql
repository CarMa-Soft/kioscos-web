-- =====================================================================
-- Primeros pasos en Hoy: inicio() trae, para el dueño, arranque = { hubo_turno, hubo_venta } (si alguna vez se abrió la caja y
-- si alguna vez se vendió). El resto de los pasos la pantalla los sabe sola (datos del ticket, productos, impresora, instalar).
-- =====================================================================
create or replace function public.inicio()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_usuario(); v_admin boolean := public.es_admin();
  v_tz text; v_d1 timestamptz; v_d2 timestamptz; t public.turnos; r jsonb;
begin
  v_tz := public.zona_horaria(v_neg);
  v_d1 := (now() at time zone v_tz)::date::timestamp at time zone v_tz;
  v_d2 := v_d1 + interval '1 day';
  select * into t from public.turnos where negocio_id = v_neg and cierre is null;
  with
  vs as (select * from public.ventas where negocio_id = v_neg and not anulada and fecha >= v_d1 and fecha < v_d2 and (v_admin or usuario_id = v_u)),
  ds as (select dv.* from public.devoluciones dv join public.ventas vv on vv.id = dv.venta_id
         where dv.negocio_id = v_neg and not vv.anulada and dv.fecha >= v_d1 and dv.fecha < v_d2 and (v_admin or vv.usuario_id = v_u))
  select jsonb_build_object(
    'propias', not v_admin,
    'tickets', (select count(*) from vs),
    'devuelto', (select coalesce(sum(total), 0) from ds),
    'total', (select coalesce(sum(total), 0) from vs) - (select coalesce(sum(total), 0) from ds),
    'ganancia', case when v_admin then
        (select coalesce(sum(total), 0) from vs) - (select coalesce(sum(total), 0) from ds)
        - (select coalesce(sum(i.cantidad * i.costo), 0) from public.venta_items i join vs on vs.id = i.venta_id)
        + (select coalesce(sum(x.cantidad * x.costo), 0) from public.devolucion_items x join ds on ds.id = x.devolucion_id where x.vuelve_stock)
      end,
    'ultimas', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'numero', numero, 'fecha', fecha, 'total', total,
        'devuelto', public.devuelto_venta(id), 'usuario', public.nombre_usuario(usuario_id),
        'resumen', (select string_agg(i.nombre, ', ' order by i.id) from public.venta_items i where i.venta_id = x.id)) order by id desc), '[]'::jsonb)
      from (select * from vs order by id desc limit 8) x),
    'turno', case when t.id is null then null else jsonb_build_object('usuario', public.nombre_usuario(t.usuario_id), 'apertura', t.apertura,
        'esperado', public.efectivo_esperado(t.id)) end,
    'fiado_pendiente', public.fiado_pendiente(v_neg),
    -- para los primeros pasos (solo el dueño): si alguna vez se abrió la caja y si alguna vez se vendió
    'arranque', case when v_admin then jsonb_build_object(
        'hubo_turno', exists (select 1 from public.turnos where negocio_id = v_neg),
        'hubo_venta', exists (select 1 from public.ventas where negocio_id = v_neg)) end
  ) into r;
  return r;
end;
$$;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 32, 'hora', now());
$$;
