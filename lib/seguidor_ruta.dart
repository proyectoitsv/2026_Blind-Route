import 'dart:math';
import 'dart:ui';
import 'grilla_nav.dart';

/// Dónde está el usuario respecto de la ruta vigente.
class UbicacionEnRuta {
  /// Índice de la celda de la ruta más cercana al usuario (dentro de la
  /// ventana de búsqueda).
  final int indice;

  /// Distancia (m) entre la celda del usuario y esa celda de la ruta.
  final double desvioMetros;

  /// true si el desvío está dentro de [SeguidorRuta.toleranciaEnRutaMetros].
  final bool enRuta;

  const UbicacionEnRuta(this.indice, this.desvioMetros, this.enRuta);
}

/// Tramo que hay que indicarle al usuario: desde dónde se mide y hacia dónde
/// apunta la indicación.
class TramoGuiado {
  final Offset desde;
  final Offset hacia;
  const TramoGuiado(this.desde, this.hacia);
}

/// Resultado de comparar la ruta recién calculada con la que se venía
/// siguiendo.
class DecisionRuta {
  /// Ruta que queda vigente. Siempre arranca en la celda del usuario.
  final List<Offset> ruta;

  /// true si se adoptó el camino nuevo; false si se conservó el anterior
  /// (con un empalme desde la posición actual).
  final bool esNueva;

  /// Por qué se decidió así. Sólo para el log de diagnóstico.
  final String motivo;

  const DecisionRuta(this.ruta, this.esNueva, this.motivo);
}

/// ═══════════════════════════════════════════════════════════════════════════
/// SEGUIMIENTO DE RUTA
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Reemplaza la regla anterior "recalcular cuando el usuario se movió más de
/// 0.10 del plano". Esa regla tenía tres problemas:
///
///  1. El umbral estaba en unidades NORMALIZADAS: 0.10 son 1,2 m en un plano
///     de 12 m y 5 m en uno de 50 m. En un plano chico, correrse una celda no
///     recalculaba; en uno grande se podía ir 5 m fuera del camino sin que
///     pasara nada.
///  2. No miraba si el usuario estaba SOBRE la ruta o no. Caminando bien por
///     el camino se recalculaba igual, cada tanto, sin necesidad; y parado a
///     una celda del camino no se recalculaba nunca.
///  3. Entre recálculos, la indicación apuntaba desde la posición real a la
///     próxima esquina de la ruta vieja. A una celda de distancia eso es una
///     diagonal: "Girá a la izquierda, 1 metro" para volver a un camino que
///     ya no tiene sentido seguir.
///
/// Ahora hay tres reglas:
///
///  • EN RUTA → no se recalcula nada. El camino se va consumiendo a medida
///    que el usuario avanza ([ubicar] dice hasta dónde llegó).
///  • FUERA DE RUTA de forma sostenida → se calcula un camino desde donde
///    está y [decidir] elige entre ese camino y el que se venía siguiendo.
///  • Mientras tanto, y siempre que el desvío esté dentro del error del
///    posicionamiento, la indicación se da como si el usuario estuviera
///    parado sobre el camino ([guia]): no se le pide un paso al costado por
///    una diferencia que el BLE no puede medir.
///
/// Todo acá es geometría sobre la lista de celdas; no hay estado ni Flutter.
/// El estado (cuánto hace que está fuera de ruta, cuándo se recalculó) vive
/// en la pantalla de navegación.
class SeguidorRuta {
  /// Desvío (m) hasta el cual el usuario cuenta como "sobre la ruta".
  ///
  /// Con celdas de 1 m sólo cumple la celda exacta del camino (la vecina ya
  /// está a 1 m). Con celdas de 0,5 m entran también las vecinas inmediatas:
  /// medio metro está muy por debajo de lo que el BLE puede distinguir, y
  /// recalcular por eso sería recalcular por ruido.
  static const double toleranciaEnRutaMetros = 0.75;

