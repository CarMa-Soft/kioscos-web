// Arranque: entrar con la cuenta (una vez por PC), elegir el usuario y poner el PIN, y después las secciones.
import { sb, llamar, guardarToken, conLimite, llamarComoDueno, mandarRecuperacion } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, ROL, aviso, correr, modal, siVenceLaSesion, hayCargaSinGuardar } from './ui.js';
import { pantallaVender } from './vender.js';
import { pantallaCaja } from './caja.js';
import { pantallaProductos } from './productos.js';
import { pantallaUsuarios, cambiarMiPin } from './usuarios.js';
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
import { recorridoPrimeraVez } from './recorrido.js';
import { atajoDe, textoAtajo, esAtajo } from './teclado.js';
import * as sc from './sinconexion.js';

const raiz = $('#app');
let datos = null;            // lo que devuelve datos_inicio()
let teclas = null;           // atajos de teclado de la sección abierta
let refresco = null;         // actualización periódica del catálogo

// La primera es la que se abre al entrar (y al abrir la app, aunque la dirección diga otra).
// grupo: el bloque del menú de la izquierda (ver menuPorGrupos). Mercadería va en el orden del circuito:
// ver stock → pedir → comprar → pagar.
const SECCIONES = [
  { ruta: '#/inicio', nombre: 'Hoy', ico: '🏠', grupo: 'dia', fn: pantallaInicio },
  { ruta: '#/vender', nombre: 'Vender', ico: '🛒', grupo: 'dia', fn: pantallaVender },
  { ruta: '#/caja', nombre: 'Caja', ico: '💵', grupo: 'dia', fn: pantallaCaja },
  { ruta: '#/clientes', nombre: 'Clientes', ico: '👥', grupo: 'dia', fn: pantallaClientes },
  { ruta: '#/productos', nombre: 'Productos', ico: '🏷️', grupo: 'mercaderia', fn: pantallaProductos, admin: true },
  { ruta: '#/remitos', nombre: 'Entradas y salidas', ico: '🔄', grupo: 'mercaderia', fn: pantallaRemitos, admin: true },
  { ruta: '#/pedidos', nombre: 'Pedidos', ico: '📝', grupo: 'mercaderia', fn: pantallaPedidos, admin: true },
  { ruta: '#/compras', nombre: 'Compras', ico: '🧾', grupo: 'mercaderia', fn: pantallaCompras, admin: true },
  { ruta: '#/proveedores', nombre: 'Proveedores', ico: '🚚', grupo: 'mercaderia', fn: pantallaProveedores, admin: true },
  { ruta: '#/reportes', nombre: 'Reportes', ico: '📊', grupo: 'numeros', fn: pantallaReportes, admin: true },
  { ruta: '#/usuarios', nombre: 'Usuarios', ico: '👤', grupo: 'admin', fn: pantallaUsuarios, admin: true },   // el empleado cambia su PIN desde el menú
  { ruta: '#/ajustes', nombre: 'Ajustes', ico: '⚙️', grupo: 'admin', fn: pantallaAjustes, admin: true },
  { ruta: '#/ayuda', nombre: 'Ayuda', fn: pantallaAyuda, aparte: true },   // en el bloque del usuario (no es un bloque del menú)
];
const GRUPOS = ['dia', 'mercaderia', 'numeros', 'admin'];   // admin (Usuarios y Ajustes) va abajo, pegado al bloque del usuario
const CLAVE_COLAPSADO = 'menu-colapsado';                   // cada PC recuerda si el menú de la izquierda está colapsado

siVenceLaSesion(() => iniciar());
// Errores que se escapan de las acciones (fuera de correr): un aviso entendible en vez de nada (el detalle, en la consola)
// (solo errores de programación: los de red o de librerías ya se manejan donde corresponde)
window.addEventListener('unhandledrejection', ev => {
  if (ev.reason instanceof TypeError && !/fetch|network|load failed/i.test(ev.reason.message) || ev.reason instanceof ReferenceError) aviso('Algo falló en la app. Probá de nuevo; si sigue pasando, recargá la página con el botón ↻ del navegador');
});

