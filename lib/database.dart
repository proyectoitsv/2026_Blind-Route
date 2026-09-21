import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'calibracion_model.dart';
import 'piso_util.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';

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
      version: 13, // v13: pisos.numero_piso + escaleras en lugares_interes
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
        numero_piso INTEGER,
        ruta_imagen TEXT NOT NULL,
        escala_metros REAL NOT NULL DEFAULT 50,
        escala_metros_alto REAL NOT NULL DEFAULT 50,
        tam_celda_metros REAL NOT NULL DEFAULT 1.0,
        rotacion_mapa REAL NOT NULL DEFAULT 0,
        remote_id TEXT,
        remote_actualizado TEXT,
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
        tipo TEXT NOT NULL DEFAULT 'comun',
        sube INTEGER NOT NULL DEFAULT 0,
        baja INTEGER NOT NULL DEFAULT 0,
        direccion_entrada REAL,
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
    if (oldVersion < 11) {
      // v11: id del mapa publicado en Supabase. Sirve para dos cosas:
      //  - en el equipo admin, republicar sobre la misma fila (idempotente);
      //  - en el equipo usuario, saber si un mapa del catálogo ya se descargó
      //    y, si se re-descarga, reemplazarlo en vez de duplicarlo.
      // Nullable: los pisos que nunca se publicaron/descargaron quedan en null.
      final cols = await db.rawQuery('PRAGMA table_info(pisos)');
      final tieneColumna =
          cols.any((c) => (c['name'] as String?) == 'remote_id');
      if (!tieneColumna) {
        await db.execute('ALTER TABLE pisos ADD COLUMN remote_id TEXT');
      }
    }
    if (oldVersion < 12) {
      // v12: fecha de actualización del mapa remoto al momento de descargarlo.
      // Permite avisar al usuario cuando el admin publicó una versión más nueva.
      final cols = await db.rawQuery('PRAGMA table_info(pisos)');
      final tiene =
          cols.any((c) => (c['name'] as String?) == 'remote_actualizado');
      if (!tiene) {
        await db.execute('ALTER TABLE pisos ADD COLUMN remote_actualizado TEXT');
      }
    }
    if (oldVersion < 13) {
      // v13: pisos identificados por NÚMERO + escaleras entre pisos.
      //
      // Mismo cuidado que en v9/v10: si la tabla se creó con el DDL nuevo la
      // columna ya existe, así que se consulta el esquema antes del ALTER.
      final colsPisos = await db.rawQuery('PRAGMA table_info(pisos)');
      if (!colsPisos.any((c) => (c['name'] as String?) == 'numero_piso')) {
        // Nullable: un piso viejo cuyo nombre no permite deducir el número
        // queda en null hasta que el admin se lo asigne desde la lista.
        await db.execute('ALTER TABLE pisos ADD COLUMN numero_piso INTEGER');
      }
      // Backfill: deducir el número de los nombres libres que ya existían
      // ("Planta Baja", "Piso 2", "Subsuelo 1", "3"...).
      final pisos = await db.query('pisos', columns: ['id', 'nombre_piso']);
      for (final p in pisos) {
        final numero = PisoUtil.numeroDesdeNombre(p['nombre_piso'] as String?);
        if (numero != null) {
          await db.update('pisos', {'numero_piso': numero},
              where: 'id = ?', whereArgs: [p['id']]);
        }
      }

      final colsLug = await db.rawQuery('PRAGMA table_info(lugares_interes)');
      bool tiene(String n) => colsLug.any((c) => (c['name'] as String?) == n);
      if (!tiene('tipo')) {
        await db.execute(
            "ALTER TABLE lugares_interes ADD COLUMN tipo TEXT NOT NULL DEFAULT 'comun'");
      }
      if (!tiene('sube')) {
        await db.execute(
            'ALTER TABLE lugares_interes ADD COLUMN sube INTEGER NOT NULL DEFAULT 0');
      }
      if (!tiene('baja')) {
        await db.execute(
            'ALTER TABLE lugares_interes ADD COLUMN baja INTEGER NOT NULL DEFAULT 0');
      }
      if (!tiene('direccion_entrada')) {
        await db.execute(
            'ALTER TABLE lugares_interes ADD COLUMN direccion_entrada REAL');
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
  /// Crea un piso identificado por su NÚMERO (0 = planta baja, negativos =
  /// subsuelos). El nombre se deriva del número, no se escribe a mano.
  Future<int> crearPiso(int edificioId, int numeroPiso, String rutaImagen) async {
    final db = await instance.database;
    return await db.insert('pisos', {
      'edificio_id': edificioId,
      'numero_piso': numeroPiso,
      'nombre_piso': PisoUtil.nombre(numeroPiso),
      'ruta_imagen': rutaImagen,
    });
  }

  /// Cambia (o asigna, en pisos viejos) el número de un piso. Actualiza
  /// también el nombre derivado para que la nube lo reciba al republicar.
  Future<void> actualizarNumeroPiso(int pisoId, int numeroPiso) async {
    final db = await instance.database;
    await db.update(
      'pisos',
      {
        'numero_piso': numeroPiso,
        'nombre_piso': PisoUtil.nombre(numeroPiso),
      },
      where: 'id = ?',
      whereArgs: [pisoId],
    );
  }

  /// Pisos de un edificio ordenados por número (los sin número, al final).
  Future<List<Map<String, dynamic>>> obtenerPisosPorEdificio(int edificioId) async {
    final db = await instance.database;
    return await db.query(
      'pisos',
      where: 'edificio_id = ?',
      whereArgs: [edificioId],
      orderBy: 'numero_piso IS NULL, numero_piso ASC',
    );
  }

  /// Números de piso ya usados en un edificio (para no repetirlos).
  Future<Set<int>> obtenerNumerosPisoOcupados(int edificioId) async {
    final db = await instance.database;
    final r = await db.query(
      'pisos',
      columns: ['numero_piso'],
      where: 'edificio_id = ? AND numero_piso IS NOT NULL',
      whereArgs: [edificioId],
    );
    return r.map((row) => row['numero_piso'] as int).toSet();
  }

  /// Datos completos de un piso, listos para navegarlo.
  Future<PisoInfo?> obtenerPisoInfo(int pisoId) async {
    final db = await instance.database;
    final r = await db.query('pisos', where: 'id = ?', whereArgs: [pisoId], limit: 1);
    return r.isNotEmpty ? PisoInfo.fromRow(r.first) : null;
  }

  /// Todos los pisos del edificio al que pertenece [pisoId] (incluido él).
  /// Es la base de la navegación entre pisos.
  Future<List<PisoInfo>> obtenerPisosDelMismoEdificio(int pisoId) async {
    final db = await instance.database;
    final r = await db.rawQuery('''
      SELECT p.* FROM pisos p
      WHERE p.edificio_id = (SELECT edificio_id FROM pisos WHERE id = ?)
      ORDER BY p.numero_piso IS NULL, p.numero_piso ASC
    ''', [pisoId]);
    return r.map(PisoInfo.fromRow).toList();
  }

  /// Datos que necesita el modo publicar: nombre del piso, nombre del edificio
  /// padre y el remote_id actual (null si nunca se publicó). Un solo JOIN.
  Future<Map<String, dynamic>?> obtenerPisoConEdificio(int pisoId) async {
    final db = await instance.database;
    final r = await db.rawQuery('''
      SELECT p.id, p.nombre_piso, p.numero_piso, p.remote_id,
             e.nombre AS edificio_nombre
      FROM pisos p
      INNER JOIN edificios e ON p.edificio_id = e.id
      WHERE p.id = ?
      LIMIT 1
    ''', [pisoId]);
    return r.isNotEmpty ? r.first : null;
  }

  /// Persiste el id remoto (Supabase) de un piso tras publicarlo.
  Future<void> guardarRemoteIdPiso(int pisoId, String remoteId) async {
    final db = await instance.database;
    await db.update(
      'pisos',
      {'remote_id': remoteId},
      where: 'id = ?',
      whereArgs: [pisoId],
    );
  }

  /// Marca un piso como no publicado (tras borrarlo de la nube).
  Future<void> limpiarRemoteIdPiso(int pisoId) async {
    final db = await instance.database;
    await db.update(
      'pisos',
      {'remote_id': null},
      where: 'id = ?',
      whereArgs: [pisoId],
    );
  }

  /// remote_ids de los pisos publicados de un edificio. Se usa al borrar un
  /// edificio entero para poder quitar también sus mapas de la nube.
  Future<List<String>> obtenerRemoteIdsDeEdificio(int edificioId) async {
    final db = await instance.database;
    final r = await db.query(
      'pisos',
      columns: ['remote_id'],
      where: 'edificio_id = ? AND remote_id IS NOT NULL',
      whereArgs: [edificioId],
    );
    return r.map((row) => row['remote_id'] as String).toList();
  }

  /// Busca un piso local por su id remoto. Devuelve su `id` local o null.
  /// Se usa para saber si un mapa del catálogo ya está descargado.
  Future<int?> buscarPisoPorRemoteId(String remoteId) async {
    final db = await instance.database;
    final r = await db.query(
      'pisos',
      columns: ['id'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    return r.isNotEmpty ? r.first['id'] as int : null;
  }

  /// Desinstala un mapa descargado: borra el piso local (con sus beacons, zonas,
  /// lugares y calibraciones) y el archivo de imagen del teléfono. Sólo afecta
  /// este dispositivo; el mapa sigue en la nube. No-op si no está descargado.
  Future<void> desinstalarMapaLocal(String remoteId) async {
    final db = await instance.database;
    final r = await db.query(
      'pisos',
      columns: ['id', 'ruta_imagen'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (r.isEmpty) return;
    final pisoId = r.first['id'] as int;
    final ruta = r.first['ruta_imagen'] as String?;

    await db.delete('beacons', where: 'piso_id = ?', whereArgs: [pisoId]);
    await db.delete('zonas_no_transitables',
        where: 'piso_id = ?', whereArgs: [pisoId]);
    await db.delete('lugares_interes',
        where: 'piso_id = ?', whereArgs: [pisoId]);
    await db.delete('calibraciones', where: 'piso_id = ?', whereArgs: [pisoId]);
    await db.delete('pisos', where: 'id = ?', whereArgs: [pisoId]);

    // Borrar el archivo de imagen local (si quedó y existe).
    if (ruta != null && ruta.isNotEmpty) {
      try {
        final f = File(ruta);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Si no se pudo borrar el archivo, no es crítico.
      }
    }
  }

  /// Set de remote_ids ya descargados/publicados en este equipo. Permite al
  /// catálogo marcar en una sola consulta qué mapas ya están en el teléfono.
  Future<Set<String>> obtenerRemoteIdsLocales() async {
    final db = await instance.database;
    final r = await db.query(
      'pisos',
      columns: ['remote_id'],
      where: 'remote_id IS NOT NULL',
    );
    return r.map((row) => row['remote_id'] as String).toSet();
  }

  /// Mapa de remote_id → fecha de la versión descargada (parseada). Sirve para
  /// que el catálogo compare con la nube y marque "Nuevo" / "Actualizado".
  /// El valor es null si el mapa se descargó antes de guardar la versión (v12).
  Future<Map<String, DateTime?>> obtenerMapasDescargados() async {
    final db = await instance.database;
    final r = await db.query(
      'pisos',
      columns: ['remote_id', 'remote_actualizado'],
      where: 'remote_id IS NOT NULL',
    );
    final res = <String, DateTime?>{};
    for (final row in r) {
      final id = row['remote_id'] as String;
      final raw = row['remote_actualizado'] as String?;
      res[id] = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    }
    return res;
  }

  /// Importa un mapa descargado de la nube a la base local, en UNA transacción.
  ///
  /// - Reutiliza el edificio local con el mismo nombre si ya existe; si no, lo
  ///   crea (así los pisos de un mismo edificio quedan agrupados).
  /// - Si ya había un piso con este [remoteId] (re-descarga), borra sus hijos y
  ///   lo actualiza en lugar de duplicarlo.
  /// - Inserta beacons, zonas, lugares y calibraciones desde su JSON crudo.
  ///
  /// Los parámetros de listas reciben el JSON tal como vino de Supabase
  /// (`List<dynamic>` de mapas) y se normalizan acá. Devuelve el piso_id local.
  Future<int> importarMapaDescargado({
    required String remoteId,
    required String edificioNombre,
    required String pisoNombre,
    required String rutaImagen,
    required double escalaX,
    required double escalaY,
    required double tamCelda,
    required double rotacion,
    required List<dynamic> beacons,
    required List<dynamic> zonas,
    required List<dynamic> lugares,
    required List<dynamic> calibraciones,
    String? remoteActualizado,
  }) async {
    final db = await instance.database;
    return await db.transaction<int>((txn) async {
      // Edificio: reusar por nombre o crear.
      int edificioId;
      final ed = await txn.query(
        'edificios',
        columns: ['id'],
        where: 'nombre = ?',
        whereArgs: [edificioNombre],
        limit: 1,
      );
      if (ed.isNotEmpty) {
        edificioId = ed.first['id'] as int;
      } else {
        edificioId = await txn.insert('edificios', {'nombre': edificioNombre});
      }

      // Piso: reusar por remote_id (re-descarga) o crear.
      final datosPiso = {
        'edificio_id': edificioId,
        'nombre_piso': pisoNombre,
        // La nube sólo guarda el nombre; el número se recupera de ahí.
        'numero_piso': PisoUtil.numeroDesdeNombre(pisoNombre),
        'ruta_imagen': rutaImagen,
        'escala_metros': escalaX,
        'escala_metros_alto': escalaY,
        'tam_celda_metros': tamCelda,
        'rotacion_mapa': rotacion,
        'remote_id': remoteId,
        'remote_actualizado': remoteActualizado,
      };

      int pisoId;
      final ex = await txn.query(
        'pisos',
        columns: ['id'],
        where: 'remote_id = ?',
        whereArgs: [remoteId],
        limit: 1,
      );
      if (ex.isNotEmpty) {
        pisoId = ex.first['id'] as int;
        await txn.update('pisos', datosPiso, where: 'id = ?', whereArgs: [pisoId]);
        // Limpiar hijos previos: se reemplazan por la versión descargada.
        await txn.delete('beacons', where: 'piso_id = ?', whereArgs: [pisoId]);
        await txn.delete('zonas_no_transitables',
            where: 'piso_id = ?', whereArgs: [pisoId]);
        await txn.delete('lugares_interes',
            where: 'piso_id = ?', whereArgs: [pisoId]);
        await txn.delete('calibraciones',
            where: 'piso_id = ?', whereArgs: [pisoId]);
      } else {
        pisoId = await txn.insert('pisos', datosPiso);
      }

      // Beacons.
      for (final raw in beacons) {
        final b = Map<String, dynamic>.from(raw as Map);
        await txn.insert('beacons', {
          'piso_id': pisoId,
          'mac': b['mac'],
          'x': (b['x'] as num).toDouble(),
          'y': (b['y'] as num).toDouble(),
          'nombre_beacon': b['nombre'] ?? '',
        });
      }

      // Zonas.
      for (final raw in zonas) {
        final z = Map<String, dynamic>.from(raw as Map);
        final vertices = (z['vertices'] as List)
            .map((v) => {
                  'dx': (v['dx'] as num).toDouble(),
                  'dy': (v['dy'] as num).toDouble(),
                })
            .toList();
        await txn.insert('zonas_no_transitables', {
          'piso_id': pisoId,
          'nombre': z['nombre'] ?? '',
          'vertices_json': jsonEncode(vertices),
        });
      }

      // Lugares de interés.
      for (final raw in lugares) {
        final l = Map<String, dynamic>.from(raw as Map);
        // Los campos de escalera son opcionales: un mapa publicado antes de
        // v13 no los trae y sus lugares quedan como comunes.
        await txn.insert('lugares_interes', {
          'piso_id': pisoId,
          'nombre': l['nombre'] ?? '',
          'x': (l['x'] as num).toDouble(),
          'y': (l['y'] as num).toDouble(),
          'descripcion': l['descripcion'],
          'tipo': LugarInteres.tipoDesdeTexto(l['tipo'] as String?).name,
          'sube': (l['sube'] == true) ? 1 : 0,
          'baja': (l['baja'] == true) ? 1 : 0,
          'direccion_entrada': (l['direccion_entrada'] as num?)?.toDouble(),
        });
      }

      // Calibraciones: el mapa crudo ya tiene la forma exacta de la fila
      // (lecturas_ble / tx_power_ajustado como strings). Sólo se fija piso_id.
      for (final raw in calibraciones) {
        final c = Map<String, dynamic>.from(raw as Map);
        c.remove('id');
        c['piso_id'] = pisoId;
        await txn.insert('calibraciones', c);
      }

      return pisoId;
    });
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
      SELECT pisos.id, pisos.edificio_id, pisos.numero_piso,
             pisos.ruta_imagen, pisos.escala_metros, pisos.escala_metros_alto,
             pisos.tam_celda_metros, pisos.rotacion_mapa,
             pisos.remote_id, pisos.remote_actualizado,
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
    return await db.insert('lugares_interes', lugar.toRow());
  }

  Future<List<LugarInteres>> obtenerLugaresPorPiso(int pisoId) async {
    final db = await instance.database;
    final res = await db.query(
      'lugares_interes',
      where: 'piso_id = ?',
      whereArgs: [pisoId],
    );
    return res.map(LugarInteres.fromRow).toList();
  }

  /// Lugares de TODOS los pisos del edificio al que pertenece [pisoId]
  /// (incluidas las escaleras). Cada lugar conserva su `pisoId`, así la
  /// navegación sabe en qué piso está.
  Future<List<LugarInteres>> obtenerLugaresDelMismoEdificio(int pisoId) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT l.* FROM lugares_interes l
      INNER JOIN pisos p ON l.piso_id = p.id
      WHERE p.edificio_id = (SELECT edificio_id FROM pisos WHERE id = ?)
    ''', [pisoId]);
    return res.map(LugarInteres.fromRow).toList();
  }

  /// Persiste la nueva ubicación de un lugar/escalera tras arrastrarlo.
  Future<void> actualizarPosicionLugar(int id, Offset posicion) async {
    final db = await instance.database;
    await db.update(
      'lugares_interes',
      {'x': posicion.dx, 'y': posicion.dy},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Desinstala del teléfono un mapa descargado (por su remote_id): borra el
  /// piso y todos sus datos. Devuelve la ruta de la imagen local para que el
  /// llamador borre también el archivo. Devuelve null si no estaba descargado.
  Future<String?> eliminarMapaDescargado(String remoteId) async {
    final db = await instance.database;
    final rows = await db.query(
      'pisos',
      columns: ['id', 'ruta_imagen'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pisoId = rows.first['id'] as int;
    final ruta = rows.first['ruta_imagen'] as String?;
    await eliminarPiso(pisoId);
    return ruta;
  }
}