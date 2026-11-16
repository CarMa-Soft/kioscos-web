// Conexión con Supabase. Toda la app habla con la base desde acá (como core.js en la app local).
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/+esm';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

export const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

// Error con un mensaje para mostrar en pantalla; 'codigo' conserva el de Postgres o PostgREST
export class ErrorBase extends Error {
  constructor(mensaje, codigo = '') { super(mensaje); this.codigo = codigo; }
}

// Traduce los errores de la base a mensajes entendibles
export function traducir(error) {
  const msg = error?.message || String(error);
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return new ErrorBase('Sin conexión a internet', 'red');
  if (error?.code === 'PGRST202') return new ErrorBase('La base no tiene esta función: falta aplicar una actualización de la base', error.code);
  if (error?.code === '23505') return new ErrorBase('Ya existe un registro con ese dato', error.code);
  if (error?.code === '42501' || /permission denied|row-level security/i.test(msg)) return new ErrorBase('Sin permiso para hacer esto', error.code || '42501');
  return new ErrorBase(msg, error?.code || '');
}

// Llama a una función de la base (las operaciones que tocan varias tablas son funciones SQL atómicas)
export async function llamar(funcion, args = {}) {
  let r;
  try { r = await sb.rpc(funcion, args); } catch (e) { throw traducir(e); }
  if (r.error) throw traducir(r.error);
  return r.data;
}