// Instalar como app: el service worker (sw.js, no guarda nada) y el botón "Instalar la app" del menú, que aparece cuando el
// navegador ofrece instalarla (Chrome y Edge; ya instalada, no aparece)
if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
let pedidoInstalar = null;
window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); pedidoInstalar = e; if ($('#instalar')) $('#instalar').hidden = false; });
window.addEventListener('appinstalled', () => { pedidoInstalar = null; if ($('#instalar')) $('#instalar').hidden = true; aviso('Listo: la app quedó instalada', 'ok'); });
async function instalar() {
  if (!pedidoInstalar) return aviso('Para instalarla, abrí el menú del navegador (⋮) y elegí "Instalar" o "Agregar a la pantalla de inicio"', 'info');
  pedidoInstalar.prompt();
  await pedidoInstalar.userChoice.catch(() => {});
  pedidoInstalar = null; $('#instalar').hidden = true;
}
document.addEventListener('keydown', e => { if (!sinRecargar(e) && !irAlMenu(e)) teclas?.(e); });
// Con algo cargado sin guardar, si igual se recarga o se cierra la pestaña, el navegador pregunta "¿Salir del sitio?"
window.addEventListener('beforeunload', e => { if (hayCargaSinGuardar()) { e.preventDefault(); e.returnValue = ''; } });

// F5, Ctrl + F5 y Ctrl + R no recargan en las pantallas de carga ni con algo cargado en otra (la carga vive en memoria)
const PANTALLAS_DE_CARGA = ['#/vender', '#/compras', '#/remitos'];
function sinRecargar(e) {
  const recarga = e.key === 'F5' || ((e.ctrlKey || e.metaKey) && e.code === 'KeyR');
  if (!recarga || !datos?.yo || !(PANTALLAS_DE_CARGA.includes(location.hash) || hayCargaSinGuardar())) return false;
  e.preventDefault(); e.stopPropagation();
  aviso('Para no perder lo que estás cargando, F5 no recarga la página', 'ok');
  return true;
}
window.addEventListener('hashchange', () => { if (datos?.yo) mostrarSeccion(); });

// ---------- Marca del negocio ----------
// El logo propio (Ajustes → Logo del negocio; config 'logo', una imagen chica como data:image/...). Se recuerda en la PC
// (localStorage 'marca') para que la próxima bienvenida lo muestre de entrada (bienvenida.js).
const logoNegocio = () => { const l = datos?.config?.logo; return typeof l === 'string' && l.startsWith('data:image/') ? l : ''; };
function recordarMarca() {
  try { localStorage.setItem('marca', JSON.stringify({ nombre: datos?.negocio?.nombre || '', logo: logoNegocio() })); } catch { /* sin almacenamiento */ }
}
// Ajustes cambió el logo (ctx.cambiarLogo): se ve en la barra sin recargar
function cambiarLogo(logo) {
  datos.config.logo = logo;
  recordarMarca();
  const cab = document.querySelector('.barra-cabeza');
  cab?.querySelector('.barra-logo')?.remove();
  if (logoNegocio()) cab?.insertAdjacentHTML('afterbegin', `<img class="barra-logo" src="${esc(logoNegocio())}" alt="">`);
}

// ---------- Bienvenida ----------
// La pantalla del logo (index.html) se va con un fundido apenas hay algo para mostrar: no agrega espera.
function quitarBienvenida() {
  const b = document.getElementById('bienvenida');
  if (!b || b.classList.contains('saliendo')) return;
  b.classList.add('saliendo');
  setTimeout(() => b.remove(), 400);
}

// ---------- Cuenta y usuario ----------
// Las pantallas de entrada: fondo verde, una tarjeta al centro con el logo (el del negocio, si tiene; si no, el de la app)
// y la firma abajo
const marcoEntrada = (contenido, logo = '') => {
  raiz.className = 'entrada';
  raiz.innerHTML = `<div class="entrada-caja"><img class="entrada-logo" src="${esc(logo || 'img/icon-192.png')}" alt="">${contenido}</div>
    <p class="entrada-firma">Powered by <b>Car-Ma Soft</b></p>`;
};
const inicial = nombre => esc(String(nombre || '?').trim().charAt(0).toUpperCase());

