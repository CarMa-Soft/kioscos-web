-- =====================================================================
-- Etapa 2: varios negocios, cuentas y usuarios con PIN
--
-- Cuentas (Supabase Auth, email y contraseña): las del dueño ('dueno') y la de la PC del local ('local').
--   Cada cuenta pertenece a un solo negocio (tabla miembros).
-- Usuarios (como en la app local): las personas que usan la app, con su PIN. Rol 'admin' (dueño) o 'empleado'.
--   La PC entra una sola vez con la cuenta del local; después cada uno elige su nombre y pone su PIN.
--   El PIN abre una sesión (tabla sesiones) atada a la cuenta: la pantalla manda su token en el
--   encabezado x-usuario-kiosco y las funciones saben quién es y qué puede hacer.
--
-- Seguridad: ninguna tabla se expone directo a la API. Todo pasa por funciones que controlan el negocio y el rol.
-- =====================================================================

create table public.negocios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(btrim(nombre)) between 1 and 80),
  activo boolean not null default true,      -- false: nadie del negocio puede entrar (sus datos quedan)
  creado timestamptz not null default now()
);

create table public.miembros (
  cuenta uuid primary key references auth.users (id) on delete cascade,   -- una cuenta, un negocio
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  rol text not null check (rol in ('dueno', 'local')),
  creado timestamptz not null default now()
);
create index miembros_negocio on public.miembros (negocio_id);

create table public.usuarios (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 40),
  rol text not null check (rol in ('admin', 'empleado')),
  activo boolean not null default true,
  pin_hash text not null,                    -- bcrypt; nunca sale de la base
  intentos integer not null default 0,       -- PIN incorrectos seguidos
  bloqueado_hasta timestamptz,
  creado timestamptz not null default now()
);
create unique index usuarios_nombre_unico on public.usuarios (negocio_id, lower(btrim(nombre)));

create table public.sesiones (
  token uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  usuario_id bigint not null references public.usuarios (id) on delete cascade,
  cuenta uuid not null references auth.users (id) on delete cascade,
  creada timestamptz not null default now(),
  vence timestamptz not null
);
create index sesiones_cuenta on public.sesiones (cuenta);
create index sesiones_usuario on public.sesiones (usuario_id);

create table public.config (
  negocio_id uuid not null references public.negocios (id) on delete cascade,
  clave text not null check (clave ~ '^[a-z_]{1,40}$'),
  valor jsonb not null,
  primary key (negocio_id, clave)
);

alter table public.negocios enable row level security;
alter table public.miembros enable row level security;
alter table public.usuarios enable row level security;
alter table public.sesiones enable row level security;
alter table public.config enable row level security;

-- ---------------------------------------------------------------------
-- Quién está del otro lado
-- ---------------------------------------------------------------------

-- Negocio de la cuenta que inició sesión (null si no tiene, o si el negocio está suspendido)
create or replace function public.mi_negocio()
returns uuid language sql stable security definer set search_path = '' as $$
  select m.negocio_id
  from public.miembros m join public.negocios n on n.id = m.negocio_id
  where m.cuenta = auth.uid() and n.activo;
$$;

-- Token de la sesión de usuario que manda la pantalla (encabezado x-usuario-kiosco), o null
create or replace function public.token_usuario()
returns uuid language plpgsql stable set search_path = '' as $$
declare v text;
begin
  v := nullif(current_setting('request.headers', true), '')::json ->> 'x-usuario-kiosco';
  if v is null or v !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return null; end if;
  return v::uuid;
end;
$$;

-- Usuario (con PIN) que está usando la app: la sesión tiene que ser de esta cuenta, de su negocio y no estar vencida
create or replace function public.usuario_actual_id()
returns bigint language sql stable security definer set search_path = '' as $$
  select u.id
  from public.sesiones s join public.usuarios u on u.id = s.usuario_id
  where s.token = public.token_usuario() and s.cuenta = auth.uid() and s.negocio_id = public.mi_negocio()
    and s.vence > now() and u.activo;
