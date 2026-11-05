import 'package:flutter/widgets.dart';

import 'ajustes_movimiento.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Movimiento de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Duraciones, curvas y el resorte de la tabla de movimiento (sección 5 de la
// v5 del prompt, fase 3 del rediseño). Principios:
//   · Fluido es arrancar en el mismo cuadro de la acción y poder
//     interrumpirse: si se toca otra vez, sigue desde donde está, no empieza
//     de cero.
//   · Curvas de salida fuerte (entran rápido y frenan suave), escritas como
//     Cubic. Nunca Curves.easeIn; Curves.easeOutCubic se siente tarde.
//   · Nada rebota. Una animación por acción, sin encadenar.
//   · Según la frecuencia: lo que pasa decenas de veces por minuto (la
//     posición) dura 120 ms o menos; lo que pasa pocas veces (cambiar de
//     tramo, llegar, abrir una hoja) puede tener un movimiento completo.
//   · Sin animaciones que se repiten (pulsos, parpadeos, bucles) ni números
//     que cuentan.
//   · Toda animación, interrumpida, termina en su estado final sin saltos. En
//     segundo plano no corren (no hay cuadros) y al volver quedan en su
//     estado final: el primer cuadro trae todo el tiempo que pasó.
//
// ─── Movimiento reducido ───
// Con «Quitar animaciones» del teléfono o con «Reducir movimiento» de Ajustes
// (AjustesMovimiento), rige la columna de la derecha de la tabla: sin
// desplazamientos, escalas ni resortes; a lo sumo un fundido de 120 ms. Los
// componentes preguntan sólo acá (reducido).
//
// ─── Las curvas en reversa ───
// Una CurvedAnimation que corre hacia atrás (al cerrar una pantalla o una
// hoja) aplica la curva al valor, que baja: una curva de salida se sentiría
// de entrada (arrancaría lento). Para que la salida también arranque rápido,
// la curva de reversa es la misma dada vuelta (Curve.flipped).
abstract final class MovimientoApp {
  // ── Movimiento reducido ─────────────────────────────────────────────────

  /// Si hay que evitar el movimiento: «Quitar animaciones» del teléfono
  /// (MediaQuery.disableAnimations, al que AmbienteDiseno ya le suma el
  /// ajuste propio) o «Reducir movimiento» de Ajustes, que se lee también
  /// directo para lo que todavía no está envuelto (el mapa de la
  /// navegación).
  static bool reducido(BuildContext context) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      AjustesMovimiento.instancia.reducirMovimiento;

  /// Lo mismo, sin contexto: para las duraciones de las transiciones, que se
  /// fijan al abrir o cerrar una pantalla.
  static bool get reducidoSinContexto =>
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations ||
      AjustesMovimiento.instancia.reducirMovimiento;

  /// [normal], o cero (el cambio salta) con movimiento reducido.
  static Duration duracion(BuildContext context, Duration normal) =>
      reducido(context) ? Duration.zero : normal;

  // ── Curvas ──────────────────────────────────────────────────────────────

  /// La curva de casi todo: cubic-bezier(0.23, 1, 0.32, 1). Arranca rápido,
  /// así responde en el primer cuadro, y se asienta sin rebote.
  static const Curve curva = Cubic(0.23, 1, 0.32, 1);

  /// Hojas inferiores: cubic-bezier(0.32, 0.72, 0, 1).
  static const Curve curvaHoja = Cubic(0.32, 0.72, 0, 1);

  /// El cabezal cuando cambia de tramo y recorre la ruta: arranca y frena
  /// suave, cubic-bezier(0.77, 0, 0.175, 1). Es la única curva que no es de
  /// salida: el cabezal va de un punto a otro de la ruta, como una cámara.
  static const Curve curvaCabezal = Cubic(0.77, 0, 0.175, 1);

  // ── Presionar y soltar ──────────────────────────────────────────────────
  // Lo levantado pasa a hundido y los botones, los chips y las tarjetas que
  // se tocan se achican apenas. Con movimiento reducido, al presionar cambia
  // sólo la sombra (sin escala) y al soltar vuelve de golpe.