function pantallaCuenta() {
  quitarBienvenida();
  marcoEntrada(`<h1>Gestión de ventas</h1>
    <p class="muted">Entrá con la cuenta del negocio. En la PC del local se hace una sola vez.</p>
    <form id="f-cuenta" class="form">
      <label>Email<input class="input" name="email" type="email" autocomplete="username" required autofocus></label>
      <label>Contraseña<input class="input" name="clave" type="password" autocomplete="current-password" required></label>
      <button class="btn primario entrada-boton">Entrar</button>
    </form>
    <p class="pie"><button type="button" class="link" id="olvide-clave">¿Olvidaste la contraseña?</button></p>`);
  $('#olvide-clave').onclick = () => olvideClave($('#f-cuenta [name=email]').value);
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
  quitarBienvenida();
  marcoEntrada(`<h1>Gestión de ventas</h1><p class="aviso mal">${esc(mensaje)}</p>
    <div class="fila entrada-fila"><button class="btn primario" id="reintentar">Reintentar</button><button class="btn" id="salir">Salir de esta cuenta</button></div>`);
  $('#reintentar').onclick = () => iniciar();
  $('#salir').onclick = () => salirDeLaCuenta();
}

// Con un solo usuario no hay que elegir: va directo al PIN. Si además el dueño activó "Entrar sin PIN" (Usuarios), entra solo
// al abrir la app; después de "Cambiar de usuario" muestra el botón Entrar (así se puede salir de la cuenta de la PC).
let entradaAutomatica = true;
const soloUno = () => datos.usuarios.length === 1 ? datos.usuarios[0] : null;
const sinPin = () => soloUno()?.rol === 'admin' && datos.config?.entrar_sin_pin === true;
function pantallaElegir() {
  marcoEntrada(`<h1>${esc(datos.negocio.nombre)}</h1><p class="muted">¿Quién sos?</p>
    <div class="usuarios">${datos.usuarios.map(u => `<button class="usuario" data-id="${u.id}"><span class="usuario-ini">${inicial(u.nombre)}</span>
      <span class="usuario-txt"><b>${esc(u.nombre)}</b><small>${ROL[u.rol]}</small></span><span class="usuario-flecha" aria-hidden="true">›</span></button>`).join('')}</div>
    <form id="f-pin" class="form" hidden>
      <div class="pin-quien"><span class="usuario-ini grande" id="pin-ini"></span><b id="pin-de"></b></div>
      <label class="pin-campo"><span class="pin-ayuda">Tu PIN</span><input class="input pin" name="pin" type="password" inputmode="numeric" autocomplete="off" maxlength="8" pattern="\\d{4,8}" required></label>
      <div class="teclado-pin" aria-label="Teclado numérico">${[1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => `<button type="button" data-tecla="${n}">${n}</button>`).join('')}
        <button type="button" data-tecla="borrar" aria-label="Borrar">⌫</button><button type="button" data-tecla="0">0</button><button type="button" data-tecla="limpiar" aria-label="Borrar todo">C</button></div>
      <div class="fila entrada-fila"><button type="button" class="btn" id="volver">Volver</button><button class="btn primario">Entrar</button></div>
      <p class="pin-olvido"><button type="button" class="link" id="olvide">¿Olvidaste tu PIN?</button></p>
    </form>
    <p class="pie"><button class="link" id="salir">Salir de la cuenta de esta PC</button></p>`, logoNegocio());
  let elegido = null;
  $$('.usuario').forEach(b => b.onclick = () => {
    elegido = datos.usuarios.find(u => u.id === +b.dataset.id);
    $('.usuarios').hidden = true; $('#f-pin').hidden = false; $('p.muted', raiz).hidden = true;   // ya eligió: fuera el '¿Quién sos?'
    $('#pin-de').textContent = elegido.nombre;
    $('#pin-ini').textContent = elegido.nombre.trim().charAt(0).toUpperCase();
    $('#f-pin [name=pin]').focus();
  });
  $('#volver').onclick = () => pantallaElegir();
  $('#olvide').onclick = () => {
    if (elegido?.rol !== 'admin') return aviso(`El PIN de ${elegido?.nombre || 'un empleado'} lo cambia el dueño, en Usuarios`, 'info');
    olvidePin(elegido, () => { const pin = $('#f-pin [name=pin]'); pin.value = ''; pin.focus(); });
  };
  $$('[data-tecla]').forEach(b => b.onclick = () => {
    const pin = $('#f-pin [name=pin]'), t = b.dataset.tecla;
    pin.value = t === 'borrar' ? pin.value.slice(0, -1) : t === 'limpiar' ? '' : (pin.value + t).slice(0, 8);
    pin.focus();
  });
  $('#f-pin').onsubmit = e => {
    e.preventDefault();
    const pin = new FormData(e.target).get('pin');
    correr(async () => {
      const r = await llamar('iniciar_usuario', { p_usuario_id: elegido.id, p_pin: pin });
      if (r.error) {   // (si entraba sin PIN y ya no se puede, por ejemplo porque se agregó otro usuario, aparece el campo)
        e.target.reset(); const pin = $('#f-pin [name=pin]'); pin.required = true; pin.closest('label').hidden = false; $('.teclado-pin').hidden = false; pin.focus(); return aviso(r.error);
      }
      guardarToken(r.token);
      await iniciar();
    });
  };
  $('#salir').onclick = async () => {
    if (confirm('Para volver a entrar en esta PC va a hacer falta el email y la contraseña de la cuenta. ¿Salir?')) await salirDeLaCuenta();
  };
  if (soloUno()) {
    $('.usuarios').hidden = true; $('#volver').hidden = true; $('p.muted', raiz).hidden = true;
    $('.usuario').click();   // el formulario del PIN, ya con su nombre
    if (sinPin()) {
      const pin = $('#f-pin [name=pin]');
      pin.required = false; pin.closest('label').hidden = true; $('.teclado-pin').hidden = true; $('.pin-olvido').hidden = true;
      $('#f-pin .btn.primario').textContent = `Entrar como ${soloUno().nombre}`;
      if (entradaAutomatica) { $('#f-pin').requestSubmit(); return; }   // la bienvenida sigue hasta que aparece Hoy
    }
  }
  quitarBienvenida();
}

