import 'poi_model.dart';
import 'rubros.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BÚSQUEDA DE LUGARES POR VOZ: NOMBRE, RUBRO Y PALABRAS CLAVE
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Dado lo que dijo el usuario, devuelve qué lugares pueden ser. La pantalla
/// de navegación decide qué hacer con el resultado: si es uno, va; si son
/// varios, le lee las opciones para que elija.
///
/// Cada lugar recibe un puntaje y se devuelven los que EMPATAN en el más
/// alto:
///
///  • Dijo el NOMBRE COMPLETO del lugar ("llevame al burger king") → 100 o
///    más. Le gana a todo lo demás: si lo nombró, quiere ese.
///  • Dijo alguna PALABRA del nombre ("restaurante" para "Restaurante Burger
///    King") → una por palabra acertada.
///  • Dijo una palabra del RUBRO del lugar ("comer" para cualquier lugar
///    del rubro Comida; las palabras de cada rubro están en rubros.dart) →
///    una por cada palabra.
///  • Dijo una PALABRA CLAVE propia de ese lugar, cargada por el admin ("el
///    mac" para "McDonald's") → una por cada palabra de la clave.
///
/// Que las palabras del nombre, las del rubro y las palabras clave valgan
/// lo mismo es a propósito: si el usuario dice "restaurante", tienen que
/// aparecer juntos el lugar que se LLAMA "Restaurante X" y el que es del
/// rubro Comida aunque se llame de otra forma.
///
/// Todo es comparación de palabras enteras, sin tildes ni mayúsculas y
/// tolerando el plural ("restaurantes" = "restaurante", "bares" = "bar").
/// No se compara por pedazos de palabra: "bar" no tiene que encontrar
/// "barbería".
class BuscadorLugares {
  /// Pasa a minúsculas, saca tildes y signos, y deja la ñ como n.
  ///
  /// Con la ñ como n, "baño" se encuentra igual lo escriban "baño", "BAÑO"
  /// o "bano" (el reconocedor de voz a veces la pierde). El costo es que
  /// "peña" y "pena" pasan a ser la misma palabra, cosa que en la práctica
  /// no molesta. La única excepción es "uña / uñas": sin la ñ quedarían como
  /// "una / unas", que son artículos y se descartan como palabras vacías, y
  /// entonces "uñas" no encontraría nada. Esas dos se guardan aparte.
  static String normalizar(String texto) {
    return texto
        .toLowerCase()
        // ñ escrita como n + tilde suelta (algunos teclados y reconocedores
        // la mandan así): se junta para tratarla igual que la otra.
        .replaceAll('n\u0303', 'ñ')
        .replaceAllMapped(RegExp(r'\buña(s?)\b'), (m) => 'unha${m[1]}')
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        // La ñ se pasa a n ANTES de limpiar: si no, "baño" quedaba como
        // "bao" (la ñ caía en el filtro de caracteres).
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim();
  }

  /// Palabras que no dicen nada sobre el destino ("quiero ir al…"). No
  /// cuentan como acierto aunque también estén en el nombre de un lugar
  /// ("Sala DE espera").
  static const Set<String> _vacias = {
    'a', 'al', 'el', 'la', 'los', 'las', 'lo', 'un', 'una', 'unos', 'unas',
    'de', 'del', 'en', 'y', 'o', 'por', 'para', 'con', 'que', 'me', 'mi',
    'quiero', 'quisiera', 'necesito', 'busco', 'buscar', 'ir', 'voy', 'vamos',
    'llevame', 'lleva', 'llevar', 'hasta', 'hacia', 'donde', 'queda', 'esta',
    'hay', 'algun', 'alguna', 'algo', 'favor', 'porfa', 'tengo', 'ganas',
    'mas', 'cerca', 'cercano', 'cercana',
  };

  static const List<String> _palabrasEscalera = ['escalera'];
  static const List<String> _palabrasAscensor = ['ascensor', 'elevador'];

  static List<String> _palabras(String textoNorm) =>
      textoNorm.split(' ').where((p) => p.isNotEmpty).toList();

  /// Misma palabra, tolerando el plural en cualquiera de las dos.
  static bool mismaPalabra(String a, String b) =>
      a == b || '${a}s' == b || '${a}es' == b || '${b}s' == a || '${b}es' == a;

  /// ¿[chica] aparece dentro de [grande] como palabras seguidas?
  static bool _contieneSecuencia(List<String> grande, List<String> chica) {
    if (chica.isEmpty || chica.length > grande.length) return false;
    for (int i = 0; i + chica.length <= grande.length; i++) {
      bool igual = true;
      for (int j = 0; j < chica.length; j++) {
        if (!mismaPalabra(grande[i + j], chica[j])) {
          igual = false;
          break;
        }
      }
      if (igual) return true;
    }
    return false;
  }

