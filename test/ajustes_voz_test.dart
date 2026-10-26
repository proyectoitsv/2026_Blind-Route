import 'package:blindroute/ajustes_voz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AJUSTES DE LA VOZ
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('de fábrica, la voz es la de siempre', () async {
    final a = AjustesVoz.nueva();
    await a.cargar();
    expect(a.velocidadMotor, closeTo(0.48, 1e-9));
    expect(a.volumenMotor, 1.0);
    expect(a.tonoMotor, 1.0);
    expect(a.intervaloRepeticion, const Duration(seconds: 15));
  });

  test('los porcentajes pasan a valores del motor y se acotan', () {
    final a = AjustesVoz.nueva();
    a.cambiar(a.velocidad, 150);
    a.cambiar(a.volumen, 5); // por debajo del mínimo (20 %)
    a.cambiar(a.tono, 120);
    a.cambiar(a.repetir, 30);
    expect(a.velocidadMotor, closeTo(0.72, 1e-9));
    expect(a.volumenMotor, closeTo(0.2, 1e-9));
    expect(a.tonoMotor, closeTo(1.2, 1e-9));
    expect(a.intervaloRepeticion, const Duration(seconds: 30));
  });

  test('lo guardado se lee de nuevo, y "de fábrica" lo deshace', () async {
    final a = AjustesVoz.nueva();
    await a.cargar();
    a.cambiar(a.velocidad, 180);
    await a.guardar();

    final b = AjustesVoz.nueva();
    await b.cargar();
    expect(b.velocidad.valor, 180);

    await b.volverDeFabrica();
    final c = AjustesVoz.nueva();
    await c.cargar();
    expect(c.velocidad.valor, 100);
  });
}