// "¿Olvidaste tu PIN?" (solo para un dueño): con el email y la contraseña de la cuenta del dueño (no la de esta PC) se pone
// un PIN nuevo. Esa cuenta se inicia aparte, solo para esto (llamarComoDueno): la PC sigue con su cuenta.
function olvidePin(u, alTerminar) {
  const m = modal('¿Olvidaste tu PIN?', `<form class="form" id="f-olvido">
    <p class="muted">Para ponerle un PIN nuevo a <b>${esc(u.nombre)}</b>, entrá con la <b>cuenta del dueño</b> (su email y contraseña). No es la cuenta
      con la que está abierta esta PC. No queda guardada.</p>
    <p class="chico pista-dueno" id="pista-dueno" hidden></p>
    <label>Email del dueño<input class="input" name="email" type="email" autocomplete="off" required autofocus></label>
    <label>Contraseña<input class="input" name="clave" type="password" autocomplete="off" required></label>
    <div class="fila"><label class="crece">PIN nuevo <span class="muted">(4 a 8 números)</span><input class="input pin" name="pin" type="password" inputmode="numeric" maxlength="8" pattern="\\d{4,8}" required></label>
      <label class="crece">Repetilo<input class="input pin" name="pin2" type="password" inputmode="numeric" maxlength="8" pattern="\\d{4,8}" required></label></div>
    <p class="chico"><button type="button" class="link" id="olvide-clave-dueno">¿Olvidaste la contraseña de la cuenta del dueño?</button></p>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Poner PIN nuevo</button></div></form>`);
  // la pista: el email del dueño a medias (h•••••@gmail.com)
  llamar('pista_cuenta_dueno').then(p => { if (p) { $('#pista-dueno', m.el).innerHTML = `La cuenta del dueño es <b>${esc(p)}</b>`; $('#pista-dueno', m.el).hidden = false; } }).catch(() => {});
  $('#olvide-clave-dueno', m.el).onclick = () => olvideClave($('[name=email]', m.el).value);
  $('#f-olvido', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    if (f.get('pin') !== f.get('pin2')) return aviso('Los dos PIN no son iguales');
    correr(async () => {
      await llamarComoDueno(String(f.get('email')).trim(), f.get('clave'), 'restablecer_pin', { p_usuario_id: u.id, p_pin: f.get('pin') });
      m.cerrar(); aviso(`Listo: ${u.nombre} ya puede entrar con el PIN nuevo`, 'ok'); alTerminar();
    });
  };
}

