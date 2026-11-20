-- =====================================================================
-- Entrar sin PIN en un negocio de una sola persona. El dueño lo activa (config entrar_sin_pin = true, en Usuarios) y vale
-- solo mientras haya un único usuario activo y sea dueño: si se agrega otro usuario, vuelve a pedirse el PIN solo.
-- La cuenta del negocio (email y contraseña) se sigue pidiendo como siempre, una vez por PC.
-- =====================================================================
create or replace function public.entra_sin_pin(p_neg uuid, p_usuario bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select c.valor = 'true'::jsonb from public.config c where c.negocio_id = p_neg and c.clave = 'entrar_sin_pin'), false)
     and (select count(*) from public.usuarios u where u.negocio_id = p_neg and u.activo) = 1
     and exists (select 1 from public.usuarios u where u.id = p_usuario and u.negocio_id = p_neg and u.activo and u.rol = 'admin');
$$;
revoke all on function public.entra_sin_pin(uuid, bigint) from public, anon, authenticated;

create or replace function public.iniciar_usuario(p_usuario_id bigint, p_pin text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); u public.usuarios; v_token uuid; v_vence timestamptz;
begin
  select * into u from public.usuarios where id = p_usuario_id and negocio_id = v_neg and activo for update;
  if not found then return jsonb_build_object('error', 'Usuario no encontrado'); end if;
  if u.bloqueado_hasta > now() then
    return jsonb_build_object('error', format('Demasiados intentos: probá de nuevo en %s minuto(s)', ceil(extract(epoch from u.bloqueado_hasta - now()) / 60)));
  end if;
  -- sin PIN solo si el dueño lo activó y es el único usuario activo (ver entra_sin_pin)
  if not (coalesce(p_pin, '') = '' and public.entra_sin_pin(v_neg, u.id))
     and (coalesce(p_pin, '') = '' or extensions.crypt(p_pin, u.pin_hash) <> u.pin_hash) then
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

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 29, 'hora', now());
$$;
