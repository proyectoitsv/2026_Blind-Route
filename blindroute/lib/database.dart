import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'beacon_model.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/semantics.dart';



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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Tabla de Edificios
    await db.execute('''
      CREATE TABLE edificios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL
      )
    ''');

    // Tabla de Pisos
    await db.execute('''
      CREATE TABLE pisos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        edificio_id INTEGER NOT NULL,
        nombre_piso TEXT NOT NULL,
        ruta_imagen TEXT NOT NULL,
        FOREIGN KEY (edificio_id) REFERENCES edificios (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de Beacons
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
  }

  // --- Funciones para Edificios ---
  Future<int> crearEdificio(String nombre) async {
    final db = await instance.database;
    return await db.insert('edificios', {'nombre': nombre});
  }

  Future<List<Map<String, dynamic>>> obtenerEdificios() async {
    final db = await instance.database;
    return await db.query('edificios');
  }

  // --- Funciones para Pisos ---
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

  // --- Funciones para Beacons ---
  Future<void> guardarBeacons(int pisoId, List<BeaconMarcado> beacons) async {
    final db = await instance.database;
    // Borramos los viejos de este piso y cargamos los nuevos (para actualizar)
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
  
  // Buscamos el beacon y traemos la info del piso al que pertenece
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
}
