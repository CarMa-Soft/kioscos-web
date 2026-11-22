-- =====================================================================
-- Pista del email de la cuenta del dueño, para "¿Olvidaste tu PIN?": la PC del local ve el email a medias
-- (h•••••@gmail.com), así el dueño recuerda cuál es sin que quede a la vista completo. Solo pide la cuenta iniciada
-- en la PC (no el PIN: se usa justo cuando no se lo recuerda).
-- =====================================================================
create or replace function public.pista_cuenta_dueno()
returns text language sql stable security definer set search_path = '' as $$
  select left(split_part(u.email, '@', 1), 1) || '•••••@' || split_part(u.email, '@', 2)
  from public.miembros m join auth.users u on u.id = m.cuenta
  where m.negocio_id = public.requiere_negocio() and m.rol = 'dueno' and u.email like '%@%'
  order by m.creado limit 1;
$$;
revoke all on function public.pista_cuenta_dueno() from public, anon, authenticated;
grant execute on function public.pista_cuenta_dueno() to authenticated;

create or replace function public.estado_app()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 38, 'hora', now());
$$;
