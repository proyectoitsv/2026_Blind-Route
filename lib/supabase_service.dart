import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'calibracion_model.dart';
import 'database.dart';
import 'supabase_config.dart';

/// Ítem liviano del catálogo de mapas publicados. NO trae los datos pesados
/// (beacons, zonas, calibraciones): sólo lo justo para pintar la lista.
/// Esos datos se descargan recién cuando el usuario toca "Descargar".
class MapaPublicadoResumen {
  final String id; // uuid remoto = clave de publicación/descarga
  final String edificioNombre;
  final String pisoNombre;
  final String imagenPath; // ruta dentro del bucket de Storage
  final int numBeacons;
  final int numCalibraciones;
  final DateTime actualizadoEn;
  final String? publicadoPor; // uid del admin dueño (sólo se lee en modo admin)

  const MapaPublicadoResumen({
    required this.id,
    required this.edificioNombre,
    required this.pisoNombre,
    required this.imagenPath,
    required this.numBeacons,
    required this.numCalibraciones,
    required this.actualizadoEn,
    this.publicadoPor,
  });

  factory MapaPublicadoResumen.fromRow(Map<String, dynamic> row) {
    return MapaPublicadoResumen(
      id: row['id'] as String,
      edificioNombre: (row['edificio_nombre'] as String?) ?? 'Sin nombre',
      pisoNombre: (row['piso_nombre'] as String?) ?? 'Piso',
      imagenPath: (row['imagen_path'] as String?) ?? '',
      numBeacons: (row['num_beacons'] as num?)?.toInt() ?? 0,
      numCalibraciones: (row['num_calibraciones'] as num?)?.toInt() ?? 0,
      actualizadoEn: DateTime.tryParse('${row['actualizado_en']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      publicadoPor: row['publicado_por'] as String?,
    );
  }
}

/// Cliente de la nube de mapas. Encapsula toda la interacción con Supabase
/// (Postgres + Storage) para que el resto de la app no sepa nada del SDK.
///
/// Diseño pensado para ir liviano:
///  - La imagen del plano vive en Storage, no como base64 en una fila.
///  - Cada piso publicado es UNA fila; sus hijos (beacons/zonas/lugares/
///    calibraciones) van como columnas JSONB. Publicar = 1 subida + 1 upsert;
///    descargar = 1 select + 1 download. Sin N+1 ni transacciones remotas.
///  - El catálogo lee sólo columnas livianas (sin los JSONB), así listar es
///    barato aunque haya cientos de calibraciones por piso.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const String _tabla = 'mapas_publicados';

  bool get configurado => SupabaseConfig.configurado;

  SupabaseClient get _client => Supabase.instance.client;
  String get _bucket => SupabaseConfig.bucketImagenes;

  // ── PUBLICAR (admin) ──────────────────────────────────────────────────────

