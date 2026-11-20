// Atajo de teclado para ir al menú (Ajustes → Teclado; config 'atajo_menu' del negocio, Ctrl + ← de fábrica).
// Ctrl + → (con el foco en el menú) pasa a la pantalla: es fijo y no se puede elegir como atajo.
// Un atajo es { alt, ctrl, shift, code }: code es la tecla física (KeyM, F4…), así no depende del idioma del teclado.

export const ATAJO_FABRICA = { alt: false, ctrl: true, shift: false, code: 'ArrowLeft' };

// El atajo del negocio (si lo guardado no sirve, el de fábrica)
export function atajoDe(config) {
  const a = config?.atajo_menu;
  return a && typeof a.code === 'string' && !problemaAtajo(a) ? { alt: !!a.alt, ctrl: !!a.ctrl, shift: !!a.shift, code: a.code } : ATAJO_FABRICA;
}

// La tecla, para mostrar: KeyM → M, Digit5 → 5, F4 → F4, ArrowLeft → ←
const FLECHAS = { ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓' };
const nombreTecla = code => FLECHAS[code] || (/^Key[A-Z]$/.test(code) ? code.slice(3) : /^Digit\d$/.test(code) ? code.slice(5) : code);
export const textoAtajo = a => [a.ctrl && 'Ctrl', a.alt && 'Alt', a.shift && 'Mayús', nombreTecla(a.code)].filter(Boolean).join(' + ');

// ¿Esta tecla apretada es el atajo?
export const esAtajo = (e, a) => e.code === a.code && e.altKey === a.alt && e.ctrlKey === a.ctrl && e.shiftKey === a.shift && !e.metaKey;

// Lo que se apretó, como atajo (null si todavía es solo Alt, Ctrl o Mayús)
export function atajoApretado(e) {
  if (/^(Alt|Control|Shift|Meta|OS)(Left|Right)?$/.test(e.code) || !e.code) return null;
  return { alt: e.altKey, ctrl: e.ctrlKey, shift: e.shiftKey, code: e.code };
}

// Teclas F que quedan libres (F1-F3 son de Vender; F5, F6, F10, F11 y F12, del navegador)
const F_LIBRES = ['F4', 'F7', 'F8', 'F9'];
// Ctrl + letra que usa el navegador (copiar, pegar, buscar, imprimir, recargar, pestañas…)
const CTRL_NAVEGADOR = ['KeyC', 'KeyV', 'KeyX', 'KeyZ', 'KeyY', 'KeyA', 'KeyF', 'KeyP', 'KeyR', 'KeyT', 'KeyW', 'KeyL', 'KeyN', 'KeyS', 'KeyD', 'KeyH', 'KeyJ', 'KeyU', 'KeyO', 'KeyK', 'KeyE', 'KeyG'];
const ESPECIALES = ['Escape', 'Enter', 'NumpadEnter', 'Tab', 'Space', 'Backspace', 'Delete', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End', 'PageUp', 'PageDown', 'Insert'];

// Si el atajo no se puede usar, por qué (texto para mostrar); si se puede, null
export function problemaAtajo(a) {
  if (!a || !a.code) return 'Apretá la combinación de teclas';
  if (a.code === 'ArrowLeft' && a.ctrl && !a.alt && !a.shift) return null;   // el de fábrica
  if (a.code === 'ArrowRight' && a.ctrl) return 'Ctrl + → ya se usa para pasar del menú a la pantalla';
  if (ESPECIALES.includes(a.code)) return 'Esa tecla ya tiene otro uso (Esc, Enter, Tab, flechas…)';
  if (/^F\d+$/.test(a.code)) {
    if (a.alt || a.ctrl || a.shift) return 'Las teclas F van solas (sin Alt, Ctrl ni Mayús)';
    return F_LIBRES.includes(a.code) ? null : `${a.code} ya se usa (F1 a F3 en Vender; F5, F6, F10, F11 y F12 en el navegador). Libres: ${F_LIBRES.join(', ')}`;
  }
  if (!a.alt && !a.ctrl) return 'Tiene que llevar Alt o Ctrl (o ser una de las teclas F libres), si no se escribiría al tipear';
  if (a.alt && !a.ctrl && /^(Digit|Numpad)[1-9]$/.test(a.code)) return 'Alt + número ya se usa para los accesos rápidos de Vender';
  if (a.ctrl && CTRL_NAVEGADOR.includes(a.code)) return `Ctrl + ${nombreTecla(a.code)} ya lo usa el navegador`;
  if (a.alt && !a.ctrl && ['KeyF', 'KeyE', 'KeyD'].includes(a.code)) return `Alt + ${nombreTecla(a.code)} ya lo usa el navegador`;
  if (a.ctrl && a.alt) return 'Mejor Alt o Ctrl, no los dos (Ctrl + Alt es AltGr en muchos teclados)';
  if (!/^(Key[A-Z]|Digit\d|F\d+)$/.test(a.code)) return 'Usá Ctrl + ←, o una letra, un número o una tecla F';
  return null;
}
