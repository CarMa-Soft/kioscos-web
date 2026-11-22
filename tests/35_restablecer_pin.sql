-- =====================================================================
-- Pruebas: "¿Olvidaste tu PIN?" con la cuenta del dueño. Usa el negocio F (28): Fede (dueño); cuentas f5 (la PC) y f6 (el dueño).
-- =====================================================================
set local role authenticated;

\echo == Con la cuenta de la PC no se puede
select pruebas.como('d0000000-0000-4000-8000-0000000000f5');
select pruebas.falla(format('select public.restablecer_pin(%s, %L)', current_setting('prueba.fede'), '1357'), 'cuenta del dueño', 'la cuenta de la PC no restablece');

\echo == Con la cuenta del dueño, PIN nuevo
select pruebas.como('d0000000-0000-4000-8000-0000000000f6');
select pruebas.falla(format('select public.restablecer_pin(%s, %L)', current_setting('prueba.fede'), '12'), 'entre 4 y 8', 'el PIN nuevo tiene 4 a 8 números');
select pruebas.ok(public.restablecer_pin(current_setting('prueba.fede')::bigint, '1357') ->> 'nombre' = 'Fede', 'restablece el PIN');
select pruebas.como('d0000000-0000-4000-8000-0000000000f5');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.fede')::bigint, '1357') ->> 'token' is not null, 'entra con el PIN nuevo');
select pruebas.ok(public.iniciar_usuario(current_setting('prueba.fede')::bigint, '7777') ->> 'error' = 'PIN incorrecto', 'el viejo ya no sirve');

\echo == Solo para dueños, y solo de su negocio
select set_config('prueba.t_fede', public.iniciar_usuario(current_setting('prueba.fede')::bigint, '1357') ->> 'token', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000f5', current_setting('prueba.t_fede'));
select set_config('prueba.fran', public.guardar_usuario(null, 'Fran', 'empleado', true, '2468') ->> 'id', false);
select pruebas.como('d0000000-0000-4000-8000-0000000000f6');
select pruebas.falla(format('select public.restablecer_pin(%s, %L)', current_setting('prueba.fran'), '1111'), 'Solo se restablece', 'el del empleado no');
select pruebas.como('d0000000-0000-4000-8000-0000000000e6');   -- el dueño de otro negocio (E)
select pruebas.falla(format('select public.restablecer_pin(%s, %L)', current_setting('prueba.fede'), '1111'), 'no encontrado', 'otro negocio no ve a Fede');
reset role;

\echo == Todas las pruebas de restablecer el PIN dieron bien
