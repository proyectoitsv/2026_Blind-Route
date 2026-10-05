import 'dart:math';
import 'package:flutter/material.dart';

/// Tipo de lugar de interés.
///  - [comun]: un destino normal (baño, aula, terminal...).
///  - [escalera]: conecta con otro piso. Además de su posición guarda si sube,
///    si baja y hacia qué lado da la entrada, para poder guiar al usuario
///    hasta quedar DE FRENTE a la escalera.
enum TipoLugar { comun, escalera }

/// Representa un lugar de interés (Point of Interest) en el mapa.
/// Ejemplos: "Baño", "Terminal 5", "Escalera", etc.
/// Las coordenadas se guardan normalizadas (0.0 a 1.0) relativas al tamaño
/// de la imagen del plano del piso.
class LugarInteres {
  final int? id; // null hasta que se persiste en la DB
  final int pisoId;
  final String nombre;
  final Offset posicion; // Coordenada normalizada (dx, dy entre 0.0 y 1.0)
  final String? descripcion; // Opcional: descripción adicional

  /// Tipo de lugar. Los lugares viejos (antes de v13) quedan como [comun].
  final TipoLugar tipo;

  /// Sólo escaleras: si desde este piso se puede SUBIR por ella.
  final bool sube;

  /// Sólo escaleras: si desde este piso se puede BAJAR por ella.
  final bool baja;

  /// Sólo escaleras: lado del plano hacia el que DA la entrada, en grados
  /// en el marco de la IMAGEN (no del norte geográfico):
  ///   0 = arriba, 90 = derecha, 180 = abajo, 270 = izquierda.
  /// Ejemplo: 180 significa que la boca de la escalera mira hacia abajo del
  /// plano, así que para entrar el usuario llega desde abajo caminando hacia
  /// arriba. La conversión a rumbo real la hace la navegación con la
  /// rotación del mapa, igual que el resto de las indicaciones.
  final double? direccionEntrada;

  /// Sólo con [tipo] == escalera: true si en realidad es un ASCENSOR. Para
  /// la navegación un ascensor es lo mismo que una escalera (conecta pisos,
  /// sube y/o baja, tiene un lado de entrada, la ruta lo rodea y llega por
  /// la puerta); lo único que cambia es cómo se lo nombra y cómo se dibuja.
  /// Por eso no es un tipo aparte sino una variante: todo lo que pregunta
  /// [esEscalera] vale también para los ascensores.
  final bool esAscensor;

  /// Otras formas de pedir este lugar por voz, además de su nombre. Ejemplo:
  /// para "McDonald's", ["restaurante", "comida rápida", "hamburguesas"]. Si
  /// el usuario dice una de estas palabras, este lugar entra como opción; si
  /// varios lugares comparten la palabra, la navegación le da a elegir.
  /// Se guardan tal como las escribió el admin; la comparación (sin tildes,
  /// sin mayúsculas) la hace la navegación.
  final List<String> palabrasClave;

  /// Id del rubro del lugar (ver rubros.dart), o null si no tiene. El rubro
  /// trae sus propias palabras ("comida" → restaurante, comer, almorzar…),
  /// así que es la forma normal de que un lugar se encuentre por lo que es;
  /// [palabrasClave] queda para lo propio de ESTE lugar (apodos, marcas).
  final String? rubro;

  const LugarInteres({
    this.id,
    required this.pisoId,
    required this.nombre,
    required this.posicion,
    this.descripcion,
    this.tipo = TipoLugar.comun,
    this.sube = false,
    this.baja = false,
    this.direccionEntrada,
    this.palabrasClave = const [],
    this.rubro,
    this.esAscensor = false,
  });

  /// true para todo lo que conecta pisos: escaleras Y ascensores.
  bool get esEscalera => tipo == TipoLugar.escalera;

  // Cómo se nombra en una frase, según sea escalera o ascensor.

  /// "Escalera" / "Ascensor".
  String get medioNombre => esAscensor ? 'Ascensor' : 'Escalera';

  /// "la escalera" / "el ascensor".
  String get medioConArticulo => esAscensor ? 'el ascensor' : 'la escalera';

  /// "a la escalera" / "al ascensor".
  String get medioComoDestino => esAscensor ? 'al ascensor' : 'a la escalera';

  /// Lado (m) del cuadrado que ocupa una escalera en el plano. Una escalera
  /// típica mide ~1 m de ancho: con celdas de 1 m ocupa una celda. Lo usan
  /// el dibujo del mapa y el pathfinder (la escalera es un obstáculo).
  static const double anchoEscaleraMetros = 1.0;

  /// Área (normalizada) que ocupa la escalera: un cuadrado de
  /// [anchoEscaleraMetros] de lado centrado en su posición.
  Rect areaEscalera({required double metrosX, required double metrosY}) {
    return Rect.fromCenter(
      center: posicion,
      width: metrosX > 0 ? anchoEscaleraMetros / metrosX : 0,
      height: metrosY > 0 ? anchoEscaleraMetros / metrosY : 0,
    );
  }

