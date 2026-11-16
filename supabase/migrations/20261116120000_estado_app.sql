-- Etapa 1: función mínima para comprobar que la app publicada llega a la base y que las migraciones se aplican.
-- 'base' sube cuando una migración cambia algo que la app necesita saber.
create or replace function public.estado_app()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('app', 'Kioscos y Almacenes', 'base', 1, 'hora', now());
$$;

-- Por defecto Postgres deja ejecutar cualquier función a todos: se cierra y se abre solo a quien la necesita
revoke all on function public.estado_app() from public;
grant execute on function public.estado_app() to anon, authenticated;
