// Lectura de facturas con Claude, compartida por las funciones leer-factura (desde la PC) y subir-factura (desde el celular).
// Igual que la lectura de la app local. La clave de IA está en los secretos de Supabase (ANTHROPIC_API_KEY).
import Anthropic from 'npm:@anthropic-ai/sdk@1.3.0';

const MODELO = 'claude-opus-5-5';
// USD por millón de tokens (entrada, salida), para estimar el costo. El detalle real está en la consola de Anthropic.
const PRECIOS: Record<string, [number, number]> = {
  'claude-opus-5-5': [4, 20], 'claude-opus-5': [5, 25], 'claude-opus-4-8': [5, 25], 'claude-sonnet-5-5': [2, 10], 'claude-haiku-5-5': [0.1, 0.5],
};
export const TIPOS = new Set(['application/pdf', 'image/jpeg', 'image/png', 'image/webp']);
export const MAX_BYTES = 9 * 1024 * 1024;   // en total, ya en base64 (las fotos se achican en el navegador)
const ORIGENES = new Set(['https://carma-soft.github.io']);

const nulo = (tipo: string) => ({ anyOf: [{ type: tipo }, { type: 'null' }] });
const ESQUEMA = {
  type: 'object', additionalProperties: false,
  required: ['proveedor', 'comprobante', 'fecha', 'vencimiento', 'items', 'descuento_global', 'otros_cargos', 'subtotal', 'iva', 'percepciones', 'total', 'observaciones'],
  properties: {
    proveedor: { type: 'object', additionalProperties: false, required: ['nombre', 'cuit'], properties: { nombre: { type: 'string' }, cuit: nulo('string') } },
    comprobante: nulo('string'),
    fecha: nulo('string'),
    vencimiento: { type: 'string' },   // "" si no trae (no nulo: el esquema ya usa los 16 campos que pueden ser null)
    items: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['codigo', 'codigo_barras', 'descripcion', 'cantidad', 'unidad', 'unidades_por_bulto', 'precio_unitario', 'bonificacion', 'importe', 'alicuota_iva', 'precio_sugerido'],
        properties: {
          codigo: nulo('string'), codigo_barras: { type: 'string' }, descripcion: { type: 'string' }, cantidad: { type: 'number' },
          unidad: { type: 'string', enum: ['unidad', 'bulto', 'kg'] }, unidades_por_bulto: nulo('number'),
          precio_unitario: nulo('number'), bonificacion: nulo('number'), importe: { type: 'number' },
          alicuota_iva: nulo('number'), precio_sugerido: nulo('number'),
        },
      },
    },
    descuento_global: nulo('number'), otros_cargos: nulo('number'),
    subtotal: nulo('number'), iva: nulo('number'), percepciones: nulo('number'), total: nulo('number'),
    observaciones: nulo('string'),
  },
};
const INSTRUCCIONES = `Leés facturas y remitos de proveedores para un kiosco o almacén de Argentina, y devolvés sus datos para cargar la compra. El archivo puede ser un PDF, un escaneo o una foto de celular (puede venir en varias fotos, una por hoja: son todas del mismo comprobante).
- proveedor: quien EMITE el comprobante (arriba, con su CUIT). Nunca el cliente o comprador.
- comprobante: tipo y número tal como figuran, por ejemplo "A 0003-00068600". fecha: en formato AAAA-MM-DD.
- vencimiento: la fecha de vencimiento del pago (o "Vto.", "Vence", "Fecha de vencimiento", "Fecha vto. pago"), en formato AAAA-MM-DD. No confundir con el vencimiento del CAE. Si la factura no la trae, cadena vacía ("").
- codigo: el código del producto del proveedor (su código interno, como figura). codigo_barras: el código de barras del producto (EAN o UPC, de 8 a 14 números), solo si el renglón lo trae aparte o el código del proveedor es ese mismo número; si no, cadena vacía ("").
- items: un renglón por producto, en el orden de la factura. Lo que no es mercadería (flete, envío, "recupero de gastos") no va como renglón: se suma en otros_cargos. Un descuento sobre toda la factura (por ejemplo "Descuento 4% en ventas") tampoco: va en descuento_global, como número positivo.
- cantidad y unidad:
  - Si el precio del renglón es por bulto o caja (columna "BU", "bultos" con precio por bulto), unidad "bulto", cantidad = cantidad de bultos, y unidades_por_bulto = cuántas unidades trae el bulto si figura (columna "UxB" o en la descripción: "30X72g" son 30).
  - Si el precio es por unidad, unidad "unidad" y cantidad = total de unidades. Si la factura separa bultos y unidades sueltas con precio por unidad, cantidad = bultos × unidades por bulto + unidades sueltas, y unidades_por_bulto = el UxB.
  - Si se cobra por peso (fiambres o quesos por pieza, verdura), unidad "kg" y cantidad = los kilos.
- importe: el importe del renglón tal como figura, ya con su bonificación y sin IVA. precio_unitario y bonificacion (en %) como figuran.
- alicuota_iva: la del renglón si figura; si no, la de la factura (21 o 10,5).
- precio_sugerido: precio de venta sugerido al público por unidad, solo si la factura lo trae.
- subtotal: neto gravado de toda la factura (sin IVA). iva: total de IVA. percepciones: suma de todas las percepciones (IVA, IIBB, municipal). total: total final.
- Números: devolvelos como números con punto decimal. Las facturas pueden usar "1.234,56" o "1,234.56": interpretalos según el contexto y verificá que cantidad × precio_unitario × (1 − bonificación) dé el importe, y que la suma de renglones cierre con el subtotal.
- Ignorá tildes, sellos, marcas de agua y anotaciones a mano que no sean parte del comprobante.
- Si algo no se lee o no figura, poné null: nunca inventes datos. En observaciones anotá en una o dos frases lo dudoso (renglones ilegibles, cuentas que no cierran); si no hay nada, null.`;

