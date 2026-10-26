import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'ajustes_navegacion.dart' show ParametroAjuste;

/// ═══════════════════════════════════════════════════════════════════════════
/// AJUSTES DE LA VOZ (app del usuario)
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Cómo le gusta a cada persona que le hable la app: velocidad, volumen, tono
/// y cada cuánto se repite una indicación que no cambió. A diferencia de los
/// ajustes de navegación (ajustes_navegacion.dart) no dependen del edificio
/// ni se calibran: son gustos.
/// Por eso se cambian en la app del usuario (pantalla_ajustes_voz.dart) y se
/// guardan sólo en su teléfono, sin nube.
///
/// Velocidad, volumen y tono van en porcentaje de cómo hablaba la app antes
/// de que se pudieran cambiar: 100 % es lo de siempre. Es más fácil de
/// entender por voz que los valores del motor (0,48 de velocidad).
///
/// Es un singleton: lo lee [VozService] al inicializarse.
class AjustesVoz {
  AjustesVoz._();
  static final AjustesVoz instancia = AjustesVoz._();

  /// Instancia aparte, sin estado compartido con [instancia]. Para tests.
  @visibleForTesting
  factory AjustesVoz.nueva() => AjustesVoz._();

  /// Velocidad del motor de voz que corresponde al 100 %.
  static const double velocidadBase = 0.48;

  final ParametroAjuste velocidad = ParametroAjuste(
    clave: 'voz_velocidad',
    nombre: 'Velocidad',
    ayuda: 'Más rápida: cada indicación termina antes.',
    unidad: '%',
    unidadHablada: 'por ciento',
    minimo: 60,
    maximo: 200,
    paso: 10,
    decimales: 0,
    porDefecto: 100,
  );

  final ParametroAjuste volumen = ParametroAjuste(
    clave: 'voz_volumen',
    nombre: 'Volumen',
    ayuda: 'Respecto del volumen del teléfono.',
    unidad: '%',
    unidadHablada: 'por ciento',
    minimo: 20,
    maximo: 100,
    paso: 10,
    decimales: 0,
    porDefecto: 100,
  );

  final ParametroAjuste tono = ParametroAjuste(
    clave: 'voz_tono',
    nombre: 'Tono',
    ayuda: 'Más: voz más aguda. Menos: más grave.',
    unidad: '%',
    unidadHablada: 'por ciento',
    minimo: 70,
    maximo: 140,
    paso: 10,
    decimales: 0,
    porDefecto: 100,
  );

  final ParametroAjuste repetir = ParametroAjuste(
    clave: 'voz_repetir_seg',
    nombre: 'Repetir la indicación cada',
    ayuda: 'Si la indicación no cambia, cada cuánto se vuelve a decir.',
    unidad: 's',
    unidadHablada: 'segundos',
    minimo: 5,
    maximo: 40,
    paso: 5,
    decimales: 0,
    porDefecto: 15,
  );

  List<ParametroAjuste> get todos => [velocidad, volumen, tono, repetir];

  // ── Valores para el motor de voz ──────────────────────────────────────────

  double get velocidadMotor => velocidadBase * velocidad.valor / 100;
  double get volumenMotor => volumen.valor / 100;
  double get tonoMotor => tono.valor / 100;
  Duration get intervaloRepeticion =>
      Duration(milliseconds: (repetir.valor * 1000).round());

  // ── Edición ───────────────────────────────────────────────────────────────

  /// Cambia [p] en memoria. Para que quede guardado, [guardar].
  void cambiar(ParametroAjuste p, double v) => p.valor = p.acotar(v);

  /// Vuelve todo al 100 % y a los 15 s de siempre, y lo guarda.
  Future<void> volverDeFabrica() {
    for (final p in todos) {
      p.valor = p.porDefecto;
    }
    return guardar();
  }

  // ── Guardado en el teléfono ───────────────────────────────────────────────

  static const String _claveGuardado = 'ajustes_voz';

  Future<void>? _carga;

  /// Lee lo guardado. Sólo la primera vez: después todo vive en memoria.
  Future<void> cargar() => _carga ??= _leer();

  Future<void> _leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_claveGuardado);
      if (texto == null) return;
      final j = jsonDecode(texto);
      if (j is! Map) return;
      for (final p in todos) {
        final x = j[p.clave];
        if (x is num && x.isFinite) p.valor = p.acotar(x.toDouble());
      }
    } catch (e) {
      debugPrint('[Voz] No se pudieron leer los ajustes de voz: $e');
    }
  }

  Future<void> guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _claveGuardado,
        jsonEncode({for (final p in todos) p.clave: p.valor}),
      );
    } catch (e) {
      debugPrint('[Voz] No se pudieron guardar los ajustes de voz: $e');
    }
  }
}
