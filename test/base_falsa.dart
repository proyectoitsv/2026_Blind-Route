import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LA BASE DE PRUEBA
// ═══════════════════════════════════════════════════════════════════════════
//
// La base del teléfono (DatabaseHelper, con sqflite) en memoria, para los
// tests de las pantallas que la leen y la escriben (las listas de edificios y
// de pisos del administrador).
//
// sqflite le habla a Android por un canal (com.tekartik.sqflite). Acá lo
// atiende el test, con las tablas en memoria y lo justo de SQL para lo que
// arma sqflite con los pedidos de DatabaseHelper que usan esas pantallas:
// SELECT (con WHERE, ORDER BY y LIMIT), INSERT, UPDATE y DELETE, con
// condiciones "col = ?", "col IS [NOT] NULL" y "col IN (SELECT …)" unidas
// por AND. Un SQL que no entiende lo rechaza con un error que lo nombra: así
// un pedido nuevo no pasa en silencio.
//
// La versión del esquema se contesta 17, la de DatabaseHelper: así sqflite
// no crea las tablas (acá no hace falta) ni migra nada.
//
// Sin paquetes nuevos (sqflite_common_ffi no es una dependencia) ni imports
// internos de sqflite: databaseFactory y databaseFactorySqflitePlugin los
// exporta package:sqflite.
//
// No termina en _test.dart: flutter test no lo corre solo.

/// La base de prueba, una para todo el archivo de tests.
final BaseFalsa baseFalsa = BaseFalsa();

/// Pone la base de prueba en lugar de la del teléfono. Va en el setUpAll:
/// DatabaseHelper abre la base una sola vez por archivo y la guarda.
void iniciarBaseDePrueba() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.tekartik.sqflite'),
        baseFalsa._atender,
      );
}

/// Las tablas de la base de prueba, en memoria.
class BaseFalsa {
  /// Las filas de cada tabla.
  final Map<String, List<Map<String, Object?>>> tablas = {};

  /// Los pedidos que llegaron, con el SQL sin espacios de más
  /// ("DELETE FROM pisos WHERE id = ?").
  final List<String> pedidos = [];

  /// Lo que la base pone en una fila nueva si no se lo dan, como los DEFAULT
  /// de las tablas de DatabaseHelper.
  static const Map<String, Map<String, Object?>> _porDefecto = {
    'pisos': {
      'numero_piso': null,
      'escala_metros': 50.0,
      'escala_metros_alto': 50.0,
      'tam_celda_metros': 1.0,
      'rotacion_mapa': 0.0,
      'remote_id': null,
    },
  };

  /// Vacía todas las tablas, para el test siguiente.
  void reiniciar() {
    tablas.clear();
    pedidos.clear();
  }

  /// Las filas de [tabla].
  List<Map<String, Object?>> filas(String tabla) => tablas[tabla] ?? const [];

  /// Agrega una fila a [tabla], con los valores por defecto y un id nuevo
  /// (si no lo trae). Devuelve el id.
  int agregar(String tabla, Map<String, Object?> fila) {
    final filas = tablas.putIfAbsent(tabla, () => []);
    final id =
        fila['id'] as int? ??
        filas.fold<int>(0, (mayor, f) {
              final otro = f['id'] as int? ?? 0;
              return otro > mayor ? otro : mayor;
            }) +
            1;
    filas.add({'id': id, ...?_porDefecto[tabla], ...fila});
    return id;
  }

  Future<Object?> _atender(MethodCall llamada) async {
    final argumentos = llamada.arguments is Map
        ? Map<String, Object?>.from(llamada.arguments as Map)
        : const <String, Object?>{};
    final sql = argumentos['sql'] == null
        ? null
        : (argumentos['sql']! as String).replaceAll(RegExp(r'\s+'), ' ').trim();
    final valores = _Valores(
      (argumentos['arguments'] as List<Object?>?) ?? const [],
    );
    if (sql != null) pedidos.add(sql);
    switch (llamada.method) {
      case 'getDatabasesPath':
        return '/base-de-prueba';
      case 'openDatabase':
        return {'id': 1};
      case 'databaseExists':
        return true;
      case 'execute':
        // PRAGMA foreign_keys, BEGIN, COMMIT y ROLLBACK: nada que hacer.
        return null;
      case 'query':
        return _consultar(sql!, valores);
      case 'insert':
        return _insertar(sql!, valores);
      case 'update':
        // sqflite manda los UPDATE y los DELETE por acá.
        return sql!.startsWith('DELETE')
            ? _borrar(sql, valores)
            : _cambiar(sql, valores);
      default:
        return null;
    }
  }

  // ─── SQL ──────────────────────────────────────────────────────────────────

  Map<String, Object?> _consultar(String sql, _Valores valores) {
    if (sql == 'PRAGMA user_version') {
      return _resultado([
        {'user_version': 17},
      ]);
    }
    final partes = RegExp(
      r'^SELECT (.+?) FROM (\w+)(?: WHERE (.+?))?(?: ORDER BY (.+?))?'
      r'(?: LIMIT (\d+))?$',
    ).firstMatch(sql);
    if (partes == null) _noEntiende(sql);
    var elegidas = _filtrar(partes[2]!, partes[3], valores);
    if (partes[4] != null) _ordenar(elegidas, partes[4]!);
    if (partes[5] != null) {
      elegidas = elegidas.take(int.parse(partes[5]!)).toList();
    }
    final columnas = partes[1]!;
    if (columnas != '*') {
      final nombres = columnas.split(', ');
      elegidas = [
        for (final fila in elegidas) {for (final c in nombres) c: fila[c]},
      ];
    }
    return _resultado(elegidas);
  }