export class Falla extends Error { constructor(msg: string, public estado = 400, public hint = '') { super(msg); } }

export function cors(origen: string | null): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': origen && ORIGENES.has(origen) ? origen : 'https://carma-soft.github.io',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-usuario-kiosco',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

// Llama a una función de la base con los encabezados que se le pasan (como el usuario o como servicio)
export async function rpc(funcion: string, cuerpo: unknown, headers: Record<string, string>) {
  const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/${funcion}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(cuerpo ?? {}),
  });
  const datos = await r.json().catch(() => null);
  if (!r.ok) throw new Falla(datos?.message || `La base respondió con un error (${r.status})`, r.status === 401 ? 401 : 403, datos?.hint || '');
  return datos;
}

export async function leer(archivos: { tipo: string; datos: string }[]) {
  const clave = Deno.env.get('ANTHROPIC_API_KEY');
  if (!clave) throw new Falla('La lectura con IA todavía no está configurada (falta la clave en Supabase).', 503);
  const cliente = new Anthropic({ apiKey: clave });
  const bloques = archivos.map(a => a.tipo === 'application/pdf'
    ? { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: a.datos } }
    : { type: 'image', source: { type: 'base64', media_type: a.tipo, data: a.datos } });
  // deno-lint-ignore no-explicit-any
  let r: any;
  try {
    // deno-lint-ignore no-explicit-any
    r = await (cliente.beta.messages.create as any)({
      model: MODELO,
      max_tokens: 16000,
      // si la lectura fuera rechazada por un filtro de seguridad, Anthropic la reintenta con el modelo recomendado
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      output_config: { effort: 'medium', format: { type: 'json_schema', schema: ESQUEMA } },
      system: INSTRUCCIONES,
      messages: [{ role: 'user', content: [...bloques, { type: 'text', text: 'Leé este comprobante y devolvé sus datos.' }] }],
    });
  } catch (e) {
    if (e instanceof Anthropic.AuthenticationError) throw new Falla('La clave de IA no es válida o fue desactivada.', 503);
    if (e instanceof Anthropic.PermissionDeniedError) throw new Falla('La clave de IA no tiene permiso para usar este modelo.', 503);
    if (e instanceof Anthropic.RateLimitError) throw new Falla('Se hicieron muchas lecturas seguidas: probá de nuevo en un minuto.', 429);
    if (e instanceof Anthropic.BadRequestError) throw new Falla(`La IA no pudo procesar el archivo: ${e.message}`);
    if (e instanceof Anthropic.APIConnectionError) throw new Falla('No se pudo conectar con la IA. Probá de nuevo en un rato.', 502);
    if (e instanceof Anthropic.APIError) throw new Falla(`La IA respondió con un error (${e.status}). Probá de nuevo en un rato.`, 502);
    throw e;
  }
  const u = r.usage || {};
  const entrada = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
  const [pe, ps] = PRECIOS[r.model] || PRECIOS[MODELO];
  const uso = { modelo: r.model, tokens_entrada: entrada, tokens_salida: u.output_tokens || 0,
    costo_usd: Math.round((entrada * pe + (u.output_tokens || 0) * ps) / 1e6 * 10000) / 10000 };
  let error = '';
  let factura = null;
  if (r.stop_reason === 'refusal') error = 'La IA no quiso leer este archivo. Revisá que sea una factura o remito.';
  else if (r.stop_reason === 'max_tokens') error = 'La factura es demasiado larga para leerla de una vez.';
  else {
    // deno-lint-ignore no-explicit-any
    try { factura = JSON.parse(r.content.find((b: any) => b.type === 'text')?.text); } catch { error = 'La IA devolvió algo que no se pudo entender. Probá de nuevo.'; }
  }
  return { factura, uso, error };
}

// Revisa los archivos que llegan: [{ tipo, datos (base64) }], un PDF o hasta 5 fotos
// deno-lint-ignore no-explicit-any
export function revisarArchivos(archivos: any): { tipo: string; datos: string }[] {
  if (!Array.isArray(archivos) || !archivos.length || archivos.length > 5) throw new Falla('Mandá un PDF o entre 1 y 5 fotos');
  let total = 0;
  for (const a of archivos) {
    if (!TIPOS.has(a?.tipo) || typeof a?.datos !== 'string' || !a.datos) throw new Falla('El archivo tiene que ser un PDF o una foto');
    total += a.datos.length;
  }
  if (total > MAX_BYTES) throw new Falla('El archivo es demasiado grande (hasta unos 6 MB)');
  return archivos;
}

// Encabezados para llamar a la base con la clave de servicio (solo dentro de las funciones de Supabase)
export const comoServicio = (): Record<string, string> => {
  const servicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  return { apikey: servicio, Authorization: `Bearer ${servicio}` };
};

// Anota el consumo de una lectura. Si falla, la lectura sigue sirviendo.
// deno-lint-ignore no-explicit-any
export async function anotar(negocio_id: string, usuario_id: number, uso: any, error: string, renglones: number) {
  try {
    await rpc('anotar_lectura_ia', { p_neg: negocio_id, p_usuario: usuario_id, p: { ...uso, ok: !error, resultado: error || `${renglones} renglones` } },
      comoServicio());
  } catch (e) { console.error('No se pudo anotar la lectura', e); }
}

// Una respuesta JSON con los encabezados CORS
export const respuesta = (h: Record<string, string>) => (cuerpo: unknown, estado = 200) =>
  new Response(JSON.stringify(cuerpo), { status: estado, headers: { ...h, 'Content-Type': 'application/json' } });
