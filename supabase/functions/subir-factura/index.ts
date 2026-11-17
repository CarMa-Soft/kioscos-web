// Función de Supabase "subir-factura": la usa la página del celular (celu.html), que no inicia sesión. Lo que la autoriza
// es el código del QR que mostró la PC (crear_subida_celular): la base guarda solo su huella, vence a los 15 minutos y
// sirve para una factura. Todo lo de la base se hace con la clave de servicio.
// - { codigo, revisar: true } → si el código sirve y de qué negocio es (para mostrarlo al abrir la página).
// - { codigo, archivos } → toma el código, lee las fotos con IA (../_shared/lectura.ts), anota el consumo y deja el
//   resultado para la PC (terminar_subida_celular). Si la lectura falla, se puede volver a mandar con el mismo código.
import { anotar, comoServicio, cors, Falla, leer, respuesta, revisarArchivos, rpc } from '../_shared/lectura.ts';

Deno.serve(async req => {
  const h = cors(req.headers.get('Origin'));
  const responder = respuesta(h);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: h });
  if (req.method !== 'POST') return responder({ error: 'Método no permitido' }, 405);
  try {
    const cuerpo = await req.json().catch(() => null);
    const codigo = typeof cuerpo?.codigo === 'string' ? cuerpo.codigo.trim() : '';
    if (!/^[0-9a-f]{48}$/.test(codigo)) throw new Falla('Este código no sirve: escaneá de nuevo el QR de la PC', 403);
    if (cuerpo?.revisar) return responder(await rpc('revisar_subida_celular', { p_codigo: codigo }, comoServicio()));

    const archivos = revisarArchivos(cuerpo?.archivos);
    const s = await rpc('tomar_subida_celular', { p_codigo: codigo, p_paginas: archivos.length }, comoServicio());
    let error = '';
    try {
      const r = await leer(archivos);
      error = r.error;
      await anotar(s.negocio_id, s.usuario_id, r.uso, r.error, r.factura?.items?.length ?? 0);
      await rpc('terminar_subida_celular', { p_id: s.id, p_resultado: error ? null : { factura: r.factura, uso: r.uso }, p_error: error || null }, comoServicio());
      if (error) throw new Falla(error, 422);
      return responder({ ok: true, renglones: r.factura?.items?.length ?? 0 });
    } catch (e) {
      // que el código no quede trabado "leyendo": vuelve a estar disponible para mandar de nuevo
      if (!error) {
        const msg = e instanceof Falla ? e.message : 'No se pudo leer la factura';
        await rpc('terminar_subida_celular', { p_id: s.id, p_resultado: null, p_error: msg }, comoServicio()).catch(() => {});
      }
      throw e;
    }
  } catch (e) {
    if (e instanceof Falla) return responder({ error: e.message }, e.estado);
    console.error(e);
    return responder({ error: 'No se pudo leer la factura. Probá de nuevo en un rato.' }, 500);
  }
});