$$;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select u.rol = 'admin' from public.usuarios u where u.id = public.usuario_actual_id()), false);
$$;

-- Corta si la cuenta no tiene un negocio activo; devuelve el negocio
create or replace function public.requiere_negocio()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid := public.mi_negocio();
begin
  if v is null then raise exception 'Esta cuenta no tiene un negocio activo' using errcode = '42501'; end if;
  return v;
end;
$$;

-- Corta si no hay un usuario con PIN; devuelve su id
create or replace function public.requiere_usuario()
returns bigint language plpgsql stable security definer set search_path = '' as $$
declare v bigint;
begin
  perform public.requiere_negocio();
  v := public.usuario_actual_id();
  if v is null then raise exception 'La sesión del usuario venció: volvé a elegir tu nombre y poner tu PIN' using errcode = '42501', hint = 'sesion'; end if;
  return v;
end;
$$;

create or replace function public.requiere_admin()
returns bigint language plpgsql stable security definer set search_path = '' as $$
declare v bigint := public.requiere_usuario();
begin
  if not public.es_admin() then raise exception 'Esto solo lo puede hacer el dueño' using errcode = '42501'; end if;
  return v;
end;
$$;

create or replace function public.hash_pin(p_pin text)
returns text language plpgsql volatile set search_path = '' as $$
begin
  if coalesce(p_pin, '') !~ '^\d{4,8}$' then raise exception 'El PIN tiene que tener entre 4 y 8 números' using errcode = '22023'; end if;
  return extensions.crypt(p_pin, extensions.gen_salt('bf', 10));
end;
$$;

-- ---------------------------------------------------------------------
-- Funciones que usa la app
-- ---------------------------------------------------------------------

-- Lo que la app necesita al abrir: el negocio, los usuarios para elegir, la configuración y quién es (si ya puso el PIN)
create or replace function public.datos_inicio()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_yo bigint := public.usuario_actual_id();
begin
  return jsonb_build_object(
    'negocio', (select jsonb_build_object('id', n.id, 'nombre', n.nombre) from public.negocios n where n.id = v_neg),
    'cuenta', (select jsonb_build_object('rol', m.rol) from public.miembros m where m.cuenta = auth.uid()),
    'usuarios', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nombre', u.nombre, 'rol', u.rol) order by u.rol, u.nombre)
                          from public.usuarios u where u.negocio_id = v_neg and u.activo), '[]'::jsonb),
    'config', coalesce((select jsonb_object_agg(c.clave, c.valor) from public.config c where c.negocio_id = v_neg), '{}'::jsonb),
    'yo', (select jsonb_build_object('id', u.id, 'nombre', u.nombre, 'rol', u.rol) from public.usuarios u where u.id = v_yo)
  );
end;
$$;

-- Entrar con el PIN. Devuelve { token, vence, usuario } o { error }: los errores no se lanzan para que quede
-- anotado el intento fallido (5 seguidos bloquean al usuario 5 minutos).
create or replace function public.iniciar_usuario(p_usuario_id bigint, p_pin text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); u public.usuarios; v_token uuid; v_vence timestamptz;
begin
  select * into u from public.usuarios where id = p_usuario_id and negocio_id = v_neg and activo for update;
  if not found then return jsonb_build_object('error', 'Usuario no encontrado'); end if;
  if u.bloqueado_hasta > now() then
    return jsonb_build_object('error', format('Demasiados intentos: probá de nuevo en %s minuto(s)', ceil(extract(epoch from u.bloqueado_hasta - now()) / 60)));
  end if;
  if coalesce(p_pin, '') = '' or extensions.crypt(p_pin, u.pin_hash) <> u.pin_hash then
    -- al quinto seguido se bloquea 5 minutos y el contador vuelve a empezar
    update public.usuarios
      set intentos = case when intentos + 1 >= 5 then 0 else intentos + 1 end,
          bloqueado_hasta = case when intentos + 1 >= 5 then now() + interval '5 minutes' else bloqueado_hasta end
      where id = u.id;
    return jsonb_build_object('error', 'PIN incorrecto');
  end if;
  update public.usuarios set intentos = 0, bloqueado_hasta = null where id = u.id;
  delete from public.sesiones where cuenta = auth.uid() and (vence <= now() or token = public.token_usuario());
  v_vence := now() + interval '16 hours';
  insert into public.sesiones (negocio_id, usuario_id, cuenta, vence) values (v_neg, u.id, auth.uid(), v_vence) returning token into v_token;
  return jsonb_build_object('token', v_token, 'vence', v_vence, 'usuario', jsonb_build_object('id', u.id, 'nombre', u.nombre, 'rol', u.rol));
