// Conexión con Supabase. Toda la app habla con la base desde acá (como core.js en la app local).
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/+esm';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

// Token del usuario que puso su PIN. Va en el encabezado x-usuario-kiosco de cada pedido a la base,
// y la base lo controla (tiene que ser de esta cuenta, de su negocio y no estar vencido).
const CLAVE_TOKEN = 'kioscos.usuario';
const leerToken = () => { try { return localStorage.getItem(CLAVE_TOKEN); } catch { return null; } };
export function guardarToken(t) {
  try { if (t) localStorage.setItem(CLAVE_TOKEN, t); else localStorage.removeItem(CLAVE_TOKEN); } catch { /* sin almacenamiento: dura hasta recargar */ }
  tokenEnMemoria = t || null;
}
let tokenEnMemoria = leerToken();

// Ningún pedido espera para siempre: si internet se colgó (o la PC estuvo suspendida), a los 30 segundos se corta y la
// pantalla avisa en vez de quedar en "Cargando…". Las funciones (lectura de facturas con IA) tienen 2 minutos.
const ESPERA_MS = 30 * 1000, ESPERA_FUNCIONES_MS = 120 * 1000;
function conTiempo(signal, ms) {
  if (typeof AbortSignal.timeout !== 'function') return signal;
  const t = AbortSignal.timeout(ms);
  return signal && typeof AbortSignal.any === 'function' ? AbortSignal.any([signal, t]) : (signal || t);
}

// Solo los pedidos a la base (/rest/v1/) y a sus funciones (/functions/v1/) llevan el token; los de inicio de sesión no
function fetchConUsuario(input, init = {}) {
  const url = typeof input === 'string' ? input : input.url;
  const esFuncion = url.startsWith(SUPABASE_URL + '/functions/v1/');
  if (tokenEnMemoria && (url.startsWith(SUPABASE_URL + '/rest/v1/') || esFuncion)) {
    const headers = new Headers(init.headers || (typeof input === 'string' ? undefined : input.headers));
    headers.set('x-usuario-kiosco', tokenEnMemoria);
    init = { ...init, headers };
  }
  return fetch(input, { ...init, signal: conTiempo(init.signal, esFuncion ? ESPERA_FUNCIONES_MS : ESPERA_MS) });
}

// lock: la renovación de la sesión no usa el bloqueo entre pestañas del navegador (navigator.locks). Con la pestaña un rato
// sin usar, ese bloqueo puede quedar tomado y toda la app queda esperando ("Cargando…" sin fin). La app se usa en una
// pestaña por PC, así que alcanza con hacerlo directo.
export const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  global: { fetch: fetchConUsuario },
  auth: { lock: async (_nombre, _espera, fn) => fn() },
});

// Corta una espera que no termina (por ejemplo, la sesión renovándose con internet colgado)
const DEMORA = 'La base tardó demasiado en responder: revisá internet y probá de nuevo';
export function conLimite(promesa, ms = ESPERA_MS + 5000) {
  let t;
  return Promise.race([promesa, new Promise((_, mal) => { t = setTimeout(() => mal(new ErrorBase(DEMORA, 'red')), ms); })])
    .finally(() => clearTimeout(t));
}

// Error con un mensaje para mostrar en pantalla; 'codigo' conserva el de Postgres o PostgREST.
// codigo 'sesion' = venció la sesión del usuario con PIN (hay que volver a elegir usuario).
export class ErrorBase extends Error {
  constructor(mensaje, codigo = '') { super(mensaje); this.codigo = codigo; }
}

