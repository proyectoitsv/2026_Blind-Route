import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Movimiento de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Duraciones y curvas. Los aplica la fase 3 (transiciones, números que
// cuentan, anillos que se llenan) respetando "Quitar animaciones" del
// teléfono (MediaQuery.disableAnimationsOf) y el interruptor propio de
// Ajustes: con cualquiera de los dos, las transiciones son instantáneas o un
// fundido mínimo. Nada de esto corre en la navegación en vivo, donde
// importan la legibilidad y la voz.
abstract final class MovimientoApp {
  // ── Movimiento reducido ─────────────────────────────────────────────────

  /// Si hay que evitar las animaciones: "Quitar animaciones" del teléfono
  /// (MediaQuery.disableAnimations). La fase 3 le suma el interruptor propio
  /// de Ajustes; los componentes preguntan sólo acá, así no hay que tocarlos
  /// de nuevo. Con movimiento reducido, los controles saltan al estado nuevo
  /// sin resorte.
  static bool reducido(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  // ── Respuesta al toque (fase 2) ─────────────────────────────────────────
  // Al presionar, lo levantado pasa a hundido (de golpe hasta la fase 3, que
  // anima el paso) y los botones se achican apenas: es la respuesta que se
  // siente bajo el dedo. Curva de salida fuerte: arranca rápido, así
  // responde en el primer cuadro, y se asienta sin rebote. Con movimiento
  // reducido no escalan: queda sólo el cambio de relieve.

  /// Cuánto dura el achique al presionar un botón, y la vuelta al soltar.
  static const Duration presion = Duration(milliseconds: 120);

  /// Curva del achique: cubic-bezier(0.23, 1, 0.32, 1). Más fuerte que
  /// Curves.easeOutCubic, que se siente tarde.
  static const Curve curvaPresion = Cubic(0.23, 1, 0.32, 1);

  /// Escala de un botón presionado. Nunca menos: se nota sin que el botón
  /// parezca otro.
  static const double escalaPresion = 0.97;

  // ── Duraciones ──────────────────────────────────────────────────────────

  /// Cambio de estado de un control: presionar, seleccionar, prender.
  static const Duration corta = Duration(milliseconds: 150);

  /// Cambio de pantalla y de pestaña.
  static const Duration media = Duration(milliseconds: 250);

  /// Hojas inferiores y elementos grandes que entran o salen.
  static const Duration larga = Duration(milliseconds: 350);

  /// Números que cuentan al aparecer y anillos que se llenan.
  static const Duration conteo = Duration(milliseconds: 700);

  /// Con movimiento reducido: un fundido apenas visible en lugar de la
  /// transición.
  static const Duration fundidoMinimo = Duration(milliseconds: 100);

  // ── Curvas ──────────────────────────────────────────────────────────────

  /// Lo que aparece o llega: arranca rápido y se asienta suave.
  static const Curve entrada = Curves.easeOutCubic;

  /// Lo que se va: arranca suave y sale rápido.
  static const Curve salida = Curves.easeInCubic;

  /// De un estado a otro sin entrar ni salir.
  static const Curve estandar = Curves.easeInOutCubic;

  /// Números que cuentan y anillos que se llenan: casi todo el recorrido al
  /// principio, así el valor final se lee enseguida.
  static const Curve curvaConteo = Curves.easeOutQuart;

  // ── Resorte ─────────────────────────────────────────────────────────────

  /// Resorte de la pieza del control segmentado, el de la tabla del prompt
  /// (sección 5.2): amortiguado justo (ζ = 40 / (2·√(400·1)) = 1), así llega
  /// sin pasarse ni rebotar. El de la v4 rebotaba (ζ ≈ 0,85).
  static const SpringDescription resorteControl = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 40,
  );

  // ── Transiciones ────────────────────────────────────────────────────────

  /// Escala de la pestaña que entra, en el fundido del cambio de pestaña.
  static const double escalaCambioPestana = 0.985;

  /// Recorrido (dp) del deslizamiento horizontal con fundido entre
  /// pantallas: corto, para que no maree.
  static const double desplazamientoPantalla = 30;
}