  /// Desvío (m) hasta el cual la indicación se calcula desde el camino y no
  /// desde la posición real. Es del orden del error del posicionamiento.
  static const double toleranciaProyeccionMetros = 1.5;

  /// Tramo de ruta (m), contado desde su inicio, donde se busca al usuario.
  /// La ruta arranca siempre en el usuario, así que no hace falta mirar más
  /// lejos; y mirar toda la ruta haría que, en un camino en U, el usuario
  /// "saltara" al tramo de vuelta sólo por pasarle cerca.
  static const double ventanaMetros = 8.0;

  /// Separación (m) hasta la cual un camino nuevo se considera EL MISMO
  /// camino, corrido. Dos celdas de 1 m, con margen para las diagonales.
  static const double separacionMismaRutaMetros = 2.5;

  /// Lo mínimo (m) que tiene que ahorrar un camino DISTINTO frente a volver
  /// al anterior para que se lo adopte. Es la histéresis que evita que la
  /// ruta salte entre dos alternativas parecidas: como el posicionamiento
  /// tiene ~1,5 m de error, y correrse d metros hacia el otro lado de un
  /// obstáculo cambia la cuenta en 2·d, con menos de 3 m el ruido solo
  /// alcanzaría para dar vuelta la decisión.
  static const double ahorroMinimoMetros = 3.0;

  // ── Geometría básica ──────────────────────────────────────────────────────

  static double _metros(Offset a, Offset b, GrillaNav g) {
    final dx = (a.dx - b.dx) * g.metrosX;
    final dy = (a.dy - b.dy) * g.metrosY;
    return sqrt(dx * dx + dy * dy);
  }

  /// Clave entera de la celda que contiene a [p] (para comparar celdas sin
  /// depender de igualdad exacta entre doubles).
  static int claveCelda(Offset p, GrillaNav g) =>
      g.indiceX(p.dx) * g.celdasY + g.indiceY(p.dy);

  /// Largo del camino en metros (cantidad de pasos × lado de celda).
  static double longitudMetros(List<Offset> ruta, GrillaNav g) =>
      ruta.length < 2 ? 0.0 : (ruta.length - 1) * g.tamCeldaMetros;

  // ── Dónde está el usuario ─────────────────────────────────────────────────

  /// Ubica a [posicion] sobre [ruta]. Sólo mira el primer tramo de la ruta
  /// ([ventanaMetros]). Ante un empate gana la celda más avanzada, para que
  /// el progreso nunca retroceda por un empate.
  static UbicacionEnRuta ubicar(
    List<Offset> ruta,
    Offset posicion,
    GrillaNav g,
  ) {
    if (ruta.isEmpty) return const UbicacionEnRuta(0, double.infinity, false);
    final celda = g.centroDeCelda(posicion);
    final tam = g.tamCeldaMetros > 0 ? g.tamCeldaMetros : 1.0;
    final ventana = min(ruta.length, max(8, (ventanaMetros / tam).ceil() + 1));

    int mejor = 0;
    double dMejor = double.infinity;
    for (int i = 0; i < ventana; i++) {
      final d = _metros(ruta[i], celda, g);
      if (d <= dMejor) {
        dMejor = d;
        mejor = i;
      }
    }
    return UbicacionEnRuta(mejor, dMejor, dMejor <= toleranciaEnRutaMetros);
  }

  // ── Qué indicarle ─────────────────────────────────────────────────────────

  /// Índice de la próxima esquina del camino a partir de [idx]: la última
  /// celda del tramo recto que sale de [idx]. Si [idx] es la última celda,
  /// devuelve [idx].
  static int _proximaEsquina(List<Offset> ruta, int idx) {
    if (idx >= ruta.length - 1) return ruta.length - 1;
    Offset signo(Offset v) => Offset(v.dx.sign, v.dy.sign);
    final dir = signo(ruta[idx + 1] - ruta[idx]);
    int j = idx;
    while (j < ruta.length - 1 && signo(ruta[j + 1] - ruta[j]) == dir) {
      j++;
    }
    return j;
  }

