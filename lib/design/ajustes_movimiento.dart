import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ajustes de movimiento y vibración
// ═══════════════════════════════════════════════════════════════════════════
//
// Dos gustos de cada persona, que se cambian en Ajustes (pantalla_ajustes.dart,
// en la app del usuario) y se guardan sólo en su teléfono, sin nube, como los
// de la voz:
//   · Reducir movimiento: las animaciones pasan a la columna de la derecha de
//     la tabla de movimiento (movimiento.dart): sin deslizamientos, escalas ni
//     resortes; a lo sumo un fundido corto. Se suma a «Quitar animaciones»
//     del teléfono: con cualquiera de los dos, el movimiento está reducido.
//   · Vibración: las vibraciones de la navegación (HapticaApp). Prendida de
//     fábrica.
//
// ─── Cómo llega a los componentes ───
// Los componentes preguntan sólo MovimientoApp.reducido(context). Las
// pantallas migradas, la galería y las hojas van envueltas en AmbienteDiseno,
// que suma este ajuste al MediaQuery (disableAnimations): así el cambio rige
// al instante. MovimientoApp.reducido también lo lee directo, para lo que
// todavía no está envuelto (el mapa de la navegación); las transiciones de
// pantalla y la vibración, que no tienen un contexto a mano, lo leen directo
// siempre.
//
// Es un singleton y avisa cuando cambia (ChangeNotifier). Lee lo guardado la
// primera vez que alguien pregunta: hasta entonces valen los de fábrica (la
// lectura tarda milisegundos).
class AjustesMovimiento extends ChangeNotifier {
  AjustesMovimiento._();

  static final AjustesMovimiento instancia = AjustesMovimiento._();

  /// Instancia aparte, sin estado compartido con [instancia]. Para tests.
  @visibleForTesting
  factory AjustesMovimiento.nueva() => AjustesMovimiento._();

  bool _reducirMovimiento = false;
  bool _vibracion = true;

  /// Si la persona pidió menos movimiento en la app (además de lo que diga
  /// el teléfono).
  bool get reducirMovimiento {
    _cargarSiHaceFalta();
    return _reducirMovimiento;
  }

  /// Si la app vibra (en la navegación).
  bool get vibracion {
    _cargarSiHaceFalta();
    return _vibracion;
  }

  // ── Cambios ───────────────────────────────────────────────────────────────

  /// Prende o apaga «Reducir movimiento» y lo guarda.
  Future<void> cambiarReducirMovimiento(bool valor) async {
    await cargar();
    if (valor == _reducirMovimiento) return;
    _reducirMovimiento = valor;
    notifyListeners();
    await _guardar();
  }

  /// Prende o apaga la vibración y lo guarda.
  Future<void> cambiarVibracion(bool valor) async {
    await cargar();
    if (valor == _vibracion) return;
    _vibracion = valor;
    notifyListeners();
    await _guardar();
  }

  // ── Guardado en el teléfono ───────────────────────────────────────────────

  static const String _claveGuardado = 'ajustes_movimiento';
  static const String _claveReducir = 'reducir_movimiento';
  static const String _claveVibracion = 'vibracion';

  Future<void>? _carga;
  bool _cargado = false;

  /// Si ya se leyó lo guardado (o se intentó).
  bool get cargado => _cargado;

  /// Lee lo guardado. Sólo la primera vez: después todo vive en memoria.
  Future<void> cargar() => _carga ??= _leer();

  void _cargarSiHaceFalta() {
    if (_carga == null) cargar();
  }

  Future<void> _leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_claveGuardado);
      if (texto == null) return;
      final j = jsonDecode(texto);
      if (j is! Map) return;
      final reducir = j[_claveReducir];
      final vibrar = j[_claveVibracion];
      var cambio = false;
      if (reducir is bool && reducir != _reducirMovimiento) {
        _reducirMovimiento = reducir;
        cambio = true;
      }
      if (vibrar is bool && vibrar != _vibracion) {
        _vibracion = vibrar;
        cambio = true;
      }
      if (cambio) notifyListeners();
    } catch (e) {
      debugPrint('[Movimiento] No se pudieron leer los ajustes: $e');
    } finally {
      _cargado = true;
    }
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _claveGuardado,
        jsonEncode({
          _claveReducir: _reducirMovimiento,
          _claveVibracion: _vibracion,
        }),
      );
    } catch (e) {
      debugPrint('[Movimiento] No se pudieron guardar los ajustes: $e');
    }
  }

  /// Vuelve a los de fábrica, sin leer ni guardar: cada test arranca igual.
  @visibleForTesting
  void reiniciarParaTests() {
    _reducirMovimiento = false;
    _vibracion = true;
    _carga = null;
    _cargado = false;
  }
}
