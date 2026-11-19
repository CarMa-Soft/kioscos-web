// Arranque: entrar con la cuenta (una vez por PC), elegir el usuario y poner el PIN, y después las secciones.
import { sb, llamar, guardarToken, conLimite } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, ROL, aviso, correr, siVenceLaSesion } from './ui.js';
import { pantallaVender } from './vender.js';
import { pantallaCaja } from './caja.js';
import { pantallaProductos } from './productos.js';
import { pantallaUsuarios } from './usuarios.js';
import { pantallaClientes } from './clientes.js';
import { pantallaAjustes } from './ajustes.js';
import { pantallaAyuda } from './ayuda.js';
import { pantallaInicio } from './inicio.js';
import { pantallaReportes } from './reportes.js';
import { pantallaCompras } from './compras.js';
import { pantallaPedidos } from './pedidos.js';
import { pantallaProveedores } from './proveedores.js';
import { pantallaRemitos } from './remitos.js';
import { VERSION } from './version.js';

const raiz = $('#app');
let datos = null;            // lo que devuelve datos_inicio()
let teclas = null;           // atajos de teclado de la sección abierta
let refresco = null;         // actualización periódica del catálogo

// La primera es la que se abre al entrar
const SECCIONES = [
  { ruta: '#/inicio', nombre: 'Hoy', fn: pantallaInicio },   // la primera es la que se abre al entrar
  { ruta: '#/vender', nombre: 'Vender', fn: pantallaVender },
  { ruta: '#/caja', nombre: 'Caja', fn: pantallaCaja },
  { ruta: '#/clientes', nombre: 'Clientes', fn: pantallaClientes },
  { ruta: '#/productos', nombre: 'Productos', fn: pantallaProductos, admin: true },
  { ruta: '#/compras', nombre: 'Compras', fn: pantallaCompras, admin: true },
  { ruta: '#/pedidos', nombre: 'Pedidos', fn: pantallaPedidos, admin: true },
  { ruta: '#/proveedores', nombre: 'Proveedores', fn: pantallaProveedores, admin: true },
  { ruta: '#/remitos', nombre: 'Entradas y salidas', fn: pantallaRemitos, admin: true },
  { ruta: '#/reportes', nombre: 'Reportes', fn: pantallaReportes, admin: true },
  { ruta: '#/usuarios', nombre: 'Usuarios', fn: pantallaUsuarios },
  { ruta: '#/ajustes', nombre: 'Ajustes', fn: pantallaAjustes, admin: true },
  { ruta: '#/ayuda', nombre: 'Ayuda', fn: pantallaAyuda, aparte: true },   // botón ? al lado del usuario (no ocupa lugar en el menú)
];

siVenceLaSesion(() => iniciar());
document.addEventListener('keydown', e => teclas?.(e));
window.addEventListener('hashchange', () => { if (datos?.yo) mostrarSeccion(); });

// ---------- Cuenta y usuario ----------

function pantallaCuenta() {
  raiz.className = 'caja-sola';
  raiz.innerHTML = `<h1>Kioscos y Almacenes</h1>
    <p class="muted">Entrá con la cuenta del negocio. En la PC del local se hace una sola vez.</p>
    <form id="f-cuenta" class="form">
      <label>Email<input class="input" name="email" type="email" autocomplete="username" required autofocus></label>
      <label>Contraseña<input class="input" name="clave" type="password" autocomplete="current-password" required></label>
      <button class="btn primario">Entrar</button>
    </form>`;
  $('#f-cuenta').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    correr(async () => {
      const { error } = await sb.auth.signInWithPassword({ email: f.get('email'), password: f.get('clave') });
      if (error) throw new Error(/invalid/i.test(error.message) ? 'Email o contraseña incorrectos' : error.message);
      await iniciar();
    });
  };
}

function pantallaSinNegocio(mensaje) {
  raiz.className = 'caja-sola';
  raiz.innerHTML = `<h1>Kioscos y Almacenes</h1><p class="aviso mal">${esc(mensaje)}</p>
    <div class="fila"><button class="btn" id="reintentar">Reintentar</button><button class="btn" id="salir">Salir de esta cuenta</button></div>`;
  $('#reintentar').onclick = () => iniciar();
  $('#salir').onclick = () => salirDeLaCuenta();
}

function pantallaElegir() {
  raiz.className = 'caja-sola';
  raiz.innerHTML = `<h1>${esc(datos.negocio.nombre)}</h1><p class="muted">¿Quién sos?</p>
    <div class="usuarios">${datos.usuarios.map(u => `<button class="usuario" data-id="${u.id}"><b>${esc(u.nombre)}</b><span>${ROL[u.rol]}</span></button>`).join('')}</div>
    <form id="f-pin" class="form" hidden>
      <label><span id="pin-de"></span><input class="input pin" name="pin" type="password" inputmode="numeric" autocomplete="off" maxlength="8" pattern="\\d{4,8}" required></label>
      <div class="fila"><button type="button" class="btn" id="volver">Volver</button><button class="btn primario">Entrar</button></div>
    </form>
    <p class="pie"><button class="link" id="salir">Salir de la cuenta de esta PC</button></p>`;
  let elegido = null;
  $$('.usuario').forEach(b => b.onclick = () => {
    elegido = datos.usuarios.find(u => u.id === +b.dataset.id);
    $('.usuarios').hidden = true; $('#f-pin').hidden = false;
    $('#pin-de').textContent = `PIN de ${elegido.nombre}`;
    $('#f-pin [name=pin]').focus();
  });
  $('#volver').onclick = () => pantallaElegir();
  $('#f-pin').onsubmit = e => {
    e.preventDefault();
    const pin = new FormData(e.target).get('pin');
    correr(async () => {
      const r = await llamar('iniciar_usuario', { p_usuario_id: elegido.id, p_pin: pin });
      if (r.error) { e.target.reset(); $('#f-pin [name=pin]').focus(); return aviso(r.error); }
      guardarToken(r.token);
      await iniciar();
    });
  };
  $('#salir').onclick = async () => {
    if (confirm('Para volver a entrar en esta PC va a hacer falta el email y la contraseña de la cuenta. ¿Salir?')) await salirDeLaCuenta();
  };
}