  /// Tramo a indicar: hacia la próxima esquina del camino y, si el usuario
  /// está dentro de [toleranciaProyeccionMetros], medido DESDE el camino.
  ///
  /// POR QUÉ DESDE EL CAMINO: la indicación tiene cuatro valores (derecho,
  /// derecha, izquierda, media vuelta) y el corte entre "derecho" y "girá"
  /// está en 30°. Parado a una celda del camino y con la esquina a dos celdas
  /// el ángulo real ya es de 27°; con la esquina a una celda, 45°. O sea que
  /// un error de UNA celda —menos que la precisión del sistema— alcanzaba
  /// para convertir un "Seguí derecho" en un "Girá", y después de vuelta.
  /// Midiendo desde el camino, la indicación es la dirección del tramo y no
  /// depende de ese error.
  static TramoGuiado guia(List<Offset> ruta, Offset posicion, GrillaNav g) {
    if (ruta.isEmpty) return TramoGuiado(posicion, posicion);
    final u = ubicar(ruta, posicion, g);
    // Última celda: se apunta al final desde la posición real (el tramo ya
    // no tiene dirección propia).
    if (u.indice >= ruta.length - 1) return TramoGuiado(posicion, ruta.last);
    final esquina = ruta[_proximaEsquina(ruta, u.indice)];
    final desde = u.desvioMetros <= toleranciaProyeccionMetros
        ? ruta[u.indice]
        : posicion;
    return TramoGuiado(desde, esquina);
  }

  // ── Camino nuevo o camino viejo ───────────────────────────────────────────

  /// Mayor distancia (m) de una celda de [nueva] a la celda más cercana de
  /// [vieja]. Corta apenas supera [corte] (no hace falta el valor exacto,
  /// sólo saber si se pasa).
  static double separacionMaxima(
    List<Offset> nueva,
    List<Offset> vieja,
    GrillaNav g, {
    double corte = double.infinity,
  }) {
    double peor = 0.0;
    for (final n in nueva) {
      double minimo = double.infinity;
      for (final v in vieja) {
        final d = _metros(n, v, g);
        if (d < minimo) {
          minimo = d;
          if (minimo <= peor) break; // ya no puede empeorar el máximo
        }
      }
      if (minimo > peor) {
        peor = minimo;
        if (peor > corte) return peor;
      }
    }
    return peor;
  }

