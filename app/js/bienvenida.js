// Bienvenida: el logo y el nombre del negocio, desde la primera vez que se vio en esta PC (localStorage 'marca').
// Es un script común (no módulo) que corre ni bien se dibuja la bienvenida, antes de que cargue el resto de la app:
// así el logo propio aparece de entrada, sin cambiar a mitad de la carga. app.js actualiza 'marca' cada vez que entra.
(function () {
  try {
    var m = JSON.parse(localStorage.getItem('marca') || 'null');
    if (!m) return;
    if (m.nombre) document.getElementById('bv-negocio').textContent = m.nombre;
    if (m.logo && m.logo.indexOf('data:image/') === 0) {
      var img = document.createElement('img');
      img.className = 'bv-logo bv-logo-propio'; img.alt = ''; img.src = m.logo;
      var svg = document.querySelector('#bienvenida .bv-logo');
      if (svg) svg.replaceWith(img);
    }
  } catch (e) { /* sin almacenamiento: queda el logo de la app */ }
})();
