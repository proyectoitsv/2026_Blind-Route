import 'package:blindroute/ajustes_navegacion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AJUSTES DE NAVEGACIÓN EN CAPAS: EDIFICIO → GENERAL → CÓDIGO
// ═══════════════════════════════════════════════════════════════════════════

/// Deja terminar los guardados en el teléfono, que no se esperan.
Future<void> _esperarGuardado() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AjustesNavegacion a;
  late String idEscuela;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    a = AjustesNavegacion.nueva();
    idEscuela = AjustesNavegacion.idEdificio('Escuela');
    await a.usarEdificio('Escuela');
  });

  test('sin cambios rige el valor del código', () {
    for (final p in a.todos) {
      expect(p.valor, p.porDefecto, reason: p.nombre);
      expect(a.origen(p), OrigenAjuste.codigo, reason: p.nombre);
    }
  });

  test('el general pisa al código y el edificio pisa al general', () {
    final f = a.filtroCaminando;
    a.cambiarGeneral(f, 0.7);
    expect(f.valor, 0.7);
    expect(a.origen(f), OrigenAjuste.general);

    a.cambiarEnEdificio(f, 0.9);
    expect(f.valor, 0.9);
    expect(a.origen(f), OrigenAjuste.edificio);

    a.volverAlGeneral(f);
    expect(f.valor, 0.7);
    a.volverAlCodigo(f);
    expect(f.valor, f.porDefecto);
    expect(a.origen(f), OrigenAjuste.codigo);
  });

  test('lo que depende del teléfono o de la persona no se cambia por edificio',
      () {
    final u = a.umbralCaminata;
    expect(u.porEdificio, isFalse);
    a.cambiarEnEdificio(u, 1.0);
    expect(u.valor, u.porDefecto);
    a.recibirDeNube(idEscuela, {u.clave: 1.0});
    expect(u.valor, u.porDefecto);
    // En el general sí.
    a.cambiarGeneral(u, 1.0);
    expect(u.valor, 1.0);
  });

  test('los cambios de un edificio rigen sólo en ese edificio', () async {
    final f = a.filtroCaminando;
    a.cambiarEnEdificio(f, 0.9);
    await a.usarEdificio('Otro');
    expect(f.valor, f.porDefecto);
    await a.usarEdificio(null);
    expect(f.valor, f.porDefecto);
    await a.usarEdificio('Escuela');
    expect(f.valor, 0.9);
  });

  test('cada capa guarda sólo lo que se cambió en ella', () {
    a.cambiarEnEdificio(a.filtroCaminando, 0.9);
    a.cambiarGeneral(a.anticipoGiro, 1.0);
    expect(a.valoresDe(idEscuela), {a.filtroCaminando.clave: 0.9});
    expect(a.valoresDe(AjustesNavegacion.idGeneral), {a.anticipoGiro.clave: 1.0});
  });

  test('los valores se acotan al rango y lo desconocido se ignora', () {
    final f = a.filtroCaminando;
    a.cambiarGeneral(f, 99);
    expect(f.valor, f.maximo);

    a.subidoANube(AjustesNavegacion.idGeneral,
        a.valoresDe(AjustesNavegacion.idGeneral));
    a.recibirDeNube(AjustesNavegacion.idGeneral, {
      f.clave: -5,
      'parametro_de_otra_version': 3,
      a.umbralCaminata.clave: 'no es un número',
    });
    expect(f.valor, f.minimo);
    expect(a.umbralCaminata.valor, a.umbralCaminata.porDefecto);
    expect(a.valoresDe(AjustesNavegacion.idGeneral), {f.clave: f.minimo});
  });

  test('lo que llega de la nube no pisa un cambio local sin subir', () {
    final f = a.filtroCaminando;
    a.cambiarEnEdificio(f, 0.9);
    expect(a.pendientes, {idEscuela});

    a.recibirDeNube(idEscuela, {f.clave: 0.5});
    expect(f.valor, 0.9);

    a.subidoANube(idEscuela, {f.clave: 0.9});
    expect(a.hayPendientes, isFalse);
    a.recibirDeNube(idEscuela, {f.clave: 0.5});
    expect(f.valor, 0.5);
  });

  test('si se cambió mientras se subía, sigue pendiente', () {
    final f = a.filtroCaminando;
    a.cambiarEnEdificio(f, 0.9);
    final subidos = a.valoresDe(idEscuela);
    a.cambiarEnEdificio(f, 1.0);
    a.subidoANube(idEscuela, subidos);
    expect(a.pendientes, {idEscuela});
  });

  test('una capa vacía en la nube borra lo que había en el teléfono', () {
    final f = a.filtroCaminando;
    a.recibirDeNube(idEscuela, {f.clave: 0.9});
    expect(f.valor, 0.9);
    a.recibirDeNube(idEscuela, null);
    expect(f.valor, f.porDefecto);
  });

  test('todo queda guardado en el teléfono, con lo pendiente', () async {
    a.cambiarGeneral(a.anticipoGiro, 1.0);
    a.cambiarEnEdificio(a.ventanaSenalCaminando, 1.5);
    await _esperarGuardado();

    final otra = AjustesNavegacion.nueva();
    await otra.usarEdificio('Escuela');
    expect(otra.anticipoGiro.valor, 1.0);
    expect(otra.ventanaSenalCaminando.valor, 1.5);
    expect(otra.pendientes, {AjustesNavegacion.idGeneral, idEscuela});
  });
}
