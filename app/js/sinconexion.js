// Ventas sin conexión. Si se corta internet mientras se vende, Vender guarda la venta en esta PC (localStorage, por negocio)
// y se sigue cobrando. Cuando vuelve internet se suben solas, de a una, con la fecha y hora en que se hicieron (la base las
// marca "sin conexión"). La clave de cada venta evita que se registre dos veces. Al cerrar la caja, si quedó alguna sin
// subir, se avisa y se ofrece subirlas antes (así entran en ese turno).
// Una barra arriba avisa mientras no hay internet, o mientras quedan ventas por subir.
import { llamar } from './base.js';
import { $, esc, plata, fecha, aviso, modal, confirmar, pedirAutorizacion } from './ui.js';

let negocio = null, yo = null, usuarios = [];
let sinConexion = false, prueba = null, subiendo = null;
const PRUEBA_MS = 20 * 1000;   // sin internet: cada cuánto se prueba si volvió

const claveCola = () => 'kioscos.sin-conexion.' + negocio;
const claveCaja = () => 'kioscos.caja.' + negocio;

// Al entrar con un usuario (app.js)
export function iniciar(neg, usuario, lista) {
  negocio = neg; yo = usuario; usuarios = lista || [];
  pintarBarra();
  if (pendientes().length) subir().catch(() => {});
}

// ---------- La cola de ventas guardadas ----------
export function pendientes() {
  if (!negocio) return [];
  try { return JSON.parse(localStorage.getItem(claveCola()) || '[]'); } catch { return []; }
}
function guardarCola(lista) {
  if (lista.length) localStorage.setItem(claveCola(), JSON.stringify(lista));
  else localStorage.removeItem(claveCola());
}
// Guarda una venta para subirla después. Si la PC no la puede guardar (sin espacio), avisa con un error: la venta sigue en pantalla.
export function guardarVenta(v) {
  const lista = pendientes();
  lista.push(v);
  try { guardarCola(lista); } catch { throw new Error('No se pudo guardar la venta en esta PC (sin espacio en el navegador). Anotala a mano.'); }
  pintarBarra();
}
const totalDe = lista => lista.reduce((s, v) => s + (+v.total || 0), 0);