end;
$$;

-- Salir (cambiar de usuario): cierra la sesión de este token
create or replace function public.cerrar_usuario()
returns void language sql volatile security definer set search_path = '' as $$
  delete from public.sesiones where token = public.token_usuario() and cuenta = auth.uid();
$$;

-- Crear o editar un usuario (solo dueño). p_pin vacío al editar = no cambia. Tiene que quedar al menos un dueño activo.
create or replace function public.guardar_usuario(p_id bigint, p_nombre text, p_rol text, p_activo boolean default true, p_pin text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); v_id bigint; v_nombre text := btrim(coalesce(p_nombre, ''));
begin
  perform public.requiere_admin();
  if v_nombre = '' then raise exception 'Falta el nombre' using errcode = '22023'; end if;
  if p_rol not in ('admin', 'empleado') then raise exception 'Rol inválido' using errcode = '22023'; end if;
  if exists (select 1 from public.usuarios where negocio_id = v_neg and lower(btrim(nombre)) = lower(v_nombre) and id is distinct from p_id) then
    raise exception 'Ya hay un usuario con ese nombre' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.usuarios (negocio_id, nombre, rol, activo, pin_hash)
      values (v_neg, v_nombre, p_rol, true, public.hash_pin(p_pin)) returning id into v_id;
  else
    update public.usuarios set nombre = v_nombre, rol = p_rol, activo = coalesce(p_activo, true),
        pin_hash = case when coalesce(p_pin, '') = '' then pin_hash else public.hash_pin(p_pin) end,
        intentos = case when coalesce(p_pin, '') = '' then intentos else 0 end,
        bloqueado_hasta = case when coalesce(p_pin, '') = '' then bloqueado_hasta end
      where id = p_id and negocio_id = v_neg returning id into v_id;
    if v_id is null then raise exception 'Usuario no encontrado' using errcode = 'P0002'; end if;
    -- desactivado o con otro PIN: se cierran sus sesiones (menos la de quien lo está editando)
    if not coalesce(p_activo, true) or coalesce(p_pin, '') <> '' then
      delete from public.sesiones where usuario_id = v_id and token is distinct from public.token_usuario();
    end if;
  end if;
  if not exists (select 1 from public.usuarios where negocio_id = v_neg and rol = 'admin' and activo) then
    raise exception 'Tiene que quedar al menos un usuario Dueño activo' using errcode = '22023';
  end if;
  return (select jsonb_build_object('id', id, 'nombre', nombre, 'rol', rol, 'activo', activo) from public.usuarios where id = v_id);
end;
$$;

