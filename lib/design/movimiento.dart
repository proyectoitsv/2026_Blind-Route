import 'package:flutter/animation.dart';

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

  /// Resorte corto para controles, como la pieza del control segmentado:
  /// 0,3 s con un rebote apenas perceptible. Es el mismo modelo que
  /// spring(duration:bounce:) de SwiftUI.
  static final SpringDescription resorteControl =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 300),
        bounce: 0.15,
      );

  // ── Transiciones ────────────────────────────────────────────────────────

  /// Escala de la pestaña que entra, en el fundido del cambio de pestaña.
  static const double escalaCambioPestana = 0.985;

  /// Recorrido (dp) del deslizamiento horizontal con fundido entre
  /// pantallas: corto, para que no maree.
  static const double desplazamientoPantalla = 30;
}