// Traduce los errores de la base a mensajes entendibles
export function traducir(error) {
  const msg = error?.message || String(error);
  if (error instanceof ErrorBase) return error;
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError' || /aborted|timed? ?out/i.test(msg)) return new ErrorBase(DEMORA, 'red');
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return new ErrorBase('Sin conexión a internet', 'red');
  if (error?.hint === 'sesion') return new ErrorBase(msg, 'sesion');
  if (error?.hint === 'limite') return new ErrorBase(msg, 'limite');   // fiado por encima del límite del cliente
  if (error?.hint === 'autorizacion') return new ErrorBase(msg, 'autorizacion');   // hace falta el PIN de un dueño
  if (error?.hint === 'promos') return new ErrorBase(msg, 'promos');   // las promociones cambiaron mientras se armaba la venta
  if (error?.code === 'PGRST202') return new ErrorBase('La base no tiene esta función: falta aplicar una actualización de la base', error.code);
  if (error?.code === '23505') return new ErrorBase(/^Ya /.test(msg) ? msg : 'Ya existe un registro con ese dato', error.code);
  if (/permission denied|row-level security/i.test(msg)) return new ErrorBase('Sin permiso para hacer esto', '42501');
  if (/statement timeout|canceling statement/i.test(msg)) return new ErrorBase(DEMORA, 'red');
  if (/JWT expired|invalid JWT|refresh token/i.test(msg)) return new ErrorBase('Se venció la conexión con la base: recargá la página con el botón ↻ del navegador', 'red');
  if (/value too long/i.test(msg)) return new ErrorBase('Algún texto es demasiado largo', error?.code || '');
  if (/invalid input syntax|out of range|numeric field overflow/i.test(msg)) return new ErrorBase('Algún número o fecha no es válido: revisalo', error?.code || '');
  if (/violates check constraint/i.test(msg)) return new ErrorBase('Algún dato no es válido (por ejemplo, un número negativo): revisalo', error?.code || '');
  if (/violates foreign key/i.test(msg)) return new ErrorBase('Ese dato está en uso o ya no existe', error?.code || '');
  // un error de la propia app (no de la base): en inglés y sin sentido para quien atiende
  if (error instanceof TypeError || error instanceof ReferenceError || error instanceof RangeError || error instanceof SyntaxError) {
    console.error(error);
    return new ErrorBase('Algo falló en la app. Probá de nuevo; si sigue pasando, recargá la página con el botón ↻ del navegador', 'app');
  }
  return new ErrorBase(msg, error?.code || '');
}

// Llama a una función de Supabase (supabase/functions), como la lectura de facturas con IA. Responde { error, hint } si falla.
export async function funcion(nombre, cuerpo) {
  let r;
  try { r = await conLimite(sb.functions.invoke(nombre, { body: cuerpo }), ESPERA_FUNCIONES_MS + 5000); } catch (e) { throw traducir(e); }
  if (r.error) {
    let d = null;
    try { d = await r.error.context?.json(); } catch { /* sin cuerpo */ }
    if (r.error.context?.status === 404) throw new ErrorBase('Esta función todavía no está publicada en Supabase', 'funcion');
    throw traducir(d?.error ? { message: d.error, hint: d.hint } : r.error);
  }
  return r.data;
}

// "¿Olvidaste la contraseña?": Supabase manda un mail con un enlace a recuperar.html (la página para elegir la nueva).
// Con un cliente aparte y flujo "implicit": el enlace trae la sesión de recuperación en la dirección, así sirve aunque se
// abra en otro dispositivo (el celular del dueño), y no toca la cuenta iniciada en esta PC.
export async function mandarRecuperacion(email) {
  const aparte = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, flowType: 'implicit', storageKey: 'kioscos-recupero' } });
  const destino = new URL('recuperar.html', location.href.split('#')[0]).href;
  let r;
  try { r = await conLimite(aparte.auth.resetPasswordForEmail(email, { redirectTo: destino })); } catch (e) { throw traducir(e); }
  if (r.error) throw new ErrorBase(/rate|seconds|security purposes/i.test(r.error.message) ? 'Ya se mandó un mail hace muy poco: esperá un minuto y probá de nuevo' : r.error.message);
}

// Llama a una función de la base con OTRA cuenta (la del dueño, para "¿Olvidaste tu PIN?"): la inicia aparte, solo para esta
// llamada, sin tocar la sesión de la PC ni guardar nada (sin persistir, sin el token del usuario con PIN), y después la cierra.
export async function llamarComoDueno(email, clave, funcion, args = {}) {
  const aparte = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false, storageKey: 'kioscos-dueno' } });
  try {
    let r;
    try { r = await conLimite(aparte.auth.signInWithPassword({ email, password: clave })); } catch (e) { throw traducir(e); }
    if (r.error) throw new ErrorBase(/invalid/i.test(r.error.message) ? 'Email o contraseña incorrectos' : r.error.message);
    try { r = await conLimite(aparte.rpc(funcion, args)); } catch (e) { throw traducir(e); }
    if (r.error) throw traducir(r.error);
    return r.data;
  } finally { aparte.auth.signOut({ scope: 'local' }).catch(() => {}); }
}

// Llama a una función de la base (las operaciones que tocan varias tablas son funciones SQL atómicas)
export async function llamar(funcion, args = {}) {
  let r;
  try { r = await conLimite(sb.rpc(funcion, args)); } catch (e) { throw traducir(e); }
  if (r.error) throw traducir(r.error);
  return r.data;
}
