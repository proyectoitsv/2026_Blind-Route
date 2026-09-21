/// Utilidades para trabajar con pisos identificados por NÚMERO.
///
/// Convención de numeración (la misma en admin, usuario y nube):
///   0  → Planta baja
///   >0 → Piso N
///   <0 → Subsuelo N (ej: -1 = Subsuelo 1)
///
/// El nombre que se guarda en `pisos.nombre_piso` (y el `piso_nombre` que se
/// publica en Supabase) se DERIVA siempre del número con [PisoUtil.nombre].
/// Así la nube no necesita una columna nueva: al descargar, el número se
/// recupera del nombre con [PisoUtil.numeroDesdeNombre].
class PisoUtil {
  PisoUtil._();

  /// Rango de pisos que se ofrecen en el selector del admin.
  static const int minimo = -3;
  static const int maximo = 20;

  /// Nombre visible del piso (lo que se guarda en la base).
  static String nombre(int numero) {
    if (numero == 0) return 'Planta baja';
    if (numero > 0) return 'Piso $numero';
    return 'Subsuelo ${-numero}';
  }

  /// Etiqueta corta para los botones del selector.
  static String etiquetaCorta(int numero) {
    if (numero == 0) return 'PB';
    if (numero > 0) return '$numero';
    return 'S${-numero}';
  }

  /// Forma en que se nombra el piso dentro de una frase hablada
  /// (ej: "Subí la escalera hasta el piso 2").
  static String paraVoz(int numero) {
    if (numero == 0) return 'la planta baja';
    if (numero > 0) return 'el piso $numero';
    return 'el subsuelo ${-numero}';
  }

  /// Piso como destino de un movimiento (ej: "Subí al piso 2",
  /// "Bajá a la planta baja").
  static String destinoVoz(int numero) {
    if (numero == 0) return 'a la planta baja';
    if (numero > 0) return 'al piso $numero';
    return 'al subsuelo ${-numero}';
  }

  /// Recupera el número de piso a partir de un nombre. Sirve para:
  ///  - mapas descargados de la nube (sólo traen `piso_nombre`);
  ///  - migrar pisos viejos que se cargaron con nombre libre.
  /// Devuelve null si el nombre no permite deducir un número.
  static int? numeroDesdeNombre(String? nombre) {
    if (nombre == null) return null;
    final n = nombre
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .trim();
    if (n.isEmpty) return null;

    if (n.contains('planta baja') || n == 'pb') return 0;

    final sub = RegExp(r'(subsuelo|sotano)\s*(\d+)').firstMatch(n);
    if (sub != null) return -int.parse(sub.group(2)!);
    if (n.contains('subsuelo') || n.contains('sotano')) return -1;

    final num = RegExp(r'-?\d+').firstMatch(n);
    if (num != null) return int.parse(num.group(0)!);

    return null;
  }
}

/// Datos de un piso que necesita la navegación para cargarlo (incluido el
/// "salto" de un piso a otro). Se arma desde una fila de la tabla `pisos`.
class PisoInfo {
  final int id;
  final int edificioId;
  final int? numero;
  final String nombre;
  final String rutaImagen;
  final double escalaX;
  final double escalaY;
  final double tamCeldaMetros;
  final double rotacionMapa;

  const PisoInfo({
    required this.id,
    required this.edificioId,
    required this.numero,
    required this.nombre,
    required this.rutaImagen,
    required this.escalaX,
    required this.escalaY,
    required this.tamCeldaMetros,
    required this.rotacionMapa,
  });

  factory PisoInfo.fromRow(Map<String, dynamic> row) {
    return PisoInfo(
      id: row['id'] as int,
      edificioId: row['edificio_id'] as int,
      numero: row['numero_piso'] as int?,
      nombre: (row['nombre_piso'] as String?) ?? 'Piso',
      rutaImagen: row['ruta_imagen'] as String,
      escalaX: (row['escala_metros'] as num?)?.toDouble() ?? 50,
      escalaY: (row['escala_metros_alto'] as num?)?.toDouble() ?? 50,
      tamCeldaMetros: (row['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
      rotacionMapa: (row['rotacion_mapa'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Nombre a mostrar: si tiene número, el derivado; si no, el guardado.
  String get nombreVisible => numero != null ? PisoUtil.nombre(numero!) : nombre;
}