  /// Presionar: levantado → hundido y escala a 0,97.
  static const Duration presion = Duration(milliseconds: 120);

  /// Soltar: hundido → levantado y escala a 1.
  static const Duration soltar = Duration(milliseconds: 160);

  /// Escala de lo presionado. Nunca menos: se nota sin que parezca otro.
  static const double escalaPresion = 0.97;

  /// Cuánto dura el cambio de un relieve: presionar (120 ms, también con
  /// movimiento reducido: sólo la sombra), soltar (160 ms) o cualquier otro
  /// cambio de estado, como seleccionar o enfocar (150 ms). Con movimiento
  /// reducido, soltar y los otros cambios saltan.
  static Duration duracionRelieve(
    BuildContext context, {
    required bool presionadoAntes,
    required bool presionado,
  }) {
    if (presionado && !presionadoAntes) return presion;
    if (presionadoAntes && !presionado) return duracion(context, soltar);
    return duracion(context, seleccion);
  }

  // ── Selección ───────────────────────────────────────────────────────────

  /// Elegir un chip, una tarjeta, una pestaña o un interruptor: cambian el
  /// color y el borde (y el ícono de la pestaña pasa a relleno).
  static const Duration seleccion = Duration(milliseconds: 150);

  // ── Resorte ─────────────────────────────────────────────────────────────

  /// Resorte de la pieza del control segmentado: amortiguado justo
  /// (ζ = 40 / (2·√(400·1)) = 1), así llega sin pasarse ni rebotar.
  static const SpringDescription resorteControl = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 40,
  );

  // ── Pantallas y hojas ───────────────────────────────────────────────────

  /// Pantalla nueva: entra desde el costado (24 dp) con un fundido, sin
  /// paralaje (la de atrás no se mueve).
  static const Duration pantallaAdelante = Duration(milliseconds: 260);

  /// Volver: la de arriba se va al costado con un fundido.
  static const Duration pantallaAtras = Duration(milliseconds: 200);

  /// Cuánto se corre una pantalla al entrar o salir (dp): corto, para que no
  /// maree.
  static const double desplazamientoPantalla = 24;

  /// Hoja inferior: sube desde abajo y el fondo se oscurece.
  static const Duration hojaEntrada = Duration(milliseconds: 300);

  /// Hoja inferior: baja.
  static const Duration hojaSalida = Duration(milliseconds: 200);

  /// Con movimiento reducido, las pantallas, las hojas y la llegada aparecen
  /// y se van con un fundido de 120 ms, sin moverse.
  static const Duration fundidoReducido = Duration(milliseconds: 120);

  // ── Ruta ────────────────────────────────────────────────────────────────

  /// Constante de tiempo del cabezal con cada actualización de la posición
  /// (suavizado exponencial): a los 80 ms recorrió el 63 % de lo que faltaba,
  /// sin pasarse. Con movimiento reducido sigue el dato directo.
  static const Duration tauCabezal = Duration(milliseconds: 80);

  /// El cabezal al cambiar de tramo: recorre la ruta a lo largo de la línea.
  static const Duration cabezalTramo = Duration(milliseconds: 350);

  /// Un tramo que se completa (acento → verde) y el siguiente (violeta
  /// punteado → acento sólido).
  static const Duration tramo = Duration(milliseconds: 300);

  /// El segmento actual de la línea de tiempo se ensancha o se achica.
  static const Duration segmentoTiempo = Duration(milliseconds: 250);

  /// Al llegar: el aviso aparece con un fundido; el cabezal se queda en el
  /// destino.
  static const Duration llegada = Duration(milliseconds: 200);

  // ── Progreso (fuera de la navegación) ───────────────────────────────────

  /// Un anillo o una barra de progreso se llena al aparecer.
  static const Duration llenarProgreso = Duration(milliseconds: 400);

  /// Después, cada cambio del valor (una descarga que avanza): corto, porque
  /// puede pasar varias veces por segundo.
  static const Duration cambioProgreso = Duration(milliseconds: 120);
}