// "¿Olvidaste la contraseña?": se manda un mail con un enlace para elegir una nueva (recuperar.html). Es la contraseña de
// la app, no la del mail. No se dice si el email existe o no (Supabase tampoco).
function olvideClave(email = '') {
  const m = modal('¿Olvidaste la contraseña?', `<form class="form" id="f-olvide-clave">
    <p class="muted">Escribí el email de la cuenta. Te llega un mail con un enlace para elegir una contraseña nueva (es la de la app, no la de tu mail).</p>
    <p class="chico pista-dueno">📬 Si no lo ves en unos minutos, revisá <b>Spam</b> o <b>Correo no deseado</b>. El mail llega de Supabase y puede venir en inglés ("Reset Password").</p>
    <label>Email<input class="input" name="email" type="email" autocomplete="email" required autofocus value="${esc(email)}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Mandar el mail</button></div></form>`);
  $('#f-olvide-clave', m.el).onsubmit = e => {
    e.preventDefault();
    const mail = String(new FormData(e.target).get('email')).trim();
    correr(async () => {
      await mandarRecuperacion(mail);
      m.cerrar();
      aviso(`Listo: si ${mail} es de una cuenta, en unos minutos llega el mail (mirá también en "Correo no deseado")`, 'ok');
    });
  };
}

