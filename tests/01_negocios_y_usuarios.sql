-- =====================================================================
-- Pruebas: separación entre negocios, cuentas y usuarios con PIN (etapa 2)
-- Corren dentro de una transacción que se deshace al final (ver .github/workflows/pruebas.yml): no dejan nada en la base.
-- Cada prueba que falla corta todo con "PRUEBA FALLIDA: ...".
-- =====================================================================

-- Ayudas, en un esquema que también se deshace
create schema pruebas;
grant usage on schema pruebas to anon, authenticated;

-- Simula lo que manda Supabase en cada pedido: la cuenta que inició sesión y el token del usuario con PIN
create function pruebas.como(p_cuenta uuid, p_token text default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_cuenta::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_cuenta is null then '{"role":"anon"}' else json_build_object('sub', p_cuenta, 'role', 'authenticated')::text end, true);
  perform set_config('request.headers',
    case when p_token is null then '{}' else json_build_object('x-usuario-kiosco', p_token)::text end, true);
end $$;

create function pruebas.ok(p_cond boolean, p_que text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'PRUEBA FALLIDA: %', p_que; end if;
  raise notice 'ok: %', p_que;
end $$;

-- La instrucción tiene que dar un error que coincida con el patrón
create function pruebas.falla(p_sql text, p_patron text, p_que text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm !~* p_patron then raise exception 'PRUEBA FALLIDA: % — dio "%", se esperaba /%/', p_que, sqlerrm, p_patron; end if;
    raise notice 'ok: %', p_que;
    return;
  end;
  raise exception 'PRUEBA FALLIDA: % — no dio error (se esperaba /%/)', p_que, p_patron;
end $$;

grant execute on all functions in schema pruebas to anon, authenticated;

-- Cuentas de prueba (no se pueden usar para entrar: no tienen contraseña)
insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('a0000000-0000-4000-8000-0000000000d1', 'authenticated', 'authenticated', 'dueno.a@prueba.test', now(), now()),
  ('a0000000-0000-4000-8000-0000000000c1', 'authenticated', 'authenticated', 'local.a@prueba.test', now(), now()),
  ('b0000000-0000-4000-8000-0000000000d2', 'authenticated', 'authenticated', 'dueno.b@prueba.test', now(), now()),
  ('b0000000-0000-4000-8000-0000000000c2', 'authenticated', 'authenticated', 'local.b@prueba.test', now(), now()),
  ('c0000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'sin.negocio@prueba.test', now(), now());

select set_config('prueba.neg_a', public.admin_alta_negocio('Prueba A', 'dueno.a@prueba.test', 'local.a@prueba.test', 'Ana', '1111')::text, false);
select set_config('prueba.neg_b', public.admin_alta_negocio('Prueba B', 'dueno.b@prueba.test', 'local.b@prueba.test', 'Beto', '2222')::text, false);
select set_config('prueba.ana', (select id from public.usuarios where nombre = 'Ana')::text, false);
select set_config('prueba.beto', (select id from public.usuarios where nombre = 'Beto')::text, false);
select pruebas.falla($$select public.admin_alta_negocio('Otro', 'dueno.a@prueba.test', null, 'X', '1234')$$,
  'ya pertenece a otro negocio', 'una cuenta no puede estar en dos negocios');

-- ---------------------------------------------------------------------
\echo == Sin iniciar sesión (anon)
set local role anon;
select pruebas.como(null);
select pruebas.falla('select * from public.negocios', 'permission denied', 'anon no lee negocios');
select pruebas.falla('select * from public.usuarios', 'permission denied', 'anon no lee usuarios');
select pruebas.falla('select public.datos_inicio()', 'permission denied', 'anon no llama a datos_inicio');
select pruebas.falla($$select public.iniciar_usuario(1, '1111')$$, 'permission denied', 'anon no puede poner un PIN');
select pruebas.ok((public.estado_app() ->> 'base')::int >= 2, 'estado_app responde sin sesión');
reset role;

-- ---------------------------------------------------------------------
\echo == La PC del negocio A, todavía sin PIN
set local role authenticated;
select pruebas.como('a0000000-0000-4000-8000-0000000000c1');
select pruebas.ok(public.datos_inicio() -> 'negocio' ->> 'nombre' = 'Prueba A', 've su negocio');
select pruebas.ok(public.datos_inicio() -> 'cuenta' ->> 'rol' = 'local', 've que es la cuenta del local');
select pruebas.ok(jsonb_array_length(public.datos_inicio() -> 'usuarios') = 1
  and public.datos_inicio() -> 'usuarios' -> 0 ->> 'nombre' = 'Ana', 've solo los usuarios de su negocio');
select pruebas.ok(jsonb_typeof(public.datos_inicio() -> 'yo') = 'null', 'sin PIN no hay usuario');
select pruebas.ok(public.datos_inicio()::text !~ '\$2[aby]\$', 'el hash del PIN nunca sale');
select pruebas.falla('select * from public.usuarios', 'permission denied', 'no lee la tabla usuarios directo');
select pruebas.falla('select * from public.config', 'permission denied', 'no lee la tabla config directo');
select pruebas.falla('select * from public.sesiones', 'permission denied', 'no lee la tabla sesiones directo');
select pruebas.falla('select * from public.miembros', 'permission denied', 'no lee la tabla miembros directo');
select pruebas.falla($$select public.hash_pin('1234')$$, 'permission denied', 'no llama a hash_pin');
select pruebas.falla($$select public.admin_alta_negocio('X', 'a@b.c', null, 'X', '1234')$$, 'permission denied', 'no puede dar de alta negocios');
select pruebas.falla($$select public.guardar_config('negocio', '{}')$$, 'venció', 'sin PIN no guarda configuración');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.beto')::bigint, '2222') ->> 'error' = 'Usuario no encontrado',
  'no puede entrar con un usuario de otro negocio');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.ana')::bigint, '9999') ->> 'error' = 'PIN incorrecto', 'PIN incorrecto');
select set_config('prueba.tok_a', public.iniciar_usuario(current_setting('prueba.ana')::bigint, '1111') ->> 'token', false);
select pruebas.ok(current_setting('prueba.tok_a') ~ '^[0-9a-f-]{36}$', 'con el PIN correcto da un token');

-- ---------------------------------------------------------------------
\echo == Ana (dueña) en la PC del negocio A
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.tok_a'));
select pruebas.ok(public.datos_inicio() -> 'yo' ->> 'nombre' = 'Ana' and public.es_admin(), 'el token la identifica como dueña');
select public.guardar_config('negocio', '{"nombre": "Prueba A editada"}');
select pruebas.ok(public.datos_inicio() -> 'config' -> 'negocio' ->> 'nombre' = 'Prueba A editada', 'guarda la configuración');
select pruebas.falla($$select public.guardar_config('Mal Clave', '1')$$, 'inválida', 'rechaza claves inválidas');
select set_config('prueba.emi', (public.guardar_usuario(null, 'Emi', 'empleado', true, '3333') ->> 'id'), false);
select pruebas.ok(current_setting('prueba.emi') ~ '^\d+$', 'crea un empleado');
select pruebas.falla($$select public.guardar_usuario(null, 'Corto', 'empleado', true, '12')$$, 'entre 4 y 8', 'el PIN tiene que tener 4 a 8 números');
select pruebas.falla($$select public.guardar_usuario(null, ' ana ', 'empleado', true, '5555')$$, 'Ya hay un usuario', 'no repite nombres');
select pruebas.falla(format($$select public.guardar_usuario(%s, 'Ana', 'empleado', true, null)$$, current_setting('prueba.ana')),
  'al menos un usuario Dueño', 'siempre queda un dueño activo');

-- ---------------------------------------------------------------------
\echo == Emi (empleado)
select pruebas.como('a0000000-0000-4000-8000-0000000000c1');
select set_config('prueba.tok_e', public.iniciar_usuario(current_setting('prueba.emi')::bigint, '3333') ->> 'token', false);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.tok_e'));
select pruebas.ok(public.datos_inicio() -> 'yo' ->> 'rol' = 'empleado' and not public.es_admin(), 'el empleado no es admin');
select pruebas.falla($$select public.guardar_config('negocio', '{}')$$, 'solo lo puede hacer el dueño', 'el empleado no cambia la configuración');
select pruebas.falla($$select public.guardar_usuario(null, 'Zeta', 'admin', true, '4444')$$, 'solo lo puede hacer el dueño', 'el empleado no crea usuarios');
select public.cambiar_mi_pin('3333', '4444');
select pruebas.falla($$select public.cambiar_mi_pin('3333', '5555')$$, 'PIN actual no es correcto', 'para cambiar el PIN pide el actual');
select pruebas.falla('select public.listar_usuarios()', 'solo lo puede hacer el dueño', 'el empleado no ve la lista para administrar');

\echo == Cinco PIN incorrectos bloquean
select pruebas.como('a0000000-0000-4000-8000-0000000000c1');
do $$ begin
  for i in 1..5 loop perform public.iniciar_usuario(current_setting('prueba.emi')::bigint, '0000'); end loop;
end $$;
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.emi')::bigint, '4444') ->> 'error' ~ '^Demasiados intentos',
  'después de 5 intentos fallidos no deja entrar ni con el PIN correcto');

\echo == Un empleado desactivado pierde su sesión
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.tok_a'));
select public.guardar_usuario(current_setting('prueba.emi')::bigint, 'Emi', 'empleado', false, null);
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.tok_e'));
select pruebas.ok(public.usuario_actual_id() is null, 'su token deja de valer');
select pruebas.ok(jsonb_array_length(public.datos_inicio() -> 'usuarios') = 1, 'ya no aparece para elegir');
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.tok_a'));
select pruebas.ok(jsonb_array_length(public.listar_usuarios()) = 2
  and public.listar_usuarios() @> '[{"nombre": "Emi", "activo": false}]', 'la dueña lo sigue viendo, desactivado');

-- ---------------------------------------------------------------------
\echo == El token de una cuenta no sirve en otra
select pruebas.como('a0000000-0000-4000-8000-0000000000d1', current_setting('prueba.tok_a'));
select pruebas.ok(public.usuario_actual_id() is null, 'el token del local no sirve con la cuenta del dueño del mismo negocio');
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.tok_a'));
select pruebas.ok(public.usuario_actual_id() is null, 'el token del negocio A no sirve en el negocio B');
select pruebas.ok(public.datos_inicio() -> 'negocio' ->> 'nombre' = 'Prueba B', 'el negocio B ve solo el suyo');
select pruebas.ok(public.datos_inicio() -> 'config' -> 'negocio' ->> 'nombre' = 'Prueba B', 'y no ve la configuración de A');
select pruebas.falla($$select public.guardar_config('negocio', '{}')$$, 'venció', 'con un token ajeno no guarda nada');

\echo == El dueño de B no toca usuarios de A
select set_config('prueba.tok_b', public.iniciar_usuario(current_setting('prueba.beto')::bigint, '2222') ->> 'token', false);
select pruebas.como('b0000000-0000-4000-8000-0000000000c2', current_setting('prueba.tok_b'));
select pruebas.falla(format($$select public.guardar_usuario(%s, 'Hackeado', 'admin', true, '9999')$$, current_setting('prueba.ana')),
  'Usuario no encontrado', 'no puede editar un usuario de otro negocio');
reset role;
select pruebas.ok((select nombre from public.usuarios where id = current_setting('prueba.ana')::bigint) = 'Ana', 'Ana sigue igual');

-- ---------------------------------------------------------------------
\echo == Negocio suspendido y cuenta sin negocio
update public.negocios set activo = false where id = current_setting('prueba.neg_a')::uuid;
set local role authenticated;
select pruebas.como('a0000000-0000-4000-8000-0000000000c1', current_setting('prueba.tok_a'));
select pruebas.falla('select public.datos_inicio()', 'no tiene un negocio activo', 'un negocio suspendido no entra');
select pruebas.ok(public.usuario_actual_id() is null, 'y su sesión deja de valer');
select pruebas.como('c0000000-0000-4000-8000-000000000000');
select pruebas.falla('select public.datos_inicio()', 'no tiene un negocio activo', 'una cuenta sin negocio no entra');
reset role;

\echo == Todas las pruebas de negocios y usuarios dieron bien