  LugarInteres copyWith({int? id, Offset? posicion}) {
    return LugarInteres(
      id: id ?? this.id,
      pisoId: pisoId,
      nombre: nombre,
      posicion: posicion ?? this.posicion,
      descripcion: descripcion,
      tipo: tipo,
      sube: sube,
      baja: baja,
      direccionEntrada: direccionEntrada,
      palabrasClave: palabrasClave,
      rubro: rubro,
      esAscensor: esAscensor,
    );
  }

  // ── Palabras clave ────────────────────────────────────────────────────────

  /// Convierte lo que escribió el admin ("restaurante, bar; café") en la
  /// lista de palabras clave: separa por coma, punto y coma o salto de línea,
  /// recorta espacios y saca vacíos y repetidos (sin distinguir mayúsculas).
  static List<String> palabrasDesdeTexto(String? texto) {
    if (texto == null || texto.trim().isEmpty) return const [];
    final vistas = <String>{};
    final salida = <String>[];
    for (final parte in texto.split(RegExp(r'[,;\n]'))) {
      final p = parte.trim();
      if (p.isEmpty) continue;
      if (vistas.add(p.toLowerCase())) salida.add(p);
    }
    return salida;
  }

  /// Lo mismo desde el JSON de la nube, donde viajan como lista. Acepta
  /// también un texto separado por comas y null (mapas publicados antes de
  /// que existieran las palabras clave).
  static List<String> palabrasDesdeJson(dynamic valor) {
    if (valor is List) {
      return palabrasDesdeTexto(valor.map((e) => '$e').join(','));
    }
    if (valor is String) return palabrasDesdeTexto(valor);
    return const [];
  }

  /// Texto para guardar en SQLite / mostrar en el campo de edición.
  static String? palabrasATexto(List<String> palabras) =>
      palabras.isEmpty ? null : palabras.join(', ');

  /// Punto (normalizado) donde el usuario queda parado frente a la boca de
  /// la escalera, a [distanciaMetros] de su posición, del lado de la entrada.
  /// Es el punto al que se calcula la ruta, para que llegue por el lado
  /// correcto y no por un costado o por detrás.
  /// Si la escalera no tiene dirección cargada, devuelve su posición.
  Offset puntoEntrada({
    required double metrosX,
    required double metrosY,
    double distanciaMetros = 1.2,
  }) {
    final dir = direccionEntrada;
    if (dir == null || metrosX <= 0 || metrosY <= 0) return posicion;
    final rad = dir * pi / 180;
    // En el marco de la imagen: arriba es -y, derecha es +x.
    final dx = sin(rad) * distanciaMetros / metrosX;
    final dy = -cos(rad) * distanciaMetros / metrosY;
    return Offset(
      (posicion.dx + dx).clamp(0.0, 1.0),
      (posicion.dy + dy).clamp(0.0, 1.0),
    );
  }

  // ── Serialización a la fila de SQLite ─────────────────────────────────────

  Map<String, dynamic> toRow() => {
        'piso_id': pisoId,
        'nombre': nombre,
        'x': posicion.dx,
        'y': posicion.dy,
        'descripcion': descripcion,
        'tipo': tipo.name,
        'sube': sube ? 1 : 0,
        'baja': baja ? 1 : 0,
        'direccion_entrada': direccionEntrada,
        'palabras_clave': palabrasATexto(palabrasClave),
        'rubro': rubro,
        'ascensor': esAscensor ? 1 : 0,
      };

  factory LugarInteres.fromRow(Map<String, dynamic> row) {
    return LugarInteres(
      id: row['id'] as int?,
      pisoId: row['piso_id'] as int,
      nombre: row['nombre'] as String,
      posicion: Offset(
        (row['x'] as num).toDouble(),
        (row['y'] as num).toDouble(),
      ),
      descripcion: row['descripcion'] as String?,
      tipo: tipoDesdeTexto(row['tipo'] as String?),
      sube: (row['sube'] as int? ?? 0) == 1,
      baja: (row['baja'] as int? ?? 0) == 1,
      direccionEntrada: (row['direccion_entrada'] as num?)?.toDouble(),
      palabrasClave: palabrasDesdeTexto(row['palabras_clave'] as String?),
      rubro: row['rubro'] as String?,
      esAscensor: (row['ascensor'] as int? ?? 0) == 1,
    );
  }

  // ── Serialización para la nube (JSON de la columna `lugares`) ─────────────
  //
  // Los campos nuevos viajan dentro del mismo JSONB que ya existía, así que
  // la tabla de Supabase no necesita cambios. Un mapa viejo (sin estos
  // campos) se descarga con todos sus lugares como comunes.

  Map<String, dynamic> toJsonNube() => {
        'nombre': nombre,
        'x': posicion.dx,
        'y': posicion.dy,
        'descripcion': descripcion,
        'tipo': tipo.name,
        'sube': sube,
        'baja': baja,
        'direccion_entrada': direccionEntrada,
        'palabras_clave': palabrasClave,
        'rubro': rubro,
        'ascensor': esAscensor,
      };

  static TipoLugar tipoDesdeTexto(String? texto) =>
      texto == TipoLugar.escalera.name ? TipoLugar.escalera : TipoLugar.comun;
}