  /// Decide qué ruta queda vigente después de recalcular.
  ///
  /// - [nueva]: el camino recién calculado desde la posición actual.
  /// - [vieja]: lo que quedaba por recorrer del camino anterior (null si no
  ///   había).
  /// - [buscarCamino]: el pathfinder, para calcular el empalme con la ruta
  ///   vieja cuando hace falta (sólo en el caso 4).
  ///
  /// Casos, en orden:
  ///
  ///  1. No había ruta, o el objetivo cambió → la nueva.
  ///  2. La nueva es la vieja CORRIDA (nunca se aleja más de
  ///     [separacionMismaRutaMetros]) → la nueva. Es el caso típico: el
  ///     usuario quedó una o dos celdas al costado y el camino pasa a salir
  ///     desde donde está, sin hacerlo volver.
  ///  3. La nueva ES la vieja con un tramo adelante para llegar a ella (el
  ///     usuario quedó atrás o se alejó, y lo óptimo es justamente volver a
  ///     la altura donde la dejó) → la nueva.
  ///  4. La nueva va POR OTRO LADO. Se calcula cuánto costaría volver a la
  ///     vieja (empalme + lo que quedaba) y se adopta la nueva sólo si
  ///     ahorra [ahorroMinimoMetros] o más. Si no, se conserva la vieja con
  ///     su empalme: el recorrido no cambia por una diferencia que puede ser
  ///     ruido de posición.
  static Future<DecisionRuta> decidir({
    required List<Offset> nueva,
    required List<Offset>? vieja,
    required GrillaNav grilla,
    required Future<List<Offset>?> Function(Offset desde, Offset hasta)
        buscarCamino,
  }) async {
    if (vieja == null || vieja.isEmpty || nueva.isEmpty) {
      return DecisionRuta(nueva, true, 'no había ruta');
    }
    if (claveCelda(vieja.last, grilla) != claveCelda(nueva.last, grilla)) {
      return DecisionRuta(nueva, true, 'cambió el objetivo');
    }

    // 2) ¿Es la misma ruta, corrida?
    final sep = separacionMaxima(
      nueva,
      vieja,
      grilla,
      corte: separacionMismaRutaMetros,
    );
    if (sep <= separacionMismaRutaMetros) {
      return DecisionRuta(
        nueva,
        true,
        'misma ruta corrida (separación ${sep.toStringAsFixed(1)} m)',
      );
    }

    // Índice en la ruta vieja de cada una de sus celdas.
    final indiceEnVieja = <int, int>{};
    for (int i = 0; i < vieja.length; i++) {
      indiceEnVieja[claveCelda(vieja[i], grilla)] = i;
    }

    // Celda de la ruta vieja más cercana a donde está el usuario ahora.
    final origen = nueva.first;
    int cercana = 0;
    double dCercana = double.infinity;
    for (int i = 0; i < vieja.length; i++) {
      final d = _metros(vieja[i], origen, grilla);
      if (d <= dCercana) {
        dCercana = d;
        cercana = i;
      }
    }

    // 3) ¿La nueva vuelve a la vieja y sigue por ella hasta el final?
    // Tiene que entrar a la vieja ANTES de pasar su punto más cercano: si
    // entra más adelante (por ejemplo recién llegando al destino, donde dos
    // caminos distintos siempre terminan juntándose) no es "volver", es ir
    // por otro lado, y eso lo resuelve el caso 4.
    for (int i = 0; i < nueva.length; i++) {
      final k = indiceEnVieja[claveCelda(nueva[i], grilla)];
      if (k == null) continue;
      if (k <= cercana && nueva.length - i == vieja.length - k) {
        bool igual = true;
        for (int j = 1; j < nueva.length - i; j++) {
          if (claveCelda(nueva[i + j], grilla) !=
              claveCelda(vieja[k + j], grilla)) {
            igual = false;
            break;
          }
        }
        if (igual) {
          return DecisionRuta(nueva, true, 'vuelve a la ruta anterior');
        }
      }
      break; // sólo interesa el primer punto de contacto
    }

    // 4) Va por otro lado: ¿cuánto cuesta volver a la vieja?
    final empalme = await buscarCamino(origen, vieja[cercana]);
    if (empalme == null || empalme.isEmpty) {
      return DecisionRuta(nueva, true, 'no se puede volver a la ruta anterior');
    }

    // El empalme se corta en la PRIMERA celda de la ruta vieja que toque
    // (puede tocarla antes de llegar a la más cercana en línea recta) y desde
    // ahí se sigue por la vieja.
    final mantenida = <Offset>[];
    int? contacto;
    for (final c in empalme) {
      mantenida.add(c);
      final k = indiceEnVieja[claveCelda(c, grilla)];
      if (k != null) {
        contacto = k;
        break;
      }
    }
    if (contacto == null) {
      return DecisionRuta(nueva, true, 'el empalme no llega a la ruta anterior');
    }
    mantenida.addAll(vieja.sublist(contacto + 1));

    final ahorro =
        longitudMetros(mantenida, grilla) - longitudMetros(nueva, grilla);
    if (ahorro >= ahorroMinimoMetros) {
      return DecisionRuta(
        nueva,
        true,
        'camino distinto, ahorra ${ahorro.toStringAsFixed(1)} m',
      );
    }
    return DecisionRuta(
      mantenida,
      false,
      'se mantiene la ruta (el camino distinto sólo ahorra '
      '${ahorro.toStringAsFixed(1)} m)',
    );
  }
}