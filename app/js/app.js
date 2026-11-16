// Etapa 2: entrar con la cuenta (una vez por PC), elegir el usuario y poner el PIN, y administrar los usuarios.
import { sb, llamar, guardarToken, traducir } from './base.js';

const $ = sel => document.querySelector(sel);
const vista = $('#vista');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ROL = { admin: 'Dueño', empleado: 'Empleado' };
let datos = null;   // lo que devuelve datos_inicio()

function aviso(texto, tipo = 'mal') {
  const el = $('#aviso');
  el.textContent = texto; el.className = 'aviso ' + tipo; el.hidden = !texto;
  if (texto) clearTimeout(aviso.t), (aviso.t = setTimeout(() => { el.hidden = true; }, 5000));
}
// Corre una acción mostrando el error en pantalla; si venció la sesión del usuario, vuelve a elegir usuario
async function correr(fn) {
  try { return await fn(); } catch (e) {
    const err = e.codigo !== undefined ? e : traducir(e);
    if (err.codigo === 'sesion') { guardarToken(null); aviso(err.message); return iniciar(); }
    aviso(err.message);
  }
}

// ---------- Pantallas ----------

function pantallaCuenta() {
  vista.innerHTML = `<h1>Kioscos y Almacenes</h1>
    <p class="muted">Entrá con la cuenta del negocio. En la PC del local se hace una sola vez.</p>
    <form id="f-cuenta" class="form">
      <label>Email<input class="input" name="email" type="email" autocomplete="username" required></label>
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
  vista.innerHTML = `<h1>Kioscos y Almacenes</h1><p class="aviso mal">${esc(mensaje)}</p>
    <button class="btn" id="salir">Salir de esta cuenta</button>`;
  $('#salir').onclick = () => salirDeLaCuenta();
}

function pantallaElegir() {
  const n = datos.negocio;
  vista.innerHTML = `<h1>${esc(n.nombre)}</h1><p class="muted">¿Quién sos?</p>
    <div class="usuarios">${datos.usuarios.map(u => `<button class="usuario" data-id="${u.id}"><b>${esc(u.nombre)}</b><span>${ROL[u.rol]}</span></button>`).join('')}</div>
    <form id="f-pin" class="form" hidden>
      <label><span id="pin-de"></span><input class="input pin" name="pin" type="password" inputmode="numeric" autocomplete="off" maxlength="8" pattern="\\d{4,8}" required></label>
      <div class="fila"><button type="button" class="btn" id="volver">Volver</button><button class="btn primario">Entrar</button></div>
    </form>
    <p class="pie"><button class="link" id="salir">Salir de la cuenta de esta PC</button></p>`;
  let elegido = null;
  vista.querySelectorAll('.usuario').forEach(b => b.onclick = () => {
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

function pantallaInicio() {
  const yo = datos.yo, admin = yo.rol === 'admin';
  vista.innerHTML = `<div class="cabecera"><div><h1>${esc(datos.negocio.nombre)}</h1><p class="muted">Hola, ${esc(yo.nombre)} · ${ROL[yo.rol]}</p></div>
      <button class="btn" id="cambiar">Cambiar de usuario</button></div>
    <p class="aviso info">La versión web está en construcción: por ahora solo se administran los usuarios.</p>
    <div class="acciones">
      ${admin ? '<button class="btn" id="usuarios">Usuarios</button>' : ''}
      <button class="btn" id="mi-pin">Cambiar mi PIN</button>
    </div>
    <div id="panel"></div>`;
  $('#cambiar').onclick = () => correr(async () => { await llamar('cerrar_usuario'); guardarToken(null); await iniciar(); });
  $('#mi-pin').onclick = () => panelMiPin();
  if (admin) $('#usuarios').onclick = () => correr(panelUsuarios);
}

async function panelUsuarios() {
  const lista = await llamar('listar_usuarios');
  const panel = $('#panel');
  panel.innerHTML = `<h2>Usuarios</h2>
    <table class="tabla"><thead><tr><th>Nombre</th><th>Rol</th><th>Estado</th><th></th></tr></thead><tbody>
    ${lista.map(u => `<tr><td>${esc(u.nombre)}</td><td>${ROL[u.rol]}</td><td>${u.activo ? (u.bloqueado ? 'Bloqueado unos minutos' : 'Activo') : 'Desactivado'}</td>
      <td><button class="link" data-editar="${u.id}">Editar</button></td></tr>`).join('')}</tbody></table>
    <button class="btn" id="nuevo">＋ Nuevo usuario</button><div id="form-usuario"></div>`;
  $('#nuevo').onclick = () => formUsuario(null);
  panel.querySelectorAll('[data-editar]').forEach(b => b.onclick = () => formUsuario(lista.find(u => u.id === +b.dataset.editar)));
}

function formUsuario(u) {
  const box = $('#form-usuario');
  box.innerHTML = `<form class="form recuadro" id="f-usuario"><h3>${u ? 'Editar ' + esc(u.nombre) : 'Nuevo usuario'}</h3>
    <label>Nombre<input class="input" name="nombre" maxlength="40" required value="${esc(u?.nombre || '')}"></label>
    <label>Rol<select class="input" name="rol"><option value="empleado">Empleado</option><option value="admin" ${u?.rol === 'admin' ? 'selected' : ''}>Dueño</option></select></label>
    <label>${u ? 'PIN nuevo <span class="muted">(vacío = no cambia)</span>' : 'PIN'}<input class="input pin" name="pin" type="password" inputmode="numeric" autocomplete="new-password" maxlength="8" pattern="\\d{4,8}" ${u ? '' : 'required'}></label>
    ${u ? `<label class="check"><input type="checkbox" name="activo" ${u.activo ? 'checked' : ''}> Activo</label>` : ''}
    <div class="fila"><button type="button" class="btn" id="cancelar">Cancelar</button><button class="btn primario">Guardar</button></div></form>`;
  $('#cancelar').onclick = () => { box.innerHTML = ''; };
  $('#f-usuario').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    correr(async () => {
      await llamar('guardar_usuario', { p_id: u?.id ?? null, p_nombre: f.get('nombre'), p_rol: f.get('rol'), p_activo: u ? f.get('activo') === 'on' : true, p_pin: f.get('pin') || null });
      aviso('Usuario guardado', 'ok');
      datos = await llamar('datos_inicio');
      await panelUsuarios();
    });
  };
}

function panelMiPin() {
  $('#panel').innerHTML = `<form class="form recuadro" id="f-mipin"><h2>Cambiar mi PIN</h2>
    <label>PIN actual<input class="input pin" name="actual" type="password" inputmode="numeric" autocomplete="off" maxlength="8" required></label>
    <label>PIN nuevo <span class="muted">(4 a 8 números)</span><input class="input pin" name="nuevo" type="password" inputmode="numeric" autocomplete="new-password" maxlength="8" pattern="\\d{4,8}" required></label>
    <div class="fila"><button class="btn primario">Cambiar</button></div></form>`;
  $('#f-mipin').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    correr(async () => { await llamar('cambiar_mi_pin', { p_actual: f.get('actual'), p_nuevo: f.get('nuevo') }); $('#panel').innerHTML = ''; aviso('PIN cambiado', 'ok'); });
  };
}

async function salirDeLaCuenta() {
  await correr(async () => { try { await llamar('cerrar_usuario'); } catch { /* ya no había sesión */ } });
  guardarToken(null);
  await sb.auth.signOut();
  datos = null;
  pantallaCuenta();
}

// ---------- Arranque ----------
async function iniciar() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return pantallaCuenta();
  try { datos = await llamar('datos_inicio'); } catch (e) {
    if (/negocio activo/.test(e.message)) return pantallaSinNegocio(e.message);
    return pantallaSinNegocio(e.message);
  }
  if (!datos.yo) { guardarToken(null); return pantallaElegir(); }
  pantallaInicio();
}

iniciar();
