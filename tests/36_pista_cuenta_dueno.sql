-- =====================================================================
-- Pruebas: la pista del email de la cuenta del dueño. Usa los negocios C y E (07 y 27).
-- =====================================================================
set local role authenticated;

\echo == La PC del local ve el email del dueño a medias
select pruebas.como('d0000000-0000-4000-8000-0000000000c3');
select pruebas.ok(public.pista_cuenta_dueno() = 'd•••••@prueba.test', 'negocio C: d•••••@prueba.test');
select pruebas.como('d0000000-0000-4000-8000-0000000000e5');
select pruebas.ok(public.pista_cuenta_dueno() = 'd•••••@prueba.test', 'negocio E, la suya');

\echo == Sin una cuenta de un negocio, nada
select pruebas.como('d0000000-0000-4000-8000-000000000999');
select pruebas.falla('select public.pista_cuenta_dueno()', 'no tiene un negocio', 'una cuenta sin negocio no ve nada');
reset role;

\echo == Todas las pruebas de la pista del email dieron bien