  /// Sube (o actualiza) un piso completo a la nube y devuelve su id remoto.
  ///
  /// Si [remoteIdExistente] no es null, se re-publica sobre esa misma fila
  /// (upsert por id): republicar un mapa no crea duplicados, lo reemplaza.
  /// El llamador debe persistir el id devuelto en `pisos.remote_id`.
  Future<String> publicarPiso({
    required String edificioNombre,
    required String pisoNombre,
    required String rutaImagen,
    required double escalaX,
    required double escalaY,
    required double tamCelda,
    required double rotacion,
    required Iterable<BeaconMarcado> beacons,
    required List<ZonaNoTransitable> zonas,
    required List<LugarInteres> lugares,
    required List<CalibracionRegistro> calibraciones,
    String? remoteIdExistente,
  }) async {
    final id = (remoteIdExistente != null && remoteIdExistente.isNotEmpty)
        ? remoteIdExistente
        : _uuidV4();

    // 1) Imagen del plano → Storage (upsert: pisa la anterior si ya existía).
    final archivo = File(rutaImagen);
    if (!await archivo.exists()) {
      throw Exception('No se encontró la imagen del plano en disco.');
    }
    final Uint8List bytes = await archivo.readAsBytes();
    final ext = p.extension(rutaImagen).toLowerCase();
    final storagePath = '$id$ext';
    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeDe(ext),
            cacheControl: '3600',
          ),
        );

    // 2) Fila del piso + hijos en JSONB → un único upsert.
    final beaconsList = beacons.toList();
    final fila = <String, dynamic>{
      'id': id,
      'edificio_nombre': edificioNombre,
      'piso_nombre': pisoNombre,
      'imagen_path': storagePath,
      'escala_metros': escalaX,
      'escala_metros_alto': escalaY,
      'tam_celda_metros': tamCelda,
      'rotacion_mapa': rotacion,
      'beacons': beaconsList
          .map((b) => {
                'mac': b.mac,
                'x': b.posicion.dx,
                'y': b.posicion.dy,
                'nombre': b.nombre,
              })
          .toList(),
      'zonas': zonas
          .map((z) => {
                'nombre': z.nombre,
                'vertices':
                    z.vertices.map((v) => {'dx': v.dx, 'dy': v.dy}).toList(),
              })
          .toList(),
      'lugares': lugares
          .map((l) => {
                'nombre': l.nombre,
                'x': l.posicion.dx,
                'y': l.posicion.dy,
                'descripcion': l.descripcion,
              })
          .toList(),
      // toJson() ya deja lecturas_ble / tx_power_ajustado como strings y el
      // timestamp en ISO: se guarda tal cual y CalibracionRegistro.fromJson lo
      // reconstruye igual al descargar. Sólo se quita el id local.
      'calibraciones': calibraciones.map((c) {
        final m = c.toJson();
        m.remove('id');
        return m;
      }).toList(),
      'num_beacons': beaconsList.length,
      'num_calibraciones': calibraciones.length,
      'actualizado_en': DateTime.now().toUtc().toIso8601String(),
    };

    // Postgres no admite el carácter nulo \u0000 en text/jsonb. Algunas
    // lecturas BLE traen bytes nulos de relleno; se limpian antes de subir.
    // Se reconstruye el nivel superior como Map<String, dynamic> (lo que exige
    // upsert); los valores anidados se limpian recursivamente.
    final filaLimpia = <String, dynamic>{
      for (final entrada in fila.entries)
        entrada.key: _limpiarNulos(entrada.value),
    };
    await _client.from(_tabla).upsert(filaLimpia);
    return id;
  }

  // ── CATÁLOGO (usuario) ────────────────────────────────────────────────────

  /// Lista los mapas publicados con columnas livianas (sin los JSONB pesados).
  Future<List<MapaPublicadoResumen>> listarMapas() async {
    final data = await _client
        .from(_tabla)
        .select(
          'id, edificio_nombre, piso_nombre, imagen_path, '
          'num_beacons, num_calibraciones, actualizado_en',
        )
        .order('edificio_nombre', ascending: true)
        .order('piso_nombre', ascending: true);

    return (data as List)
        .map((e) => MapaPublicadoResumen.fromRow(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// URL pública de la imagen de un mapa (para thumbnails del catálogo).
  String urlImagen(String imagenPath) =>
      _client.storage.from(_bucket).getPublicUrl(imagenPath);

  // ── AUTODESCARGA POR BEACON ────────────────────────────────────────────────

  /// Dada una lista de MACs detectadas, pregunta al servidor si algún mapa
  /// publicado contiene alguna de ellas. Devuelve el id remoto del mapa o null.
  /// La búsqueda ocurre en el server (dentro del JSONB de beacons); no baja
  /// datos pesados hasta que efectivamente se descarga el mapa.
  Future<String?> buscarMapaPorMacs(List<String> macs) async {
    if (macs.isEmpty) return null;
    final res = await _client
        .rpc('buscar_mapa_por_macs', params: {'p_macs': macs});
    return res as String?;
  }

  // ── CATÁLOGO ADMIN ────────────────────────────────────────────────────────

  /// id del admin logueado (para saber cuáles mapas son propios). Null si no
  /// hay sesión.
  String? get usuarioActualId => _client.auth.currentUser?.id;

  /// Igual que [listarMapas] pero incluye el dueño de cada mapa, para que la
  /// pantalla de administración marque los propios y los ordene primero.
  Future<List<MapaPublicadoResumen>> listarMapasAdmin() async {
    final data = await _client
        .from(_tabla)
        .select(
          'id, edificio_nombre, piso_nombre, imagen_path, '
          'num_beacons, num_calibraciones, actualizado_en, publicado_por',
        )
        .order('edificio_nombre', ascending: true)
        .order('piso_nombre', ascending: true);

    return (data as List)
        .map((e) => MapaPublicadoResumen.fromRow(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── ELIMINAR (admin dueño) ────────────────────────────────────────────────

  /// Borra un mapa publicado (imagen + fila). La imagen se quita con la API de
  /// Storage (borrarla por SQL directo está prohibido). La fila la borra la RLS
  /// por dueño: si el mapa es de otro administrador, no se borra nada y se lanza
  /// un error. Se borra la imagen primero (con la fila aún presente) para que la
  /// regla de Storage pueda verificar el dueño.
  Future<void> eliminarMapa(String remoteId) async {
    // 1) Ruta de la imagen en el bucket.
    final row = await _client
        .from(_tabla)
        .select('imagen_path')
        .eq('id', remoteId)
        .maybeSingle();
    final imagenPath = row == null ? null : row['imagen_path'] as String?;

    // 2) Imagen → API de Storage.
    if (imagenPath != null && imagenPath.isNotEmpty) {
      await _client.storage.from(_bucket).remove([imagenPath]);
    }

    // 3) Fila → la RLS por dueño decide. Si no borró nada, no era el dueño.
    final borradas =
        await _client.from(_tabla).delete().eq('id', remoteId).select('id');
    if ((borradas as List).isEmpty) {
      throw Exception('No autorizado: el mapa es de otro administrador.');
    }
  }

  // ── DESCARGAR (usuario) ───────────────────────────────────────────────────

  /// Descarga un mapa completo y lo importa a la base local. Devuelve el
  /// `piso_id` local resultante (listo para navegar). Si ese mapa ya se había
  /// descargado antes (mismo remote_id), lo reemplaza en vez de duplicarlo.
  Future<int> descargarMapa(String remoteId) async {
    // 1) Fila completa (incluye los JSONB).
    final row = Map<String, dynamic>.from(
      await _client.from(_tabla).select().eq('id', remoteId).single(),
    );

    // 2) Imagen → archivo local permanente.
    final imagenPath = row['imagen_path'] as String;
    final Uint8List bytes =
        await _client.storage.from(_bucket).download(imagenPath);
    final dir = await getApplicationDocumentsDirectory();
    final ext = p.extension(imagenPath);
    final rutaLocal = p.join(dir.path, 'mapa_$remoteId$ext');
    await File(rutaLocal).writeAsBytes(bytes, flush: true);

    // 3) Insertar/actualizar en la base local en una sola transacción.
    return DatabaseHelper.instance.importarMapaDescargado(
      remoteId: remoteId,
      edificioNombre: (row['edificio_nombre'] as String?) ?? 'Descargado',
      pisoNombre: (row['piso_nombre'] as String?) ?? 'Piso',
      rutaImagen: rutaLocal,
      escalaX: (row['escala_metros'] as num?)?.toDouble() ?? 50,
      escalaY: (row['escala_metros_alto'] as num?)?.toDouble() ?? 50,
      tamCelda: (row['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
      rotacion: (row['rotacion_mapa'] as num?)?.toDouble() ?? 0.0,
      beacons: (row['beacons'] as List?) ?? const [],
      zonas: (row['zonas'] as List?) ?? const [],
      lugares: (row['lugares'] as List?) ?? const [],
      calibraciones: (row['calibraciones'] as List?) ?? const [],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Recorre mapas/listas/strings y elimina el carácter nulo \u0000, que
  /// Postgres no acepta en text/jsonb. Devuelve una copia limpia.
  static dynamic _limpiarNulos(dynamic valor) {
    if (valor is String) {
      return valor.contains('\u0000')
          ? valor.replaceAll('\u0000', '')
          : valor;
    }
    if (valor is Map) {
      return valor.map((k, v) => MapEntry(k, _limpiarNulos(v)));
    }
    if (valor is List) {
      return valor.map(_limpiarNulos).toList();
    }
    return valor;
  }

  static String _mimeDe(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  /// UUID v4 generado en el cliente (sin dependencias extra) para poder hacer
  /// el upsert de la fila en un solo viaje, con id conocido de antemano.
  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante 10xx
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final s = b.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}