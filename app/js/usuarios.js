// Usuarios (solo dueño) y cambiar mi PIN
import { llamar } from './base.js';
import { $, $$, esc, ROL, aviso, correr, modal } from './ui.js';

export async function pantallaUsuarios(vista, ctx) {
  const admin = ctx.yo.rol === 'admin';
  const lista = admin ? await llamar('listar_usuarios') : [];
  vista.innerHTML = `<div class="cabecera"><h2>${admin ? 'Usuarios' : 'Mi usuario'}</h2>
      <div class="acciones"><button class="btn" id="mi-pin">Cambiar mi PIN</button>${admin ? '<button class="btn primario" id="nuevo">＋ Nuevo usuario</button>' : ''}</div></div>
    ${admin ? `<div class="tabla-caja"><table class="tabla"><thead><tr><th>Nombre</th><th>Rol</th><th>Estado</th><th></th></tr></thead><tbody>
      ${lista.map(u => `<tr><td>${esc(u.nombre)}</td><td>${ROL[u.rol]}</td><td>${u.activo ? (u.bloqueado ? 'Bloqueado unos minutos' : 'Activo') : 'Desactivado'}</td>
        <td class="num"><button class="link" data-editar="${u.id}">Editar</button></td></tr>`).join('')}</tbody></table></div>` : ''}`;
  $('#mi-pin').onclick = () => miPin();
  if (admin) {
    $('#nuevo').onclick = () => formUsuario(null);
    $$('[data-editar]').forEach(b => b.onclick = () => formUsuario(lista.find(u => u.id === +b.dataset.editar)));
  }

  function formUsuario(u) {
    const m = modal(u ? 'Editar ' + u.nombre : 'Nuevo usuario', `<form class="form" id="f-usuario">
      <label>Nombre<input class="input" name="nombre" maxlength="40" required value="${esc(u?.nombre || '')}" autofocus></label>
      <label>Rol<select class="input" name="rol"><option value="empleado">Empleado</option><option value="admin" ${u?.rol === 'admin' ? 'selected' : ''}>Dueño</option></select></label>
      <label>${u ? 'PIN nuevo <span class="muted">(vacío = no cambia)</span>' : 'PIN <span class="muted">(4 a 8 números)</span>'}<input class="input pin" name="pin" type="password" inputmode="numeric" autocomplete="new-password" maxlength="8" pattern="\\d{4,8}" ${u ? '' : 'required'}></label>
      ${u ? `<label class="check"><input type="checkbox" name="activo" ${u.activo ? 'checked' : ''}> Activo</label>` : ''}
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
    $('#f-usuario', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target);
      correr(async () => {
        await llamar('guardar_usuario', { p_id: u?.id ?? null, p_nombre: f.get('nombre'), p_rol: f.get('rol'), p_activo: u ? f.get('activo') === 'on' : true, p_pin: f.get('pin') || null });
        m.cerrar(); aviso('Usuario guardado', 'ok'); ctx.recargar();
      });
    };
  }

  function miPin() {
    const m = modal('Cambiar mi PIN', `<form class="form" id="f-mipin">
      <label>PIN actual<input class="input pin" name="actual" type="password" inputmode="numeric" autocomplete="off" maxlength="8" required autofocus></label>
      <label>PIN nuevo <span class="muted">(4 a 8 números)</span><input class="input pin" name="nuevo" type="password" inputmode="numeric" autocomplete="new-password" maxlength="8" pattern="\\d{4,8}" required></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Cambiar</button></div></form>`);
    $('#f-mipin', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target);
      correr(async () => { await llamar('cambiar_mi_pin', { p_actual: f.get('actual'), p_nuevo: f.get('nuevo') }); m.cerrar(); aviso('PIN cambiado', 'ok'); });
    };
  }
}
