import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ajustes_movimiento.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Vibración
// ═══════════════════════════════════════════════════════════════════════════
//
// Las vibraciones de la app pasan por acá, así el interruptor «Vibración» de
// Ajustes (AjustesMovimiento) las apaga todas. Ninguna al presionar un botón:
// en la navegación se volvería ruido.
//
// La tabla de movimiento (sección 5.4 de la v5) pide una suave al cambiar de
// tramo (cambioDeTramo) y una media al llegar (llegada). La navegación en
// vivo (pantalla_naveg.dart) sigue con las fuerzas de antes: media al decir
// «Girá…» y al empezar a orientarse al llegar; fuerte en «Llegaste», en la
// escalera y al cambiar de piso. Decidido en la fase 5.7: una vibración suave
// se puede perder caminando; se cambian recién si, probándolas, conviene.
//
// En Android son las vibraciones cortas del sistema (las de
// View.performHapticFeedback): si la vibración al tocar está apagada en el
// teléfono, puede que no vibre.
abstract final class HapticaApp {
  /// Al cambiar de tramo: suave.
  static Future<void> cambioDeTramo() => suave();

  /// Al llegar: media.
  static Future<void> llegada() => media();

  /// Vibración suave (HapticFeedback.lightImpact).
  static Future<void> suave() => _vibrar(HapticFeedback.lightImpact);

  /// Vibración media (HapticFeedback.mediumImpact).
  static Future<void> media() => _vibrar(HapticFeedback.mediumImpact);

  /// Vibración fuerte (HapticFeedback.heavyImpact).
  static Future<void> fuerte() => _vibrar(HapticFeedback.heavyImpact);

  /// Vibra si el interruptor está prendido. La primera vez espera a leer lo
  /// guardado (milisegundos). Nunca falla: una vibración que no sale no
  /// puede cortar la navegación.
  static Future<void> _vibrar(Future<void> Function() vibracion) async {
    try {
      final ajustes = AjustesMovimiento.instancia;
      if (!ajustes.cargado) await ajustes.cargar();
      if (!ajustes.vibracion) return;
      await vibracion();
    } catch (e) {
      debugPrint('[Vibración] No se pudo vibrar: $e');
    }
  }
}
