// URL base: siempre relativa. Nginx proxea /api en local,
// el Ingress lo enruta en Kubernetes. Sin cambios entre ambientes.
var base = "/api";

function mostrarSalida(texto) {
  var out = document.getElementById("out");
  out.textContent = (typeof texto === "string") ? texto : JSON.stringify(texto, null, 2);
}

function obtenerValores() {
  var a = parseFloat(document.getElementById("in-a").value);
  var b = parseFloat(document.getElementById("in-b").value);
  if (isNaN(a) || isNaN(b)) { throw "Los valores de A y B deben ser numeros."; }
  return { a: a, b: b };
}

function handleResponse(r) {
  if (!r.ok && r.status !== 400) { throw "HTTP " + r.status; }
  return r.json();
}

function sumar() {
  try {
    var v = obtenerValores();
    fetch(base + "/sumar?a=" + encodeURIComponent(v.a) + "&b=" + encodeURIComponent(v.b))
      .then(handleResponse).then(mostrarSalida)
      .catch(function (e) { mostrarSalida("Error: " + e); });
  } catch (e) { mostrarSalida("Error: " + e); }
}

function restar() {
  try {
    var v = obtenerValores();
    fetch(base + "/restar?a=" + encodeURIComponent(v.a) + "&b=" + encodeURIComponent(v.b))
      .then(handleResponse).then(mostrarSalida)
      .catch(function (e) { mostrarSalida("Error: " + e); });
  } catch (e) { mostrarSalida("Error: " + e); }
}

function multiplicar() {
  try {
    var v = obtenerValores();
    fetch(base + "/multiplicar", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(v)
    }).then(handleResponse).then(mostrarSalida)
      .catch(function (e) { mostrarSalida("Error: " + e); });
  } catch (e) { mostrarSalida("Error: " + e); }
}

function dividir() {
  try {
    var v = obtenerValores();
    fetch(base + "/dividir", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(v)
    }).then(handleResponse).then(function (data) {
      if (data && data.detail) { mostrarSalida("Aviso: " + data.detail); }
      else { mostrarSalida(data); }
    }).catch(function (e) { mostrarSalida("Error: " + e); });
  } catch (e) { mostrarSalida("Error: " + e); }
}

function checkHealth() {
  var el = document.getElementById("health-msg");
  fetch(base + "/health")
    .then(function (r) {
      if (!r.ok) { throw "API no disponible"; }
      return r.json();
    })
    .then(function (data) {
      if (data && data.status === "ok") {
        el.textContent = "API OK (" + (data.environment || "?") + ")";
        el.style.color = "#16a34a";
      } else {
        el.textContent = "API responde, revisar estado";
        el.style.color = "#d97706";
      }
    })
    .catch(function () {
      el.textContent = "No se pudo conectar a la API.";
      el.style.color = "#b91c1c";
    });
}

checkHealth();
// trigger CI
