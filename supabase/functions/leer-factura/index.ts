// Función de Supabase "leer-factura": la PC manda el PDF o las fotos de una factura y recibe sus datos para cargar la compra
// (formato "Factura leída" en CLAUDE.md). La lectura está en ../_shared/lectura.ts (la comparte con subir-factura).
// - Quién puede: lo decide la base con permiso_lectura_ia(), llamada como el usuario (su sesión y su PIN). Solo el dueño,
//   y hasta 60 lecturas por día por negocio.
// - Cada lectura se anota en lecturas_ia (con la clave de servicio) con su costo estimado.
import { anotar, cors, Falla, leer, respuesta, revisarArchivos, rpc } from '../_shared/lectura.ts';

Deno.serve(async req => {
  const h = cors(req.headers.get('Origin'));
  const responder = respuesta(h);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: h });
  if (req.method !== 'POST') return responder({ error: 'Método no permitido' }, 405);
  try {
    // 1) ¿quién es y puede? (la base valida la sesión de la cuenta y el PIN del usuario)
    const comoUsuario: Record<string, string> = {
      apikey: req.headers.get('apikey') || '', Authorization: req.headers.get('Authorization') || '',
      'x-usuario-kiosco': req.headers.get('x-usuario-kiosco') || '',
    };
    if (!comoUsuario.Authorization) throw new Falla('Falta iniciar sesión', 401);
    const permiso = await rpc('permiso_lectura_ia', {}, comoUsuario);

    // 2) los archivos: [{ tipo, datos (base64) }], un PDF o hasta 5 fotos
    const cuerpo = await req.json().catch(() => null);
    const archivos = revisarArchivos(cuerpo?.archivos);

    // 3) leer y anotar el consumo (aunque la lectura no haya servido, la IA se usó)
    const { factura, uso, error } = await leer(archivos);
    await anotar(permiso.negocio_id, permiso.usuario_id, uso, error, factura?.items?.length ?? 0);
    if (error) throw new Falla(error, 422);
    return responder({ factura, uso });
  } catch (e) {
    if (e instanceof Falla) return responder({ error: e.message, hint: e.hint || undefined }, e.estado);
    console.error(e);
    return responder({ error: 'No se pudo leer la factura. Probá de nuevo en un rato.' }, 500);
  }
});
