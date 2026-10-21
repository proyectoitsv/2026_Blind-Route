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

/// Para qué lado dobla el camino en una esquina, visto por quien lo recorre.
enum SentidoGiro { izquierda, derecha }

/// Lo próximo que hay que hacer sobre la ruta: doblar en una esquina, o
/// llegar al final.
class Maniobra {
  /// Celda donde termina el tramo recto actual.
  final Offset esquina;

  /// Metros que faltan hasta [esquina], medidos por el camino.
  final double metros;

  /// Para qué lado se dobla ahí. Null si [esquina] es el final de la ruta.
  final SentidoGiro? giro;

  const Maniobra(this.esquina, this.metros, this.giro);

  bool get esFinal => giro == null;
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

  /// Cantidad de celdas que abarca [ventanaMetros].
  static int _ventanaCeldas(List<Offset> ruta, GrillaNav g) {
    final tam = g.tamCeldaMetros > 0 ? g.tamCeldaMetros : 1.0;
    return max(8, (ventanaMetros / tam).ceil() + 1);
  }

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
    final ventana = min(ruta.length, _ventanaCeldas(ruta, g));

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
  ///
  /// [avanceMetros]: cuánto más adelante se supone que está el usuario
  /// respecto de donde lo ubica el posicionamiento, que llega con atraso
  /// (ver el comentario de los giros anticipados en la pantalla de
  /// navegación). La indicación se calcula desde ahí.
  ///
  /// [comprometida]: esquina cuyo giro YA se le anunció al usuario. Mientras
  /// siga adelante en la ruta, la indicación se calcula como si ya estuviera
  /// parado en ella. Sin esto, alguien que empieza a doblar apenas escucha
  /// "girá a la izquierda" —todavía sin haber "llegado" a la esquina según
  /// el posicionamiento— recibiría un "girá a la derecha" para volver a
  /// enderezarse.
  static TramoGuiado guia(
    List<Offset> ruta,
    Offset posicion,
    GrillaNav g, {
    double avanceMetros = 0.0,
    Offset? comprometida,
  }) {
    if (ruta.isEmpty) return TramoGuiado(posicion, posicion);
    final u = ubicar(ruta, posicion, g);
    final enCamino = u.desvioMetros <= toleranciaProyeccionMetros;
    final ultimo = ruta.length - 1;

    // Posición "virtual" sobre la ruta: la medida, más el avance por atraso,
    // y nunca antes de una esquina cuyo giro ya se anunció. Sólo si el
    // usuario está sobre el camino: lejos de él no hay sobre qué avanzar.
    int indice = u.indice;
    if (enCamino) {
      final tam = g.tamCeldaMetros > 0 ? g.tamCeldaMetros : 1.0;
      indice = min(ultimo, indice + (avanceMetros / tam).round());
      if (comprometida != null) {
        final clave = claveCelda(comprometida, g);
        final tope = min(ruta.length, u.indice + _ventanaCeldas(ruta, g));
        for (int i = indice + 1; i < tope; i++) {
          if (claveCelda(ruta[i], g) == clave) {
            indice = i;
            break;
          }
        }
      }
    }

    // Última celda: se apunta al final desde la posición real (el tramo ya
    // no tiene dirección propia).
    if (indice >= ultimo) return TramoGuiado(posicion, ruta.last);
    final esquina = ruta[_proximaEsquina(ruta, indice)];
    return TramoGuiado(enCamino ? ruta[indice] : posicion, esquina);
  }

  /// Lo próximo que hay que hacer: en qué esquina termina el tramo recto en
  /// el que está el usuario, a cuántos metros, y para qué lado dobla ahí el
  /// camino (o si ahí termina la ruta). Null si no hay ruta o el usuario
  /// está lejos de ella.
  ///
  /// [posicionFina]: la posición SIN ajustar a la grilla, si se tiene. La
  /// distancia a la esquina sale de ella (medida a lo largo del tramo), así
  /// no avanza de a saltos de una celda: con celdas de 1 m y caminando a
  /// 0,9 m/s, cada salto son 1,1 s de diferencia en el momento del aviso.
  static Maniobra? proximaManiobra(
    List<Offset> ruta,
    Offset posicion,
    GrillaNav g, {
    Offset? posicionFina,
  }) {
    if (ruta.length < 2) return null;
    final u = ubicar(ruta, posicion, g);
    if (u.desvioMetros > toleranciaProyeccionMetros) return null;
    final ultimo = ruta.length - 1;
    if (u.indice >= ultimo) return Maniobra(ruta.last, 0.0, null);

    final j = _proximaEsquina(ruta, u.indice);
    final tam = g.tamCeldaMetros > 0 ? g.tamCeldaMetros : 1.0;
    double metros = (j - u.indice) * tam;

    if (posicionFina != null) {
      // Distancia a la esquina a lo largo del tramo (que es horizontal o
      // vertical). Se acota a ±1 celda de la medida por celdas, para que una
      // posición fina que todavía no "alcanzó" a la celda no la contradiga.
      final dxM = ((ruta[j].dx - posicionFina.dx) * g.metrosX).abs();
      final dyM = ((ruta[j].dy - posicionFina.dy) * g.metrosY).abs();
      final horizontal = (ruta[j].dx - ruta[j - 1].dx).abs() >
          (ruta[j].dy - ruta[j - 1].dy).abs();
      final fina = horizontal ? dxM : dyM;
      metros = fina.clamp(max(0.0, metros - tam), metros + tam).toDouble();
    }

    if (j >= ultimo) return Maniobra(ruta[j], metros, null);

    // Para qué lado dobla: producto cruz entre el tramo que llega y el que
    // sale. En pantalla el eje y crece hacia abajo, así que positivo es giro
    // horario = a la derecha de quien camina.
    final d1 = ruta[j] - ruta[j - 1];
    final d2 = ruta[j + 1] - ruta[j];
    final cruz = d1.dx.sign * d2.dy.sign - d1.dy.sign * d2.dx.sign;
    return Maniobra(
      ruta[j],
      metros,
      cruz > 0 ? SentidoGiro.derecha : SentidoGiro.izquierda,
    );
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