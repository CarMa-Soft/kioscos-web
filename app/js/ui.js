// Utilidades de pantalla compartidas por todas las secciones
import { traducir, guardarToken, llamar } from './base.js';

export const $ = (sel, raiz = document) => raiz.querySelector(sel);
export const $$ = (sel, raiz = document) => [...raiz.querySelectorAll(sel)];
export const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtPlata = new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const plata = n => fmtPlata.format(+n || 0);
export const cant = n => (+n || 0).toLocaleString('es-AR', { maximumFractionDigits: 3 });
export const fecha = iso => iso ? new Date(iso).toLocaleString('es-AR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }) : '—';
// Fechas de calendario (AAAA-MM-DD: fecha de factura, vencimiento)
export const dia = d => d ? new Date(d + 'T12:00').toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric' }) : '—';
export const hoyDia = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
export const sumarDias = (d, n) => { const x = new Date(d + 'T12:00'); x.setDate(x.getDate() + (+n || 0)); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
export const diasHasta = d => Math.round((new Date(d + 'T12:00') - new Date(hoyDia() + 'T12:00')) / 864e5);
// "venció hace 5 días" / "vence hoy" / "vence en 3 días"
export const textoVence = d => { const n = diasHasta(d); return n < 0 ? `<span class="mal">venció hace ${-n} día${n === -1 ? '' : 's'}</span>` : n === 0 ? '<span class="mal">vence hoy</span>' : `vence en ${n} día${n === 1 ? '' : 's'}`; };
export const hora = iso => iso ? new Date(iso).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }) : '—';
// Número escrito por la persona: acepta coma decimal; vacío = NaN
export const numero = v => {
  let s = String(v ?? '').trim().replace(/\s|\$/g, '');
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');   // 1.234,50 → 1234.50
  return s === '' ? NaN : +s;
};
export const ROL = { admin: 'Dueño', empleado: 'Empleado' };

export function aviso(texto, tipo = 'mal') {
  const el = $('#aviso');
  el.textContent = texto; el.className = 'aviso flotante ' + tipo; el.hidden = !texto;
  clearTimeout(aviso.t);
  if (texto) aviso.t = setTimeout(() => { el.hidden = true; }, tipo === 'mal' ? 7000 : 3500);
}

// Si una acción avisa que venció la sesión del usuario, la app vuelve a pedir usuario y PIN
let alVencerSesion = () => location.reload();
export const siVenceLaSesion = fn => { alVencerSesion = fn; };

// Corre una acción mostrando el error en pantalla
export async function correr(fn) {
  try { return await fn(); } catch (e) {
    const err = e && e.codigo !== undefined ? e : traducir(e);
    if (err.codigo === 'sesion') { guardarToken(null); aviso(err.message); return alVencerSesion(); }
    aviso(err.message);
    return undefined;
  }
}

// Ventana sobre la pantalla. Devuelve { el, cerrar }. Escape o "Cancelar" (data-cerrar) la cierran.
export function modal(titulo, cuerpo, { ancho = false, alCerrar } = {}) {
  const fondo = document.createElement('div');
  fondo.className = 'modal-fondo';
  fondo.innerHTML = `<div class="modal ${ancho ? 'ancho' : ''}" role="dialog" aria-modal="true"><h2>${esc(titulo)}</h2>${cuerpo}</div>`;
  document.body.append(fondo);
  const cerrar = () => { fondo.remove(); document.removeEventListener('keydown', tecla); alCerrar?.(); };
  const tecla = e => { if (e.key === 'Escape') cerrar(); };
  document.addEventListener('keydown', tecla);
  $$('[data-cerrar]', fondo).forEach(b => b.onclick = cerrar);
  setTimeout(() => $('[autofocus], input, select, button.primario', fondo)?.focus(), 30);
  return { el: fondo, cerrar };
}

// Un dueño autoriza con su PIN algo que el usuario actual no puede hacer solo (descuento por encima del tope,
// devolución). Devuelve el permiso de un solo uso de autorizar_dueno, o null si se cancela.
export function pedirAutorizacion(usuarios, mensaje) {
  return new Promise(listo => {
    const duenos = usuarios.filter(u => u.rol === 'admin');
    let token = null;
    const m = modal('Autorización del dueño', `<form class="form" id="f-aut"><p>${esc(mensaje)}</p>
      <label ${duenos.length === 1 ? 'hidden' : ''}>Dueño<select class="input" name="dueno">${duenos.map(u => `<option value="${u.id}">${esc(u.nombre)}</option>`).join('')}</select></label>
      <label>PIN ${duenos.length === 1 ? 'de ' + esc(duenos[0].nombre) : 'del dueño'}<input class="input pin" name="pin" type="password" inputmode="numeric" autocomplete="off" maxlength="8" required autofocus></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Autorizar</button></div></form>`,
      { alCerrar: () => listo(token) });
    $('#f-aut', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target);
      correr(async () => {
        const r = await llamar('autorizar_dueno', { p_dueno_id: +f.get('dueno'), p_pin: f.get('pin') });
        if (r.error) { e.target.pin.value = ''; return aviso(r.error); }
        token = r.token; m.cerrar();
      });
    };
  });
}

export function confirmar(titulo, texto, boton = 'Aceptar') {
  return new Promise(res => {
    const m = modal(titulo, `<p>${esc(texto)}</p><div class="fila fin"><button class="btn" data-cerrar>Cancelar</button><button class="btn primario" id="si">${esc(boton)}</button></div>`,
      { alCerrar: () => res(false) });
    $('#si', m.el).onclick = () => { res(true); m.el.remove(); };
  });
}