async function cambiarDeUsuario() {
  entradaAutomatica = false;
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

// Menú de la izquierda: los bloques de secciones (sin títulos, separados por una línea), el de Usuarios y Ajustes abajo,
// y debajo el bloque del usuario. Los bloques vacíos no se muestran (para el empleado solo queda el del día a día).
function menuPorGrupos(yo) {
  const enlace = s => `<a href="${s.ruta}" data-ruta="${s.ruta}" title="${esc(s.nombre)}" class="${s.ruta === '#/vender' ? 'menu-vender' : ''}">
      <span class="menu-ico" aria-hidden="true">${s.ico}</span><span class="menu-txt">${esc(s.nombre)}</span></a>`;
  const bloque = g => {
    const lista = SECCIONES.filter(s => s.grupo === g && !s.aparte && (!s.admin || yo.rol === 'admin'));
    return lista.length ? `<div class="menu-grupo">${lista.map(enlace).join('')}</div>` : '';
  };
  const quien = `${yo.nombre} · ${ROL[yo.rol]}`;
  return `<div class="menu-bloques">${GRUPOS.filter(g => g !== 'admin').map(bloque).join('')}</div>
    <div class="menu-pie">${bloque('admin')}
      <div class="menu-grupo menu-usuario">
        <a href="#/ayuda" data-ruta="#/ayuda" title="Ayuda: cómo hacer cada cosa"><span class="menu-ico" aria-hidden="true">?</span><span class="menu-txt">Ayuda</span></a>
        <div class="menu-quien" title="${esc(quien)}"><span class="menu-ico" aria-hidden="true">👤</span><span class="menu-txt">${esc(quien)}</span></div>
        ${yo.rol === 'admin' ? '' : `<button class="menu-accion" id="mi-pin-menu" title="Cambiar mi PIN"><span class="menu-ico" aria-hidden="true">🔑</span><span class="menu-txt">Cambiar mi PIN</span></button>`}
        <button class="menu-accion" id="instalar" title="Instalar la app en esta PC o celular: ícono propio y ventana sin la barra del navegador" ${pedidoInstalar ? '' : 'hidden'}><span class="menu-ico" aria-hidden="true">⬇️</span><span class="menu-txt">Instalar la app</span></button>
        <button class="menu-accion" id="cambiar" title="Cambiar de usuario"><span class="menu-ico" aria-hidden="true">🔁</span><span class="menu-txt">Cambiar de usuario</span></button>
      </div>
      <div class="menu-firma" title="Powered by Car-Ma Soft"><span class="menu-txt">Powered by <b>Car-Ma Soft</b></span><span class="menu-firma-corta" aria-hidden="true">CM</span></div></div>`;
}

// Si la PC tiene el menú colapsado (localStorage puede fallar: entonces arranca abierto)
const leerColapsado = () => { try { return localStorage.getItem(CLAVE_COLAPSADO) === '1'; } catch { return false; } };
const guardarColapsado = si => { try { localStorage.setItem(CLAVE_COLAPSADO, si ? '1' : '0'); } catch { /* sin almacenamiento: no se recuerda */ } };
function colapsar(si) {
  raiz.classList.toggle('colapsada', si);
  const b = $('#colapsar');
  if (!b) return;
  b.textContent = si ? '»' : '«';
  b.setAttribute('aria-label', si ? 'Mostrar el menú' : 'Achicar el menú');
  b.title = `${b.getAttribute('aria-label')} (${textoAtajo(atajoDe(datos?.config))} para ir al menú con el teclado)`;
  b.setAttribute('aria-expanded', String(!si));
}

// En el celular la barra queda fija arriba y tapa lo de arriba: su alto va a --alto-barra (lo usan el scroll y los
// paneles fijos, como el de cobro en Vender). En la PC, 0px.
const celular = matchMedia('(max-width: 800px)');
let medirBarra = null;
function seguirAltoBarra() {
  medirBarra?.disconnect();
  const barra = $('#barra');
  const poner = () => document.documentElement.style.setProperty('--alto-barra', celular.matches && barra ? barra.offsetHeight + 'px' : '0px');
  if (barra && 'ResizeObserver' in window) { medirBarra = new ResizeObserver(poner); medirBarra.observe(barra); }
  poner();
}
celular.addEventListener('change', () => seguirAltoBarra());

function armarMarco() {
  const yo = datos.yo;
  raiz.className = 'marco';
  // En la PC, barra a la izquierda que se puede colapsar (« »). En el celular, barra arriba: el menú y el usuario se
  // esconden detrás del botón ☰, que muestra la sección actual.
  raiz.innerHTML = `<header class="barra" id="barra">
      <div class="barra-cabeza">${logoNegocio() ? `<img class="barra-logo" src="${esc(logoNegocio())}" alt="">` : ''}<div class="negocio" title="${esc(datos.negocio.nombre)}">${esc(datos.negocio.nombre)}</div>
        <button class="barra-colapsar" id="colapsar"></button>
        <button class="menu-boton" id="menu" aria-expanded="false" aria-controls="menu-nav"><span aria-hidden="true">☰</span> <span id="seccion-actual">Menú</span></button></div>
      <nav id="menu-nav">${menuPorGrupos(yo)}</nav></header>
    <main id="vista" class="vista"></main>`;
  colapsar(leerColapsado());
  $('#colapsar').onclick = () => { const si = !raiz.classList.contains('colapsada'); colapsar(si); guardarColapsado(si); };
  $('#cambiar').onclick = () => cambiarDeUsuario();
  $('#instalar').onclick = instalar;
  if ($('#mi-pin-menu')) $('#mi-pin-menu').onclick = () => { abrirMenu(false); cambiarMiPin(); };
  $('#menu').onclick = () => abrirMenu(!$('#barra').classList.contains('abierto'));
  $('#menu-nav').onkeydown = teclasDelMenu;
  seguirAltoBarra();
}

// Con el foco en el menú: ↑ ↓ pasan a la anterior o la siguiente (dando la vuelta) y la van mostrando, Inicio y Fin a la
// primera y la última, Ctrl + → a la pantalla abierta. Enter abre la sección, como un clic: el foco queda en el menú.
function teclasDelMenu(e) {
  if (e.key === 'ArrowRight' && e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey) { e.preventDefault(); return enfocarPantalla(); }
  if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
  const items = $$('#menu-nav a, #menu-nav button').filter(x => x.offsetParent !== null);
  const k = items.indexOf(document.activeElement);
  if (k < 0) return;
  const ir = { ArrowDown: items[(k + 1) % items.length], ArrowUp: items[(k - 1 + items.length) % items.length],
    Home: items[0], End: items[items.length - 1] }[e.key];
  if (ir) { e.preventDefault(); ir.focus(); mostrarAlPasar(ir); }
}
// Al pasar por una sección con las flechas se muestra su pantalla (un instante después, así no carga todas si se pasa
// rápido) y el foco sigue en el menú. Sin sumar al historial. En el celular no: el menú tapa la pantalla.
let alPasar = null;
let quedarEnMenu = false;
function mostrarAlPasar(a) {
  clearTimeout(alPasar);
  const ruta = a.dataset.ruta;
  if (!ruta || celular.matches || ruta === location.hash) return;
  alPasar = setTimeout(() => { if (document.activeElement === a) { quedarEnMenu = true; location.replace(ruta); } }, 250);
}
// Si la pantalla se llevó el foco (por ejemplo, Vender al buscador), vuelve al menú
function volverAlMenu() {
  const a = $('#menu-nav a.activa');
  if (a && !$('#menu-nav').contains(document.activeElement) && !document.querySelector('.modal-fondo')) a.focus();
}
// El foco a la pantalla abierta: a su primer campo (en Vender, el buscador); si no tiene, a su primer botón o enlace
function enfocarPantalla() {
  const vista = $('#vista');
  if (!vista) return;
  if (celular.matches) abrirMenu(false);
  const visible = el => el.offsetParent !== null && !el.disabled;
  const destino = $$('input:not([type=hidden]):not([type=checkbox]):not([type=radio]), select, textarea', vista).find(visible)
    || $$('button, a[href], summary', vista).find(visible);
  if (destino) return destino.focus();
  vista.tabIndex = -1; vista.focus();
}
// El atajo (Ajustes → Teclado, Ctrl + ← de fábrica) lleva el foco al menú, a la sección en la que estás.
// Con una ventana abierta no hace nada.
function irAlMenu(e) {
  if (!datos?.yo || !$('#menu-nav') || !esAtajo(e, atajoDe(datos.config))) return false;
  e.preventDefault();
  if (document.querySelector('.modal-fondo')) return true;
  if (celular.matches) abrirMenu(true);
  ($('#menu-nav a.activa') || $('#menu-nav a'))?.focus();
  return true;
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
  const desdeElMenu = quedarEnMenu;
  quedarEnMenu = false;
  if (!desdeElMenu) abrirMenu(false);
  teclas = null;
  const vista = $('#vista');
  // mientras carga, la forma de una pantalla en gris que "late" (aparece recién si tarda: sin parpadeo en lo rápido)
  vista.innerHTML = `<div class="esqueleto" role="status" aria-label="Cargando ${esc(s.nombre)}"><div class="esq esq-titulo"></div>
    <div class="esq-tarjetas"><div class="esq"></div><div class="esq"></div><div class="esq"></div></div><div class="esq esq-tabla"></div></div>`;
  const ctx = {
    yo, negocio: datos.negocio, usuarios: datos.usuarios,
    config: datos.config,          // configuración del negocio (datos para el ticket, cuándo imprimir); Ajustes la actualiza
    ir: ruta => { location.replace(ruta); },   // sin sumar al historial (ver ui.js: botón atrás)
    recargar: () => mostrarSeccion(),
    cambiarLogo,
    alTeclear: fn => { teclas = fn; },
  };
  let ok = false;
  await correr(async () => { await s.fn(vista, ctx); ok = true; });
  quitarBienvenida();
  if (ok && $('#vista') === vista) {   // la pantalla nueva entra con un fundido corto
    vista.classList.remove('entrando'); void vista.offsetWidth; vista.classList.add('entrando');
  }
  if (desdeElMenu && location.hash === s.ruta) { volverAlMenu(); setTimeout(volverAlMenu, 50); }
  // si no se pudo cargar (sin internet, la base no respondió), no queda en "Cargando…": se ofrece reintentar
  if (!ok && $('#vista') === vista && vista.querySelector('.esqueleto')) {
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
  const bvNegocio = document.getElementById('bv-negocio');
  if (bvNegocio && datos.negocio?.nombre) bvNegocio.textContent = datos.negocio.nombre;   // en la bienvenida, el nombre del negocio
  recordarMarca();
  document.title = `Gestión de ventas · ${datos.negocio.nombre}`;
  if (!datos.yo) { guardarToken(null); return pantallaElegir(); }
  armarMarco();
  sc.iniciar(datos.negocio.id, datos.yo, datos.usuarios);   // ventas hechas sin conexión: la barra de aviso y subir las que quedaron
  const ok = await correr(async () => { await cat.cargar(datos.negocio.id); return true; });
  if (!ok) return quitarBienvenida();
  refresco = setInterval(() => cat.actualizar().catch(() => {}), 60 * 1000);
  // la primera vez que entra el dueño, el recorrido de bienvenida (un momento después, con la pantalla ya armada)
  setTimeout(() => recorridoPrimeraVez(datos), 700);
  // al abrir la app (o recargar la página) siempre arranca en la primera sección, Hoy, aunque la dirección quedara en otra.
  // Con location.replace (como el menú), no replaceState: así el manejo del botón "atrás" (ui.js) se entera del cambio;
  // el cambio de dirección muestra la sección solo (hashchange).
  if (!abierta) {
    abierta = true;
    if (location.hash !== SECCIONES[0].ruta) return location.replace(SECCIONES[0].ruta);
  }
  await mostrarSeccion();
}
let abierta = false;   // ya se mostró la primera pantalla desde que se abrió la app

iniciar();