async function cambiarDeUsuario() {
  await correr(async () => { try { await llamar('cerrar_usuario'); } catch { /* ya no había sesión */ } });
  guardarToken(null);
  cat.olvidarCostos();
  await iniciar();
}

async function salirDeLaCuenta() {
  await correr(async () => { try { await llamar('cerrar_usuario'); } catch { /* ya no había sesión */ } });
  guardarToken(null);
  await sb.auth.signOut();
  datos = null; cat.olvidarTodo();
  pantallaCuenta();
}

// ---------- Secciones ----------

function armarMarco() {
  const yo = datos.yo;
  raiz.className = 'marco';
  // En el celular (pantalla angosta) el menú y el usuario se esconden detrás del botón ☰, que muestra la sección actual
  raiz.innerHTML = `<header class="barra" id="barra"><div class="negocio">${esc(datos.negocio.nombre)}</div>
      <button class="menu-boton" id="menu" aria-expanded="false" aria-controls="menu-nav"><span aria-hidden="true">☰</span> <span id="seccion-actual">Menú</span></button>
      <nav id="menu-nav">${SECCIONES.filter(s => (!s.admin || yo.rol === 'admin') && !s.aparte).map(s => `<a href="${s.ruta}" data-ruta="${s.ruta}">${s.nombre}</a>`).join('')}</nav>
      <div class="quien"><a class="btn chico boton-ayuda" href="#/ayuda" title="Ayuda: cómo hacer cada cosa">? Ayuda</a> ${esc(yo.nombre)} · ${ROL[yo.rol]} <button class="btn chico" id="cambiar">Cambiar de usuario</button></div></header>
    <main id="vista" class="vista"></main>`;
  $('#cambiar').onclick = () => cambiarDeUsuario();
  $('#menu').onclick = () => abrirMenu(!$('#barra').classList.contains('abierto'));
}
function abrirMenu(abrir) {
  $('#barra')?.classList.toggle('abierto', abrir);
  $('#menu')?.setAttribute('aria-expanded', String(abrir));
}

async function mostrarSeccion() {
  const yo = datos.yo;
  let s = SECCIONES.find(x => x.ruta === location.hash && (!x.admin || yo.rol === 'admin'));
  if (!s) { s = SECCIONES[0]; history.replaceState(null, '', s.ruta); }
  $$('nav a').forEach(a => a.classList.toggle('activa', a.dataset.ruta === s.ruta));
  $('#seccion-actual').textContent = s.nombre;
  abrirMenu(false);
  teclas = null;
  const vista = $('#vista');
  vista.innerHTML = '<p class="muted">Cargando…</p>';
  const ctx = {
    yo, negocio: datos.negocio, usuarios: datos.usuarios,
    config: datos.config,          // configuración del negocio (datos para el ticket, cuándo imprimir); Ajustes la actualiza
    ir: ruta => { location.replace(ruta); },   // sin sumar al historial (ver ui.js: botón atrás)
    recargar: () => mostrarSeccion(),
    alTeclear: fn => { teclas = fn; },
  };
  let ok = false;
  await correr(async () => { await s.fn(vista, ctx); ok = true; });
  // si no se pudo cargar (sin internet, la base no respondió), no queda en "Cargando…": se ofrece reintentar
  if (!ok && $('#vista') === vista && /Cargando…/.test(vista.textContent)) {
    vista.innerHTML = `<div class="recuadro-blanco"><p><b>No se pudo cargar ${esc(s.nombre)}.</b></p>
      <p class="muted">Puede ser que se haya cortado internet o que la PC haya estado suspendida.</p>
      <div class="fila"><button class="btn primario" id="reintentar-seccion">Reintentar</button><button class="btn" id="recargar-pagina">Recargar la página</button></div></div>`;
    $('#reintentar-seccion').onclick = () => mostrarSeccion();
    $('#recargar-pagina').onclick = () => location.reload();
  }
}

// ---------- Versión nueva ----------
// Cada 2 minutos se compara la versión cargada con la publicada; si cambió, se avisa (no se recarga sola: puede haber
// una venta a medio cargar). En la computadora de desarrollo no hay version.json y no se avisa nada.
async function revisarVersion() {
  if (VERSION === 'desarrollo') return;
  try {
    const r = await fetch('version.json', { cache: 'no-store' });
    if (r.ok && (await r.json()).version !== VERSION) $('#version-nueva').hidden = false;
  } catch { /* sin conexión: se vuelve a intentar */ }
}
$('#actualizar').onclick = () => location.reload();
setInterval(revisarVersion, 2 * 60 * 1000);

// ---------- Arranque ----------
async function iniciar() {
  clearInterval(refresco);
  let session;
  try { ({ data: { session } } = await conLimite(sb.auth.getSession())); } catch (e) { return pantallaSinNegocio(e.message); }
  if (!session) return pantallaCuenta();
  try { datos = await llamar('datos_inicio'); } catch (e) { return pantallaSinNegocio(e.message); }
  if (!datos.yo) { guardarToken(null); return pantallaElegir(); }
  armarMarco();
  const ok = await correr(async () => { await cat.cargar(datos.negocio.id); return true; });
  if (!ok) return;
  refresco = setInterval(() => cat.actualizar().catch(() => {}), 60 * 1000);
  await mostrarSeccion();
}

iniciar();