  int _insertar(String sql, _Valores valores) {
    final partes = RegExp(
      r'^INSERT INTO (\w+) \((.+)\) VALUES \((.+)\)$',
    ).firstMatch(sql);
    if (partes == null) _noEntiende(sql);
    final columnas = partes[2]!.split(', ');
    return agregar(partes[1]!, {
      for (final c in columnas) c: valores.siguiente(),
    });
  }

  int _cambiar(String sql, _Valores valores) {
    final partes = RegExp(
      r'^UPDATE (\w+) SET (.+?) WHERE (.+)$',
    ).firstMatch(sql);
    if (partes == null) _noEntiende(sql);
    // Los "?" del SET van antes que los del WHERE.
    final cambios = <String, Object?>{};
    for (final asignacion in partes[2]!.split(', ')) {
      final columna = RegExp(r'^(\w+) = \?$').firstMatch(asignacion)?[1];
      if (columna == null) _noEntiende(sql);
      cambios[columna] = valores.siguiente();
    }
    final elegidas = _filtrar(partes[1]!, partes[3], valores);
    for (final fila in elegidas) {
      fila.addAll(cambios);
    }
    return elegidas.length;
  }

  int _borrar(String sql, _Valores valores) {
    final partes = RegExp(
      r'^DELETE FROM (\w+)(?: WHERE (.+))?$',
    ).firstMatch(sql);
    if (partes == null) _noEntiende(sql);
    final elegidas = _filtrar(partes[1]!, partes[2], valores);
    tablas[partes[1]!]?.removeWhere(elegidas.contains);
    return elegidas.length;
  }

  /// Las filas de [tabla] que cumplen [donde] (todas, sin WHERE). Los "?"
  /// se toman de [valores] en el orden en que aparecen.
  List<Map<String, Object?>> _filtrar(
    String tabla,
    String? donde,
    _Valores valores,
  ) {
    final filas = this.filas(tabla);
    if (donde == null) return [...filas];
    final condiciones = [
      for (final condicion in donde.split(' AND '))
        _condicion(condicion, valores),
    ];
    return [
      for (final fila in filas)
        if (condiciones.every((cumple) => cumple(fila))) fila,
    ];
  }

  bool Function(Map<String, Object?>) _condicion(
    String condicion,
    _Valores valores,
  ) {
    final igual = RegExp(r'^(\w+) = \?$').firstMatch(condicion);
    if (igual != null) {
      final valor = valores.siguiente();
      return (fila) => fila[igual[1]!] == valor;
    }
    final nulo = RegExp(r'^(\w+) IS (NOT )?NULL$').firstMatch(condicion);
    if (nulo != null) {
      final esNulo = nulo[2] == null;
      return (fila) => (fila[nulo[1]!] == null) == esNulo;
    }
    final dentro = RegExp(
      r'^(\w+) IN \(SELECT (\w+) FROM (\w+) WHERE (.+)\)$',
    ).firstMatch(condicion);
    if (dentro != null) {
      final permitidos = {
        for (final fila in _filtrar(dentro[3]!, dentro[4], valores))
          fila[dentro[2]!],
      };
      return (fila) => permitidos.contains(fila[dentro[1]!]);
    }
    _noEntiende(condicion);
  }

  /// Ordena [filas] según [orden] ("numero_piso IS NULL, numero_piso ASC").
  /// Como SQLite: lo nulo va primero en ASC.
  void _ordenar(List<Map<String, Object?>> filas, String orden) {
    final terminos = <int Function(Map<String, Object?>, Map<String, Object?>)>[
      for (final termino in orden.split(', '))
        if (RegExp(r'^(\w+) IS NULL$').firstMatch(termino) case final nulo?)
          (a, b) =>
              (a[nulo[1]!] == null ? 1 : 0) - (b[nulo[1]!] == null ? 1 : 0)
        else if (RegExp(r'^(\w+)(?: (ASC|DESC))?$').firstMatch(termino)
            case final columna?)
          (a, b) =>
              _comparar(a[columna[1]!], b[columna[1]!]) *
              (columna[2] == 'DESC' ? -1 : 1)
        else
          (a, b) => _noEntiende(orden),
    ];
    filas.sort((a, b) {
      for (final termino in terminos) {
        final c = termino(a, b);
        if (c != 0) return c;
      }
      return 0;
    });
  }

  static int _comparar(Object? a, Object? b) {
    if (a == null || b == null) {
      return (a == null ? 0 : 1) - (b == null ? 0 : 1);
    }
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  /// Como contesta sqflite una consulta: las columnas y los valores.
  static Map<String, Object?> _resultado(List<Map<String, Object?>> filas) {
    final columnas = filas.isEmpty ? <String>[] : filas.first.keys.toList();
    return {
      'columns': columnas,
      'rows': [
        for (final fila in filas) [for (final c in columnas) fila[c]],
      ],
    };
  }

  static Never _noEntiende(String sql) =>
      throw UnsupportedError('La base de prueba no entiende este SQL: $sql');
}

/// Los valores de los "?" de un pedido, en orden.
class _Valores {
  _Valores(this._valores);

  final List<Object?> _valores;
  int _siguiente = 0;

  Object? siguiente() => _valores[_siguiente++];
}