// ---------- Lo que Vender necesita para abrir sin internet ----------
// La caja (turno, formas de pago, recargos, balanza) y las promociones de hoy, de la última vez que se abrió Vender con internet
export function recordarCaja(caja, promos) {
  if (!negocio) return;
  try {
    const { turno, formas_pago, recargos, balanza } = caja;
    localStorage.setItem(claveCaja(), JSON.stringify({ caja: { turno, formas_pago, recargos, balanza }, promos: promos || [] }));
  } catch { /* sin almacenamiento */ }
}
export function cajaGuardada() {
  if (!negocio) return null;
  try {
    const g = JSON.parse(localStorage.getItem(claveCaja()) || 'null');
    if (!g?.caja) return null;
    // las promociones guardadas que valen hoy (por si se guardaron otro día)
    const d = new Date(), hoy = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`, dow = d.getDay() || 7;
    g.promos = (g.promos || []).filter(p => (!p.desde || p.desde <= hoy) && (!p.hasta || p.hasta >= hoy) && (!p.dias?.length || p.dias.includes(dow)));
    return g;
  } catch { return null; }
}

// ---------- ¿Hay internet? ----------
export const estaSinConexion = () => sinConexion;
// Un pedido a la base anduvo: hay internet
export function hayConexion() { if (sinConexion) { sinConexion = false; clearTimeout(prueba); pintarBarra(); } }
// Un pedido a la base falló por la conexión: desde ahora Vender guarda sin esperar, y se prueba cada tanto si volvió
export function marcarSinConexion() {
  if (!sinConexion) { sinConexion = true; pintarBarra(); }
  clearTimeout(prueba);
  prueba = setTimeout(probar, PRUEBA_MS);
}
async function probar() {
  clearTimeout(prueba);
  try { await llamar('estado_app'); } catch (e) { if (e.codigo === 'red') return marcarSinConexion(); }
  sinConexion = false; pintarBarra();
  if (pendientes().length) subir().catch(() => {});
}
addEventListener('offline', () => marcarSinConexion());
addEventListener('online', () => { if (sinConexion) probar(); });

// ---------- Subir ----------
// De a una, en orden. conPin: si un descuento necesita la autorización del dueño, la pide (si no, la deja para después).
// Devuelve { subidas, quedan }.
export function subir({ conPin = false } = {}) {
  if (subiendo) return subiendo;
  subiendo = (async () => {
    let subidas = 0;
    try {
      for (const v of pendientes()) {
        const args = { ...v.args };
        for (;;) {
          try {
            await llamar('registrar_venta', args);
            hayConexion();
            guardarCola(pendientes().filter(x => x.clave !== v.clave));
            subidas++;
            break;
          } catch (err) {
            if (err.codigo === 'red') { marcarSinConexion(); return; }
            if (err.codigo === 'sesion') return;   // se venció el usuario: se sube cuando vuelva a entrar
            if (err.codigo === 'autorizacion' && conPin) {
              const token = await pedirAutorizacion(usuarios, `Venta sin conexión de ${fecha(v.fecha)} (${plata(v.total)}): ${err.message}`);
              if (token) { args.p_autorizacion = token; continue; }
            }
            // queda para revisar: se muestra en "Ver"
            guardarCola(pendientes().map(x => x.clave === v.clave ? { ...x, error: err.message } : x));
            break;
          }
        }
      }
    } finally {
      const quedan = pendientes().length;
      if (subidas) aviso(`Se ${subidas === 1 ? 'subió 1 venta hecha' : `subieron ${subidas} ventas hechas`} sin conexión${quedan ? ` (quedan ${quedan})` : ''}`, 'ok');
      subiendo = null;
      pintarBarra();
    }
  })().then(() => ({ quedan: pendientes().length }));
  return subiendo;
}

// ---------- La barra de aviso ----------
function pintarBarra() {
  const el = $('#sin-conexion');
  if (!el) return;
  const lista = pendientes(), n = lista.length, conError = lista.some(v => v.error);
  el.hidden = !sinConexion && !n;
  if (el.hidden) return;
  const cuantas = n === 1 ? '1 venta guardada' : `${n} ventas guardadas`;
  el.classList.toggle('sin-red', sinConexion);
  el.innerHTML = sinConexion
    ? `<b>📴 Sin internet.</b> <span>Podés seguir cobrando: las ventas se guardan en esta PC y se suben solas cuando vuelva.${n ? ` (${cuantas}: ${plata(totalDe(lista))})` : ''}</span>
       ${n ? '<button class="btn chico" id="sc-ver">Ver</button>' : ''}`
    : `<b>${n === 1 ? '1 venta hecha' : `${n} ventas hechas`} sin conexión ${conError ? 'no se pudo subir' : 'sin subir'}.</b>
       <button class="btn chico primario" id="sc-subir">Subir ahora</button><button class="btn chico" id="sc-ver">Ver</button>`;
  if ($('#sc-subir')) $('#sc-subir').onclick = () => subirConAviso();
  if ($('#sc-ver')) $('#sc-ver').onclick = () => verPendientes();
}

async function subirConAviso() {
  const { quedan } = await subir({ conPin: true });
  if (quedan && !sinConexion) verPendientes();
  else if (quedan) aviso('Sigue sin haber internet: se suben solas cuando vuelva', 'info');
}

// Las ventas guardadas: cuándo, quién, el total y, si no se pudo subir, por qué. El dueño puede descartar una que no corresponde.
export function verPendientes() {
  const lista = pendientes();
  const admin = yo?.rol === 'admin';
  const m = modal('Ventas hechas sin conexión', `
    <p class="muted">Quedaron guardadas en esta PC. Se suben solas cuando hay internet; para que entren en el turno, subilas antes de cerrar la caja.</p>
    ${lista.length ? `<table class="tabla"><thead><tr><th>Cuándo</th><th>Vendió</th><th>Productos</th><th class="num">Total</th>${admin ? '<th></th>' : ''}</tr></thead><tbody>
      ${lista.map(v => `<tr><td>${fecha(v.fecha)}</td><td>${esc(v.usuario || '')}</td><td class="corto">${esc(v.resumen || '')}${v.error ? `<div class="mal chico">${esc(v.error)}</div>` : ''}</td>
        <td class="num">${plata(v.total)}</td>${admin ? `<td><button class="btn chico peligro" data-descartar="${esc(v.clave)}">Descartar</button></td>` : ''}</tr>`).join('')}</tbody></table>`
      : '<p>No queda ninguna por subir.</p>'}
    <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button>${lista.length ? '<button class="btn primario" id="sc-subir-todas">Subir ahora</button>' : ''}</div>`, { ancho: true });
  if ($('#sc-subir-todas', m.el)) $('#sc-subir-todas', m.el).onclick = async () => { m.cerrar(); await subirConAviso(); };
  m.el.querySelectorAll('[data-descartar]').forEach(b => b.onclick = async () => {
    const v = pendientes().find(x => x.clave === b.dataset.descartar);
    if (!v || !await confirmar('Descartar venta', `¿Descartar la venta sin conexión de ${fecha(v.fecha)} por ${plata(v.total)}? No se va a registrar (la plata y el stock no se cuentan).`, 'Descartar')) return;
    guardarCola(pendientes().filter(x => x.clave !== v.clave));
    pintarBarra(); m.cerrar(); verPendientes();
  });
}

// Antes de cerrar la caja: si quedan ventas sin subir, se ofrece subirlas. Devuelve true si se puede seguir con el cierre
// (no quedaba ninguna, o se decidió cerrar igual); false si se canceló o se subieron (alSubir: para mirar los totales de nuevo).
export function antesDeCerrar(alSubir) {
  const lista = pendientes();
  if (!lista.length) return Promise.resolve(true);
  return new Promise(listo => {
    let r = false;
    const m = modal('Ventas sin subir', `
      <p>Hay <b>${lista.length === 1 ? '1 venta hecha' : `${lista.length} ventas hechas`} sin conexión</b> (${plata(totalDe(lista))}) que todavía no se ${lista.length === 1 ? 'subió' : 'subieron'}.</p>
      <p class="muted">Subilas antes de cerrar, así entran en este turno y los totales de la caja dan bien.</p>
      <div class="fila fin"><button class="btn izq" id="sc-igual">Cerrar igual</button><button class="btn" data-cerrar>Cancelar</button><button class="btn primario" id="sc-ahora">Subir ahora</button></div>`,
      { alCerrar: () => listo(r) });
    $('#sc-igual', m.el).onclick = async () => {
      if (await confirmar('Cerrar igual', 'Las ventas sin subir van a entrar en el próximo turno (cuando se suban). ¿Cerrar igual?', 'Cerrar igual')) { r = true; m.cerrar(); }
    };
    $('#sc-ahora', m.el).onclick = async () => {
      m.cerrar();
      const { quedan } = await subir({ conPin: true });
      if (quedan) aviso(sinConexion ? 'No hay internet: no se pudieron subir. Probá de nuevo cuando vuelva.' : 'Alguna venta no se pudo subir: mirá el detalle en "Ver".');
      else aviso('Listo: ya están en el turno. Revisá los totales y cerrá la caja.', 'ok');
      alSubir?.();
    };
  });
}