  /// Qué tan bien responde [lugar] a lo que dijo el usuario ([textoNorm], ya
  /// normalizado). 0 = nada que ver.
  static int puntaje(String textoNorm, LugarInteres lugar) {
    final texto = _palabras(textoNorm);
    if (texto.isEmpty) return 0;
    final textoUtil = texto.where((p) => !_vacias.contains(p)).toList();

    // Nombre completo dicho tal cual.
    final nombre = _palabras(normalizar(lugar.nombre));
    if (_contieneSecuencia(texto, nombre)) return 100 + nombre.length;

    // Palabras del nombre.
    final nombreUtil = nombre.where((p) => !_vacias.contains(p)).toList();
    int mejor = 0;
    for (final p in textoUtil) {
      if (nombreUtil.any((n) => mismaPalabra(p, n))) mejor++;
    }

    // Palabras del rubro y palabras clave propias del lugar. Se puntúan
    // igual.
    final rubro = Rubros.porId(lugar.rubro);
    final claves = <List<String>>[
      // Se normalizan acá, así en rubros.dart se pueden escribir con ñ y
      // tildes ("baño", "niños", "librería") sin que dejen de encontrarse.
      if (rubro != null)
        for (final p in rubro.palabras) _palabras(normalizar(p)),
      for (final c in lugar.palabrasClave) _palabras(normalizar(c)),
      // Escaleras y ascensores no tienen rubro: se encuentran por lo que
      // son, se llamen como se llamen ("Núcleo B").
      if (lugar.esEscalera)
        for (final p in lugar.esAscensor ? _palabrasAscensor : _palabrasEscalera)
          [p],
    ];
    for (final k in claves) {
      if (k.isEmpty) continue;
      int p = 0;
      if (_contieneSecuencia(texto, k)) {
        // Dijo la clave entera ("comida rapida").
        p = k.where((x) => !_vacias.contains(x)).length;
        if (p == 0) p = 1;
      } else if (textoUtil.isNotEmpty && _contieneSecuencia(k, textoUtil)) {
        // Dijo una parte de una clave de varias palabras ("comida").
        p = textoUtil.length;
      }
      if (p > mejor) mejor = p;
    }
    return mejor;
  }

  /// Lugares de [lugares] que mejor responden a [textoNorm]: todos los que
  /// empatan en el puntaje más alto. Lista vacía si ninguno tiene que ver.
  static List<LugarInteres> candidatos(
    String textoNorm,
    Iterable<LugarInteres> lugares,
  ) {
    int mejor = 0;
    final salida = <LugarInteres>[];
    for (final l in lugares) {
      final p = puntaje(textoNorm, l);
      if (p == 0 || p < mejor) continue;
      if (p > mejor) {
        mejor = p;
        salida.clear();
      }
      salida.add(l);
    }
    return salida;
  }

  // ── Respuesta a "¿vamos ahí?" ─────────────────────────────────────────────

  static const Set<String> _palabrasSi = {
    'si', 'sisi', 'sip', 'dale', 'bueno', 'ok', 'okey', 'okay', 'vamos',
    'ese', 'esa', 'ahi', 'listo', 'claro', 'perfecto', 'obvio', 'acuerdo',
    'afirmativo', 'joya',
  };
  static const Set<String> _palabrasNo = {
    'no', 'nop', 'otro', 'otra', 'otros', 'otras', 'opcion', 'opciones',
    'cuales', 'diferente', 'distinto', 'distinta', 'ninguno', 'ninguna',
    'negativo', 'tampoco',
  };

  /// true si la respuesta es un sí, false si es un no, null si no se
  /// entiende. Con las dos cosas en la misma frase gana el no ("no, vamos a
  /// otro"): ir a un lugar que no quería es peor que volver a preguntar.
  static bool? siONo(String respuestaNorm) {
    final palabras = _palabras(respuestaNorm);
    if (palabras.any(_palabrasNo.contains)) return false;
    if (palabras.any(_palabrasSi.contains)) return true;
    return null;
  }

  /// ¿Dijo el nombre COMPLETO de [lugar]? (No una palabra suelta que también
  /// esté en el nombre.)
  static bool dijoNombreCompleto(String respuestaNorm, LugarInteres lugar) {
    final nombre = _palabras(normalizar(lugar.nombre));
    return _contieneSecuencia(_palabras(respuestaNorm), nombre);
  }

  // ── Respuesta a "¿a cuál vas?" ────────────────────────────────────────────

  static const List<Set<String>> _ordinales = [
    {'primero', 'primera', 'primer', 'uno', '1'},
    {'segundo', 'segunda', 'dos', '2'},
    {'tercero', 'tercera', 'tercer', 'tres', '3'},
    {'cuarto', 'cuarta', 'cuatro', '4'},
  ];

  /// Índice de la opción que eligió el usuario al responder, o null si no se
  /// entiende. Acepta el nombre (o una parte que no se confunda con otra
  /// opción) y también "primero", "segundo", "el último"… Con [ordinales] en
  /// false sólo vale el nombre.
  static int? opcionDicha(
    String respuestaNorm,
    List<LugarInteres> opciones, {
    bool ordinales = true,
  }) {
    if (opciones.isEmpty) return null;
    final palabras = _palabras(respuestaNorm);
    if (palabras.isEmpty) return null;

    // 1) Por nombre: tiene que ganar UNA sola opción.
    final sinClaves = [
      for (final o in opciones)
        puntaje(
          respuestaNorm,
          LugarInteres(pisoId: o.pisoId, nombre: o.nombre, posicion: o.posicion),
        ),
    ];
    int mejor = 0;
    for (final p in sinClaves) {
      if (p > mejor) mejor = p;
    }
    if (mejor > 0) {
      final ganadoras = [
        for (int i = 0; i < sinClaves.length; i++)
          if (sinClaves[i] == mejor) i,
      ];
      if (ganadoras.length == 1) return ganadoras.first;
    }

    // 2) Por orden.
    if (!ordinales) return null;
    if (palabras.any((p) => p == 'ultimo' || p == 'ultima')) {
      return opciones.length - 1;
    }
    for (int i = 0; i < _ordinales.length && i < opciones.length; i++) {
      if (palabras.any(_ordinales[i].contains)) return i;
    }
    return null;
  }
}