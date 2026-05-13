import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
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
      version: 3, // Incrementamos versión para la migración de POIs
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
  }

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
      SELECT pisos.id, pisos.ruta_imagen, edificios.nombre as edificio_nombre, pisos.nombre_piso
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
      await txn.delete('pisos', where: 'edificio_id = ?', whereArgs: [edificioId]);
      await txn.delete('edificios', where: 'id = ?', whereArgs: [edificioId]);
    });
  }

  Future<int> eliminarPiso(int id) async {
    final db = await instance.database;
    await db.delete('beacons', where: 'piso_id = ?', whereArgs: [id]);
    await db.delete('zonas_no_transitables', where: 'piso_id = ?', whereArgs: [id]);
    await db.delete('lugares_interes', where: 'piso_id = ?', whereArgs: [id]);
    return await db.delete('pisos', where: 'id = ?', whereArgs: [id]);
  }
}