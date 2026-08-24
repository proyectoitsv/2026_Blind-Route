import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'calibracion_model.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('blindroute.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 10, // v10: rumbo_captura en calibraciones (fingerprint direccional)
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE edificios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pisos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        edificio_id INTEGER NOT NULL,
        nombre_piso TEXT NOT NULL,
        ruta_imagen TEXT NOT NULL,
        escala_metros REAL NOT NULL DEFAULT 50,
        escala_metros_alto REAL NOT NULL DEFAULT 50,
        tam_celda_metros REAL NOT NULL DEFAULT 1.0,
        rotacion_mapa REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (edificio_id) REFERENCES edificios (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE beacons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        piso_id INTEGER NOT NULL,
        mac TEXT NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL,
        nombre_beacon TEXT NOT NULL,
        FOREIGN KEY (piso_id) REFERENCES pisos (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE zonas_no_transitables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        piso_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        vertices_json TEXT NOT NULL,
        FOREIGN KEY (piso_id) REFERENCES pisos (id) ON DELETE CASCADE
      )
    ''');

    // --- NUEVA TABLA: Lugares de Interés (POI) ---
    await db.execute('''
      CREATE TABLE lugares_interes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        piso_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL,
        descripcion TEXT,
        FOREIGN KEY (piso_id) REFERENCES pisos (id) ON DELETE CASCADE
      )
    ''');

    // --- Calibraciones por celda (modo calibración) ---
    await db.execute(_sqlCrearCalibraciones);
  }

  /// DDL de la tabla de calibraciones. Compartido entre _createDB (instalaciones
  /// nuevas) y _onUpgrade (instalaciones existentes) para no duplicar el esquema.
  static const String _sqlCrearCalibraciones = '''
    CREATE TABLE IF NOT EXISTS calibraciones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      piso_id INTEGER NOT NULL,
      celda_ix INTEGER NOT NULL,
      celda_iy INTEGER NOT NULL,
      lecturas_ble TEXT NOT NULL,
      tx_power_ajustado TEXT NOT NULL DEFAULT '{}',
      timestamp TEXT NOT NULL,
      etiqueta TEXT,
      es_fingerprint INTEGER NOT NULL DEFAULT 0,
      rumbo_captura REAL,
      FOREIGN KEY (piso_id) REFERENCES pisos (id) ON DELETE CASCADE
    )
  ''';

  // Migración para usuarios existentes
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS zonas_no_transitables (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          piso_id INTEGER NOT NULL,
          nombre TEXT NOT NULL,
          vertices_json TEXT NOT NULL,
          FOREIGN KEY (piso_id) REFERENCES pisos (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS lugares_interes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          piso_id INTEGER NOT NULL,
          nombre TEXT NOT NULL,
          x REAL NOT NULL,
          y REAL NOT NULL,
          descripcion TEXT,
          FOREIGN KEY (piso_id) REFERENCES pisos (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE pisos ADD COLUMN escala_metros REAL NOT NULL DEFAULT 50',
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE pisos ADD COLUMN escala_metros_alto REAL NOT NULL DEFAULT 50',
      );
    }
    if (oldVersion < 6) {
      // SQLite no soporta "ADD COLUMN IF NOT EXISTS"; el guard por versión
      // garantiza que este ALTER corra una sola vez por upgrade.
      await db.execute(
        'ALTER TABLE pisos ADD COLUMN tam_celda_metros REAL NOT NULL DEFAULT 1.0',
      );
    }
    if (oldVersion < 7) {
      await db.execute(_sqlCrearCalibraciones);
    }
    if (oldVersion < 8) {
      // v8: offset de brújula por piso. Permite calibrar la rotación del mapa
      // directamente desde la pantalla de configuración.
      await db.execute(
        'ALTER TABLE pisos ADD COLUMN rotacion_mapa REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 9) {
      // v9: marca de PUNTO CLAVE (fingerprint) en las calibraciones.
      //
      // Ojo con el orden respecto de la v7: una instalacion que venga de una
      // version < 7 ya creo la tabla con el DDL de _sqlCrearCalibraciones, que
      // arriba YA incluye es_fingerprint. En ese caso este ALTER fallaria por
      // columna duplicada, asi que se consulta el esquema antes de tocar nada.
      final cols = await db.rawQuery('PRAGMA table_info(calibraciones)');
      final tieneColumna =
          cols.any((c) => (c['name'] as String?) == 'es_fingerprint');
      if (!tieneColumna) {
        await db.execute(
          'ALTER TABLE calibraciones ADD COLUMN es_fingerprint '
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 10) {
      // v10: rumbo de la brujula al capturar el fingerprint. Mismo cuidado que
      // en la v9: si la tabla se creo recien con el DDL nuevo, la columna ya
      // existe y el ALTER fallaria.
      final cols = await db.rawQuery('PRAGMA table_info(calibraciones)');
      final tieneRumbo =
          cols.any((c) => (c['name'] as String?) == 'rumbo_captura');
      if (!tieneRumbo) {
        // Sin NOT NULL: null significa "se tomo sin brujula", que es
        // exactamente el estado de todos los fingerprints ya guardados.
        await db.execute(
          'ALTER TABLE calibraciones ADD COLUMN rumbo_captura REAL',
        );
      }
    }
  }

  // --- Edificios ---
  Future<int> crearEdificio(String nombre) async {
    final db = await instance.database;
    return await db.insert('edificios', {'nombre': nombre});
  }

  Future<List<Map<String, dynamic>>> obtenerEdificios() async {
    final db = await instance.database;
    return await db.query('edificios');
  }

  // --- Pisos ---
  Future<int> crearPiso(int edificioId, String nombrePiso, String rutaImagen) async {
    final db = await instance.database;
    return await db.insert('pisos', {
      'edificio_id': edificioId,
      'nombre_piso': nombrePiso,
      'ruta_imagen': rutaImagen,
    });
  }

  Future<List<Map<String, dynamic>>> obtenerPisosPorEdificio(int edificioId) async {
    final db = await instance.database;
    return await db.query('pisos', where: 'edificio_id = ?', whereArgs: [edificioId]);
  }

  /// Actualiza la escala de un piso: metros que representa el plano en X
  /// ([escalaX]) y en Y ([escalaY]).
  Future<void> actualizarEscalaPiso(int pisoId, double escalaX, double escalaY) async {
    final db = await instance.database;
    await db.update(
      'pisos',
      {'escala_metros': escalaX, 'escala_metros_alto': escalaY},
      where: 'id = ?',
      whereArgs: [pisoId],
    );
  }

  /// Persiste el lado de celda de la grilla (m) del piso. Rango válido 0.5–1.0.
  Future<void> actualizarTamCeldaPiso(int pisoId, double tamCelda) async {
    final db = await instance.database;
    await db.update(
      'pisos',
      {'tam_celda_metros': tamCelda},
      where: 'id = ?',
      whereArgs: [pisoId],
    );
  }

  /// Persiste la rotación del mapa (grados) del piso.
  /// 0 = Norte arriba, 90 = Este arriba, 180 = Sur arriba, 270 = Oeste arriba.
  Future<void> actualizarRotacionMapa(int pisoId, double rotacion) async {
    final db = await instance.database;
    await db.update(
      'pisos',
      {'rotacion_mapa': rotacion},
      where: 'id = ?',
      whereArgs: [pisoId],
    );
  }

  // --- Beacons ---
  Future<void> guardarBeacons(int pisoId, List<BeaconMarcado> beacons) async {
    final db = await instance.database;
    await db.delete('beacons', where: 'piso_id = ?', whereArgs: [pisoId]);
    for (var b in beacons) {
      await db.insert('beacons', {
        'piso_id': pisoId,
        'mac': b.mac,
        'x': b.posicion.dx,
        'y': b.posicion.dy,
        'nombre_beacon': b.nombre,
      });
    }
  }

  Future<List<BeaconMarcado>> obtenerBeaconsPorPiso(int pisoId) async {
    final db = await instance.database;
    final res = await db.query('beacons', where: 'piso_id = ?', whereArgs: [pisoId]);
    return res.map((json) => BeaconMarcado(
      posicion: Offset(json['x'] as double, json['y'] as double),
      nombre: json['nombre_beacon'] as String,
      mac: json['mac'] as String,
    )).toList();
  }

  Future<Map<String, dynamic>?> obtenerInfoPorBeacon(String mac) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT pisos.id, pisos.ruta_imagen, pisos.escala_metros, pisos.escala_metros_alto,
             pisos.tam_celda_metros, pisos.rotacion_mapa,
             edificios.nombre as edificio_nombre, pisos.nombre_piso
      FROM beacons
      INNER JOIN pisos ON beacons.piso_id = pisos.id
      INNER JOIN edificios ON pisos.edificio_id = edificios.id
      WHERE beacons.mac = ?
      LIMIT 1
    ''', [mac]);
    if (result.isNotEmpty) return result.first;
    return null;
  }

  // --- Zonas no transitables ---

  Future<int> crearZona(ZonaNoTransitable zona) async {
    final db = await instance.database;
    final verticesJson = jsonEncode(
      zona.vertices.map((v) => {'dx': v.dx, 'dy': v.dy}).toList(),
    );
    return await db.insert('zonas_no_transitables', {
      'piso_id': zona.pisoId,
      'nombre': zona.nombre,
      'vertices_json': verticesJson,
    });
  }

  Future<List<ZonaNoTransitable>> obtenerZonasPorPiso(int pisoId) async {
    final db = await instance.database;
    final res = await db.query(
      'zonas_no_transitables',
      where: 'piso_id = ?',
      whereArgs: [pisoId],
    );
    return res.map((row) {
      final List<dynamic> raw = jsonDecode(row['vertices_json'] as String);
      final vertices = raw.map((v) => Offset(v['dx'] as double, v['dy'] as double)).toList();
      return ZonaNoTransitable(
        id: row['id'] as int,
        pisoId: pisoId,
        nombre: row['nombre'] as String,
        vertices: vertices,
      );
    }).toList();
  }

  Future<void> eliminarZona(int zonaId) async {
    final db = await instance.database;
    await db.delete('zonas_no_transitables', where: 'id = ?', whereArgs: [zonaId]);
  }

  // --- LUGARES DE INTERÉS (POI) ---

  Future<int> crearLugarInteres(LugarInteres lugar) async {
    final db = await instance.database;
    return await db.insert('lugares_interes', {
      'piso_id': lugar.pisoId,
      'nombre': lugar.nombre,
      'x': lugar.posicion.dx,
      'y': lugar.posicion.dy,
      'descripcion': lugar.descripcion,
    });
  }

  Future<List<LugarInteres>> obtenerLugaresPorPiso(int pisoId) async {
    final db = await instance.database;
    final res = await db.query(
      'lugares_interes',
      where: 'piso_id = ?',
      whereArgs: [pisoId],
    );
    return res.map((row) => LugarInteres(
      id: row['id'] as int,
      pisoId: pisoId,
      nombre: row['nombre'] as String,
      posicion: Offset(row['x'] as double, row['y'] as double),
      descripcion: row['descripcion'] as String?,
    )).toList();
  }

  Future<void> eliminarLugarInteres(int id) async {
    final db = await instance.database;
    await db.delete('lugares_interes', where: 'id = ?', whereArgs: [id]);
  }

  // --- CALIBRACIONES (modo calibración) ---

  Future<void> guardarCalibracion(CalibracionRegistro c) async {
    final db = await instance.database;
    await db.insert('calibraciones', c.toJson());
  }

  /// Borra las calibraciones duplicadas de un piso y devuelve cuantas elimino.
  ///
  /// Se consideran duplicadas las filas con la MISMA celda y las MISMAS
  /// lecturas BLE (el JSON identico), que es la firma de la reentrada del
  /// callback de scan: varias inserciones del mismo `_acumCal`. De cada grupo
  /// se conserva la de menor id. Dos calibraciones reales de la misma celda
  /// tomadas en momentos distintos jamas dan el JSON identico al dBm.
  Future<int> eliminarCalibracionesDuplicadas(int pisoId) async {
    final db = await instance.database;
    return await db.rawDelete('''
      DELETE FROM calibraciones
      WHERE piso_id = ?
        AND id NOT IN (
          SELECT MIN(id) FROM calibraciones
          WHERE piso_id = ?
          GROUP BY celda_ix, celda_iy, lecturas_ble, es_fingerprint
        )
    ''', [pisoId, pisoId]);
  }

  Future<List<CalibracionRegistro>> obtenerCalibracionesPorPiso(int pisoId) async {
    final db = await instance.database;
    final res = await db.query(
      'calibraciones',
      where: 'piso_id = ?',
      whereArgs: [pisoId],
      orderBy: 'timestamp DESC',
    );
    return res.map((row) => CalibracionRegistro.fromJson(row)).toList();
  }

  Future<void> eliminarCalibracion(int id) async {
    final db = await instance.database;
    await db.delete('calibraciones', where: 'id = ?', whereArgs: [id]);
  }

  // --- Borrado en cascada ---
  Future<void> eliminarEdificioCompleto(int edificioId) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.rawDelete('''
        DELETE FROM beacons 
        WHERE piso_id IN (SELECT id FROM pisos WHERE edificio_id = ?)
      ''', [edificioId]);
      await txn.rawDelete('''
        DELETE FROM zonas_no_transitables 
        WHERE piso_id IN (SELECT id FROM pisos WHERE edificio_id = ?)
      ''', [edificioId]);
      await txn.rawDelete('''
        DELETE FROM lugares_interes
        WHERE piso_id IN (SELECT id FROM pisos WHERE edificio_id = ?)
      ''', [edificioId]);
      await txn.rawDelete('''
        DELETE FROM calibraciones
        WHERE piso_id IN (SELECT id FROM pisos WHERE edificio_id = ?)
      ''', [edificioId]);
      await txn.delete('pisos', where: 'edificio_id = ?', whereArgs: [edificioId]);
      await txn.delete('edificios', where: 'id = ?', whereArgs: [edificioId]);
    });
  }

  Future<int> eliminarPiso(int id) async {
    final db = await instance.database;
    await db.delete('beacons', where: 'piso_id = ?', whereArgs: [id]);
    await db.delete('zonas_no_transitables', where: 'piso_id = ?', whereArgs: [id]);
    await db.delete('lugares_interes', where: 'piso_id = ?', whereArgs: [id]);
    await db.delete('calibraciones', where: 'piso_id = ?', whereArgs: [id]);
    return await db.delete('pisos', where: 'id = ?', whereArgs: [id]);
  }
}