create or replace function public.cambiar_mi_pin(p_actual text, p_nuevo text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint := public.requiere_usuario(); v_hash text;
begin
  select pin_hash into v_hash from public.usuarios where id = v_id;
  if extensions.crypt(coalesce(p_actual, ''), v_hash) <> v_hash then raise exception 'El PIN actual no es correcto' using errcode = '22023'; end if;
  update public.usuarios set pin_hash = public.hash_pin(p_nuevo) where id = v_id;
  delete from public.sesiones where usuario_id = v_id and token is distinct from public.token_usuario();
end;
$$;

-- Guardar una clave de la configuración del negocio (solo dueño)
create or replace function public.guardar_config(p_clave text, p_valor jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio();
begin
  perform public.requiere_admin();
  if coalesce(p_clave, '') !~ '^[a-z_]{1,40}$' then raise exception 'Clave de configuración inválida' using errcode = '22023'; end if;
  if p_valor is null or pg_column_size(p_valor) > 65536 then raise exception 'Valor de configuración inválido' using errcode = '22023'; end if;
  insert into public.config (negocio_id, clave, valor) values (v_neg, p_clave, p_valor)
    on conflict (negocio_id, clave) do update set valor = excluded.valor;
end;
$$;

-- ---------------------------------------------------------------------
-- Alta de un negocio (solo desde el SQL Editor de Supabase, nunca desde la app)
-- Antes: crear en Authentication → Users las cuentas del dueño y de la PC del local (con "Auto Confirm User").
-- Ej.: select public.admin_alta_negocio('Despensa Tito', 'tito@mail.com', 'local.tito@mail.com', 'Tito', '1234');
-- ---------------------------------------------------------------------
create or replace function public.admin_alta_negocio(p_nombre text, p_email_dueno text, p_email_local text, p_usuario text, p_pin text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid; v_dueno uuid; v_local uuid;
begin
  select id into v_dueno from auth.users where lower(email) = lower(btrim(p_email_dueno));
  if v_dueno is null then raise exception 'No existe la cuenta %: creala primero en Authentication → Users', p_email_dueno; end if;
  if p_email_local is not null then
    select id into v_local from auth.users where lower(email) = lower(btrim(p_email_local));
    if v_local is null then raise exception 'No existe la cuenta %: creala primero en Authentication → Users', p_email_local; end if;
  end if;
  if exists (select 1 from public.miembros where cuenta in (v_dueno, v_local)) then
    raise exception 'Alguna de esas cuentas ya pertenece a otro negocio';
  end if;
  insert into public.negocios (nombre) values (btrim(p_nombre)) returning id into v_neg;
  insert into public.miembros (cuenta, negocio_id, rol) values (v_dueno, v_neg, 'dueno');
  if v_local is not null then insert into public.miembros (cuenta, negocio_id, rol) values (v_local, v_neg, 'local'); end if;
  insert into public.usuarios (negocio_id, nombre, rol, pin_hash) values (v_neg, btrim(p_usuario), 'admin', public.hash_pin(p_pin));
  insert into public.config (negocio_id, clave, valor) values (v_neg, 'negocio', jsonb_build_object('nombre', btrim(p_nombre)));
  return v_neg;
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos: Postgres deja ejecutar cualquier función a todos. Se cierra todo y se abre solo lo necesario.
-- ---------------------------------------------------------------------
revoke all on function public.mi_negocio(), public.token_usuario(), public.usuario_actual_id(), public.es_admin(),
  public.requiere_negocio(), public.requiere_usuario(), public.requiere_admin(), public.hash_pin(text),
  public.datos_inicio(), public.iniciar_usuario(bigint, text), public.cerrar_usuario(),
  public.guardar_usuario(bigint, text, text, boolean, text), public.cambiar_mi_pin(text, text),
  public.guardar_config(text, jsonb), public.admin_alta_negocio(text, text, text, text, text)
  from public, anon, authenticated;

-- Las que llama la app (con una cuenta iniciada)
grant execute on function public.datos_inicio(), public.iniciar_usuario(bigint, text), public.cerrar_usuario(),
  public.guardar_usuario(bigint, text, text, boolean, text), public.cambiar_mi_pin(text, text),
  public.guardar_config(text, jsonb)
  to authenticated;

-- Las de control, para usarlas en reglas (RLS) y funciones de las próximas etapas
grant execute on function public.mi_negocio(), public.token_usuario(), public.usuario_actual_id(), public.es_admin()
  to authenticated;

-- Las tablas no se exponen a la API: sin permisos para anon ni authenticated
revoke all on public.negocios, public.miembros, public.usuarios, public.sesiones, public.config from anon, authenticated;

-- La app sabe que la base ya tiene esta etapa
create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 2, 'hora', now());
$$;
