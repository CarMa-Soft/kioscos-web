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

// Solo los pedidos a la base (/rest/v1/) llevan el token; los de inicio de sesión no
function fetchConUsuario(input, init = {}) {
  const url = typeof input === 'string' ? input : input.url;
  if (tokenEnMemoria && url.startsWith(SUPABASE_URL + '/rest/v1/')) {
    const headers = new Headers(init.headers || (typeof input === 'string' ? undefined : input.headers));
    headers.set('x-usuario-kiosco', tokenEnMemoria);
    init = { ...init, headers };
  }
  return fetch(input, init);
}

export const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { global: { fetch: fetchConUsuario } });

// Error con un mensaje para mostrar en pantalla; 'codigo' conserva el de Postgres o PostgREST.
// codigo 'sesion' = venció la sesión del usuario con PIN (hay que volver a elegir usuario).
export class ErrorBase extends Error {
  constructor(mensaje, codigo = '') { super(mensaje); this.codigo = codigo; }
}

// Traduce los errores de la base a mensajes entendibles
export function traducir(error) {
  const msg = error?.message || String(error);
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return new ErrorBase('Sin conexión a internet', 'red');
  if (error?.hint === 'sesion') return new ErrorBase(msg, 'sesion');
  if (error?.hint === 'limite') return new ErrorBase(msg, 'limite');   // fiado por encima del límite del cliente
  if (error?.code === 'PGRST202') return new ErrorBase('La base no tiene esta función: falta aplicar una actualización de la base', error.code);
  if (error?.code === '23505') return new ErrorBase(/^Ya /.test(msg) ? msg : 'Ya existe un registro con ese dato', error.code);
  if (/permission denied|row-level security/i.test(msg)) return new ErrorBase('Sin permiso para hacer esto', '42501');
  return new ErrorBase(msg, error?.code || '');
}

// Llama a una función de la base (las operaciones que tocan varias tablas son funciones SQL atómicas)
export async function llamar(funcion, args = {}) {
  let r;
  try { r = await sb.rpc(funcion, args); } catch (e) { throw traducir(e); }
  if (r.error) throw traducir(r.error);
  return r.data;
}
