// Contraseña nueva (recuperar.html): se llega desde el enlace del mail de "¿Olvidaste la contraseña?". El enlace trae una
// sesión de recuperación en la dirección (#access_token=…&type=recovery). Se usa una conexión aparte, que no se guarda:
// así no reemplaza la cuenta iniciada en la app de esta PC. Se elige la contraseña nueva y se cierra esa sesión.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/+esm';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: true, flowType: 'implicit', storageKey: 'kioscos-recupero' },
});
const raiz = document.getElementById('app');
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const caja = html => {
  raiz.innerHTML = `<div class="entrada-caja"><img class="entrada-logo" src="img/icon-192.png" alt="">${html}</div>
    <p class="entrada-firma">Powered by <b>Car-Ma Soft</b></p>`;
};
const alApp = '<p class="pie"><a href="./">Ir a la app</a></p>';

async function empezar() {
  // el enlace puede traer un error (vencido o ya usado) en la dirección
  const datos = new URLSearchParams(location.hash.slice(1) || location.search.slice(1));
  if (datos.get('error') || datos.get('error_description')) return vencido();
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return vencido();
  history.replaceState(null, '', location.pathname);   // que el enlace no quede en la barra ni en el historial
  caja(`<h1>Contraseña nueva</h1><p class="muted">Para la cuenta <b>${esc(session.user.email)}</b>. Es la contraseña de la app, no la de tu mail.</p>
    <form class="form" id="f-nueva">
      <label>Contraseña nueva <span class="muted">(al menos 8 caracteres)</span><input class="input" name="clave" type="password" autocomplete="new-password" minlength="8" required autofocus></label>
      <label>Repetila<input class="input" name="clave2" type="password" autocomplete="new-password" minlength="8" required></label>
      <p class="aviso mal" id="error" hidden></p>
      <button class="btn primario entrada-boton">Guardar contraseña</button>
    </form>`);
  document.getElementById('f-nueva').onsubmit = async e => {
    e.preventDefault();
    const f = new FormData(e.target), error = document.getElementById('error'), boton = e.target.querySelector('button');
    error.hidden = true;
    if (f.get('clave') !== f.get('clave2')) { error.textContent = 'Las dos contraseñas no son iguales'; error.hidden = false; return; }
    boton.disabled = true;
    const { error: e2 } = await sb.auth.updateUser({ password: f.get('clave') });
    boton.disabled = false;
    if (e2) {
      error.textContent = /should be different|same/i.test(e2.message) ? 'Tiene que ser distinta de la anterior'
        : /weak|least|short/i.test(e2.message) ? 'Es muy corta o muy fácil: probá con otra más larga' : 'No se pudo guardar: ' + e2.message;
      error.hidden = false; return;
    }
    await sb.auth.signOut({ scope: 'local' }).catch(() => {});
    caja(`<h1>¡Listo!</h1><p class="muted">Ya podés entrar con la contraseña nueva. Si estabas en "¿Olvidaste tu PIN?", volvé a la app y usala ahí.</p>${alApp}`);
  };
}

function vencido() {
  caja(`<h1>El enlace ya no sirve</h1><p class="muted">Venció o ya se usó. Pedí otro desde la app con <b>¿Olvidaste la contraseña?</b>.</p>${alApp}`);
}

empezar().catch(() => vencido());
