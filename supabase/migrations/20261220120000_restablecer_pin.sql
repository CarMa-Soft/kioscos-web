-- =====================================================================
-- "¿Olvidaste tu PIN?": con el email y la contraseña de la CUENTA DEL DUEÑO (no la de la PC del local) se le pone un PIN
-- nuevo a un usuario con rol Dueño. La pantalla inicia esa cuenta aparte, solo para esta llamada (no cambia la sesión de la
-- PC ni guarda nada). Se desbloquea el usuario y se cierran sus otras sesiones.
-- =====================================================================
create or replace function public.restablecer_pin(p_usuario_id bigint, p_pin text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_neg uuid := public.requiere_negocio(); u public.usuarios;
begin
  if not exists (select 1 from public.miembros where cuenta = auth.uid() and negocio_id = v_neg and rol = 'dueno') then
    raise exception 'Hace falta la cuenta del dueño del negocio (no la de la PC del local)' using errcode = '42501';
  end if;
  select * into u from public.usuarios where id = p_usuario_id and negocio_id = v_neg for update;
  if not found then raise exception 'Usuario no encontrado' using errcode = 'P0002'; end if;
  if u.rol <> 'admin' then raise exception 'Solo se restablece el PIN de un dueño; el del empleado lo cambia el dueño en Usuarios' using errcode = '42501'; end if;
  update public.usuarios set pin_hash = public.hash_pin(p_pin), intentos = 0, bloqueado_hasta = null, activo = true where id = u.id;
  delete from public.sesiones where usuario_id = u.id;
  return jsonb_build_object('nombre', u.nombre);
end;
$$;
revoke all on function public.restablecer_pin(bigint, text) from public, anon, authenticated;
grant execute on function public.restablecer_pin(bigint, text) to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 37, 'hora', now());
$$;
