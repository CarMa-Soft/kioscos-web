-- =====================================================================
-- Etapa 8b: mandar la factura desde el celular
-- La PC (el dueño, en "Cargar desde factura") pide un código: la base guarda solo su huella (sha256) y lo da una vez.
-- La PC lo muestra como QR (celu.html#código, vence a los 15 minutos). El celular, sin iniciar sesión, saca las fotos y
-- las manda a la función de Supabase "subir-factura", que con la clave de servicio toma el código, las lee con IA y deja
-- el resultado acá. La PC consulta cada 2 segundos y, cuando está lista, abre la revisión como con un archivo.
-- No hace falta que el celular esté en la misma red: alcanza con internet.
-- =====================================================================

create table public.subidas_celular (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  usuario_id bigint not null,
  huella text not null unique,                 -- sha256 del código (el código no se guarda)
  creado timestamptz not null default now(),
  vence timestamptz not null,
  estado text not null default 'esperando' check (estado in ('esperando', 'leyendo', 'lista', 'error', 'entregada', 'cancelada')),
  paginas integer,
  error text,
  resultado jsonb,                             -- { factura, uso } hasta que la PC lo retira
  foreign key (usuario_id, negocio_id) references public.usuarios (id, negocio_id)
);
create index subidas_celular_negocio on public.subidas_celular (negocio_id, creado);
alter table public.subidas_celular enable row level security;
revoke all on public.subidas_celular from anon, authenticated;

create or replace function public.huella_subida(p_codigo text)
returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(coalesce(p_codigo, ''), 'sha256'), 'hex');
$$;

-- La PC pide un código nuevo (solo el dueño). Borra los viejos del negocio y cancela los que quedaron esperando.
create or replace function public.crear_subida_celular()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_u bigint := public.requiere_admin(); v_codigo text; v_id bigint; v_vence timestamptz;
begin
  delete from public.subidas_celular where negocio_id = v_neg and creado < now() - interval '1 day';
  if (select count(*) from public.subidas_celular where negocio_id = v_neg and creado > now() - interval '1 hour') >= 30 then
    raise exception 'Se pidieron demasiados códigos en la última hora: probá más tarde' using errcode = 'P0001';
  end if;
  update public.subidas_celular set estado = 'cancelada', resultado = null
    where negocio_id = v_neg and usuario_id = v_u and estado in ('esperando', 'error');
  v_codigo := encode(extensions.gen_random_bytes(24), 'hex');
  v_vence := now() + interval '15 minutes';
  insert into public.subidas_celular (negocio_id, usuario_id, huella, vence)
    values (v_neg, v_u, public.huella_subida(v_codigo), v_vence) returning id into v_id;
  return jsonb_build_object('id', v_id, 'codigo', v_codigo, 'vence', v_vence, 'minutos', 15);
end;
$$;

-- La PC consulta cómo va. Cuando está lista, entrega el resultado una sola vez (y lo borra de la base).
create or replace function public.estado_subida_celular(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); s public.subidas_celular;
begin
  perform public.requiere_admin();
  select * into s from public.subidas_celular where id = p_id and negocio_id = v_neg for update;
  if not found then raise exception 'No se encontró el pedido' using errcode = 'P0002'; end if;
  if s.estado in ('esperando', 'error') and s.vence < now() then
    return jsonb_build_object('estado', 'vencido');
  end if;
  if s.estado = 'lista' then
    update public.subidas_celular set estado = 'entregada', resultado = null where id = s.id;
    return jsonb_build_object('estado', 'lista', 'paginas', s.paginas, 'resultado', s.resultado);
  end if;
  return jsonb_build_object('estado', s.estado, 'paginas', s.paginas, 'error', s.error);
end;
$$;

create or replace function public.cancelar_subida_celular(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  update public.subidas_celular set estado = 'cancelada', resultado = null
    where id = p_id and negocio_id = v_neg and estado in ('esperando', 'error');
end;
$$;

-- ---------------------------------------------------------------------
-- Lo que usa la función de Supabase "subir-factura" (solo con la clave de servicio)
-- ---------------------------------------------------------------------
-- El celular abre la página: ¿el código sirve? (para mostrar el nombre del negocio o "venció")
create or replace function public.revisar_subida_celular(p_codigo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s public.subidas_celular;
begin
  select * into s from public.subidas_celular where huella = public.huella_subida(p_codigo);
  if not found or s.estado in ('cancelada', 'entregada') then
    raise exception 'Este código ya no sirve: pedí uno nuevo en la PC' using errcode = 'P0001';
  end if;
  if s.estado = 'lista' then return jsonb_build_object('estado', 'lista'); end if;
  if s.vence < now() then raise exception 'Este código venció: pedí uno nuevo en la PC' using errcode = 'P0001'; end if;
  return jsonb_build_object('estado', s.estado, 'negocio', (select nombre from public.negocios where id = s.negocio_id), 'vence', s.vence);
end;
$$;

-- Llegaron las fotos: el código pasa a "leyendo" (nadie más lo puede usar mientras tanto). Controla el límite de lecturas.
create or replace function public.tomar_subida_celular(p_codigo text, p_paginas integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s public.subidas_celular;
begin
  select * into s from public.subidas_celular where huella = public.huella_subida(p_codigo) for update;
  if not found or s.estado not in ('esperando', 'error', 'leyendo') then
    raise exception 'Este código ya no sirve: pedí uno nuevo en la PC' using errcode = 'P0001';
  end if;
  if s.vence < now() then raise exception 'Este código venció: pedí uno nuevo en la PC' using errcode = 'P0001'; end if;
  if s.estado = 'leyendo' then raise exception 'Ya se está leyendo una factura con este código: esperá a que termine' using errcode = 'P0001'; end if;
  if (select count(*) from public.lecturas_ia where negocio_id = s.negocio_id and fecha > now() - interval '1 day') >= 60 then
    raise exception 'Ya se leyeron 60 facturas en las últimas 24 horas: probá de nuevo más tarde' using errcode = 'P0001';
  end if;
  update public.subidas_celular set estado = 'leyendo', paginas = p_paginas, error = null where id = s.id;
  return jsonb_build_object('id', s.id, 'negocio_id', s.negocio_id, 'usuario_id', s.usuario_id);
end;
$$;

-- Terminó la lectura: con resultado ({factura, uso}) queda lista para la PC; con error, se puede volver a mandar
create or replace function public.terminar_subida_celular(p_id bigint, p_resultado jsonb, p_error text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.subidas_celular
    set estado = case when p_error is null then 'lista' else 'error' end,
        resultado = case when p_error is null then p_resultado end, error = left(p_error, 300)
    where id = p_id and estado = 'leyendo';
end;
$$;

revoke all on function public.huella_subida(text), public.crear_subida_celular(), public.estado_subida_celular(bigint),
  public.cancelar_subida_celular(bigint), public.revisar_subida_celular(text), public.tomar_subida_celular(text, integer),
  public.terminar_subida_celular(bigint, jsonb, text) from public, anon, authenticated;
grant execute on function public.crear_subida_celular(), public.estado_subida_celular(bigint), public.cancelar_subida_celular(bigint) to authenticated;
grant execute on function public.revisar_subida_celular(text), public.tomar_subida_celular(text, integer),
  public.terminar_subida_celular(bigint, jsonb, text) to service_role;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 15, 'hora', now());
$$;
