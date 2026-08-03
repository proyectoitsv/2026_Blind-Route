import 'dart:math';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show debugPrint;
import 'calibracion_model.dart';
import 'grilla_nav.dart';

/// Modelo log-distancia AJUSTADO para un beacon concreto: ordenada al origen
/// ([txPower], RSSI a 1 m) y pendiente ([n], exponente de perdida).
///
/// -- POR QUE HACE FALTA AJUSTAR n Y NO SOLO txPower ------------------------
/// El modelo es `rssi = txPower - 10*n*log10(d)`. Tiene DOS grados de libertad
/// y la calibracion anterior estimaba solo uno: fijaba n = 2.7 y despejaba
/// txPower en cada punto, para despues PROMEDIAR los txPower obtenidos. Si el
/// n real del sitio no es 2.7, cada punto de calibracion devuelve un txPower
/// distinto (absorbe el error de pendiente a SU distancia) y el promedio solo
/// acierta a la distancia media de las calibraciones.
///
/// El efecto es una COMPRESION del rango dinamico de las distancias: si el n
/// modelado es mayor que el real, `d_est = d_real^(n_real/n)`, o sea que las
/// distancias cortas se INFLAN y las largas se ACHICAN. Medido con n_real =
/// 2.0 y calibraciones a 2/5/8 m:
///   d_real 0.3 m -> 0.60 m (+100 %)   ...   d_real 20 m -> 13.4 m (-33 %)
/// Y eso es exactamente el sintoma doble reportado en campo:
///   - parado JUNTO a un beacon el rango minimo estimado ronda 1 m, asi que la
///     multilateracion nunca puede poner al usuario encima del beacon;
///   - FUERA de la nube de beacons todos los rangos vienen achicados, asi que
///     la solucion que mejor los explica cae DENTRO de la nube.
/// No es un bug de la trilateracion: la trilateracion resuelve correctamente
/// una geometria que le llega deformada.
///
/// Con tres o mas calibraciones a distancias distintas se pueden ajustar AMBOS
/// parametros por minimos cuadrados sobre `rssi` vs `log10(d)`, que es lineal.
/// Sobre los datos del ejemplo la regresion recupera n = 2.00 y txPower = -60
/// exactos, y el error de rango se vuelve nulo en todo el recorrido.
class ModeloRangoBeacon {
  /// RSSI de referencia a 1 m (dBm).
  final double txPower;

  /// Exponente de perdida de propagacion.
  final double n;

  /// `true` si [n] salio de una regresion real; `false` si es el valor por
  /// defecto porque no habia calibraciones suficientes.
  final bool ajustado;

  /// Cantidad de puntos de calibracion usados en el ajuste.
  final int puntos;

  const ModeloRangoBeacon({
    required this.txPower,
    required this.n,
    this.ajustado = false,
    this.puntos = 0,
  });

  /// Distancia (m) para un RSSI ya filtrado.
  double distancia(double rssiFiltrado) {
    if (rssiFiltrado >= 0) return 0.1;
    final d = pow(10.0, (txPower - rssiFiltrado) / (10.0 * n)).toDouble();
    return d.clamp(0.1, 30.0);
  }
}

class ProcesadorSenal {
  // ─── VENTANA DE MEDIANAS ──────────────────────────────────────────────────
  //
  // Mediana truncada sobre ventana deslizante. Más robusta que Kalman para
  // ruido bimodal/asimétrico del multipath BLE.
  //
  // _tamVentana: ventana de exactamente 3 s de señal. Con emisión a 160 ms/beacon
  //   (≈6,25 Hz) → ceil(3000 / 160) = 19 muestras. Subir en entornos con
  //   hormigón/metal si se quiere más suavizado (a costa de latencia).
  // _corteMediana: descarta 20% en cada extremo antes de promediar.

  static const int _tamVentana = 19;
  static const double _corteMediana = 0.20;

  /// Ventana mínima cuando el usuario está caminando: 7 muestras ≈ 1,1 s.
  /// La ventana larga de 3 s da mucha estabilidad con el usuario parado, pero
  /// su retardo de grupo (~1,5 s) es la MAYOR fuente de latencia del pipeline:
  /// a 1,2 m/s son ~1,8 m de atraso antes de que la posición siquiera entre al
  /// filtro. Con el usuario en movimiento conviene resignar suavizado —el
  /// filtro One Euro ya se encarga— a cambio de reducir ese retardo a ~0,55 s.
  static const int _ventanaMin = 7;

  final Map<String, List<double>> _ventanaRssi = {};
  final Map<String, double> _varianzaRssi = {};

  /// Cantidad de muestras (las más recientes del buffer) que efectivamente se
  /// promedian. La controla [ajustarPorMovimiento].
  int _ventanaEfectiva = _tamVentana;

  int get ventanaEfectiva => _ventanaEfectiva;

  /// Acorta la ventana de mediana a medida que el usuario se mueve.
  /// [factor]: 0 = quieto (ventana completa, máxima estabilidad),
  ///           1 = caminando (ventana mínima, mínima latencia).
  /// El buffer sigue guardando [_tamVentana] muestras: solo cambia cuántas se
  /// usan, así volver al estado "quieto" recupera el suavizado al instante,
  /// sin tener que re-llenar nada.
  void ajustarPorMovimiento(double factor) {
    final f = factor.clamp(0.0, 1.0);
    final v = (_tamVentana + (_ventanaMin - _tamVentana) * f).round();
    _ventanaEfectiva = v.clamp(_ventanaMin, _tamVentana);
  }

  // ─── MODELO DE DISTANCIA ──────────────────────────────────────────────────
  //
  // _txPower: RSSI de referencia a 1 m, calibrado = -55 dBm (rango aceptable
  //   por beacon: -50 a -60 dBm). Es la *ordenada al origen* del modelo log.
  //   Para calibración por beacon usar rssiADistanciaConTx(rssi, txPower).
  //
  // _pathLossExponent: es la *pendiente* del modelo y depende del entorno, no
  //   de la referencia de 1 m. La calibración 1 m = -55 dBm fija txPower pero
  //   NO altera n, así que 2.7 (interior típico) sigue siendo el valor correcto.
  //   2.0 = pasillo despejado  |  2.5 = oficina abierta
  //   2.7 = interior típico    |  3.0 = varias paredes
  //   3.5 = hormigón/subterráneo

  static const double _txPower = -55.0;
  static const double _pathLossExponent = 2.7;

  /// Exponente de pérdida de propagación (n) del modelo log-distancia. Expuesto
  /// para que la calibración use el mismo valor al despejar txPower.
  static double get pathLossExponent => _pathLossExponent;

  static double rssiADistanciaConTx(double rssiFiltrado, double txPower) {
    if (rssiFiltrado >= 0) return 0.1;
    final d = pow(10.0, (txPower - rssiFiltrado) / (10.0 * _pathLossExponent))
        .toDouble();
    return d.clamp(0.1, 30.0);
  }

  /// Devuelve el txPower ajustado para [mac] promediando todas las calibraciones
  /// disponibles que tienen una lectura para ese beacon.
  /// Si no hay calibraciones, devuelve [txPowerDefault].
  static double txPowerCalibrado(
    String mac,
    List<CalibracionRegistro> calibraciones, {
    double txPowerDefault = _txPower,
  }) {
    final valores = calibraciones
        .where((c) => c.txPowerAjustado.containsKey(mac))
        .map((c) => c.txPowerAjustado[mac]!)
        .toList();
    if (valores.isEmpty) return txPowerDefault;
    return valores.reduce((a, b) => a + b) / valores.length;
  }

  // ─── FILTRADO PRINCIPAL ───────────────────────────────────────────────────

  double? filtrarYPromediar(String mac, int rssiActual) {
    if (rssiActual > -20 || rssiActual < -110) return null;

    _ventanaRssi.putIfAbsent(mac, () => []);
    final v = _ventanaRssi[mac]!;
    v.add(rssiActual.toDouble());
    if (v.length > _tamVentana) v.removeAt(0);
    // Mínimo de muestras antes de devolver un valor: 25% de la ventana
    // (≈ ceil(19 * 0.25) = 5 muestras ≈ 0,8 s). Fórmula, no hardcodeado:
    // escala automáticamente si se cambia _tamVentana.
    final minMuestras = (_tamVentana * 0.25).ceil();
    if (v.length < minMuestras) return null;

    // Solo las N muestras más recientes (N = ventana efectiva según movimiento).
    final desde = v.length > _ventanaEfectiva ? v.length - _ventanaEfectiva : 0;
    final usadas = desde == 0 ? v : v.sublist(desde);

    // Hot path: se ejecuta por cada beacon en cada callback BLE (~6 Hz × N
    // beacons). Se evitan las asignaciones de sublist() y map()/reduce()
    // recorriendo el rango interior con índices directos. El resultado numérico
    // (media truncada + varianza sobre el interior) es idéntico al anterior.
    final ordenados = List<double>.from(usadas)..sort();
    final corte =
        (usadas.length * _corteMediana).round().clamp(1, usadas.length ~/ 3);
    final hasta = ordenados.length - corte;
    final cuenta = hasta - corte;

    double suma = 0;
    for (int i = corte; i < hasta; i++) {
      suma += ordenados[i];
    }
    final media = suma / cuenta;

    double sumaCuadrados = 0;
    for (int i = corte; i < hasta; i++) {
      final dif = ordenados[i] - media;
      sumaCuadrados += dif * dif;
    }
    _varianzaRssi[mac] = (sumaCuadrados / cuenta).clamp(0.1, 999.0);

    return media;
  }

  double varianzaBeacon(String mac) => _varianzaRssi[mac] ?? 999.0;

  // --- FINGERPRINTING DE PUNTOS CLAVE ---------------------------------------

  /// Beacons en comun (fingerprint vs lectura viva) para considerar valida una
  /// comparacion. Con menos de 3 el patron no identifica una celda: cualquier
  /// punto del pasillo da parecido.
  static const int _fpMinComunes = 3;

  /// Distancia robusta (dB) por debajo de la cual la coincidencia se considera
  /// perfecta.
  ///
  /// CALIBRADO CONTRA EL FADING REAL, no contra el ruido termico. A 2.4 GHz la
  /// longitud de onda es 12.5 cm, asi que moverse 30 cm —sin salir de la
  /// celda— cambia por completo la interferencia multicamino y puede correr el
  /// RSSI de un beacon 5 a 10 dB. Y no es algo que el promediado temporal
  /// arregle: el patron de fading es una propiedad del PUNTO, no del instante;
  /// parado dentro de un nulo de interferencia, se promedia el nulo.
  ///
  /// Medido con desviacion de 5 dB por beacon, parado en la celda CORRECTA:
  ///   metrica RMS simple  -> mediana 5.68 dB, percentil 90 8.71 dB
  ///   metrica robusta     -> mediana 3.85 dB, percentil 90 6.68 dB
  /// El corte anterior de 6.0 dB rechazaba mas o menos la mitad de las
  /// coincidencias buenas. Estos valores dejan pasar hasta el percentil 90.
  static const double _fpDbBueno = 4.0;

  /// Distancia robusta (dB) por encima de la cual no hay coincidencia alguna.
  ///
  /// Es un FILTRO DE COHERENCIA, no el discriminador de posicion: sirve para
  /// descartar un patron absurdo (otro piso, beacon caido), no para decidir en
  /// que celda esta el usuario. Quien discrimina la posicion es la combinacion
  /// de [_fpMargenDb] (comparacion relativa entre puntos clave, donde el ruido
  /// del vector vivo se cancela porque es el mismo en ambas comparaciones) y
  /// el radio espacial que aplica quien consume esto. Ver la nota grande en
  /// [compararFingerprints] sobre por que un umbral absoluto no puede resolver
  /// metros con este nivel de fading.
  static const double _fpDbMalo = 10.0;

  /// Ventaja minima (dB) del mejor fingerprint sobre el mejor de OTRA celda.
  /// Sin este margen, dos puntos clave parecidos se turnarian el match y la
  /// posicion saltaria entre ellos.
  static const double _fpMargenDb = 2.0;

  /// Piso de RSSI para que una lectura viva entre en la comparacion.
  static const double _fpRssiMinimo = -95.0;

  /// Convierte una distancia robusta en dB a confianza `[0,1]`.
  ///
  /// Expuesto para que el consumidor pueda suavizar el rms en el tiempo antes
  /// de convertirlo: promediar la distancia y despues mapear es mas estable que
  /// promediar confianzas ya saturadas en 0 o en 1.
  static double confianzaFingerprint(double rms) =>
      ((_fpDbMalo - rms) / (_fpDbMalo - _fpDbBueno)).clamp(0.0, 1.0);

  /// Compara las [lecturasVivas] (mac -> RSSI filtrado) contra los
  /// fingerprints guardados y devuelve la mejor coincidencia, o `null`.
  ///
  /// ── POR QUE ESTO NO ES "OTRA TRILATERACION" ───────────────────────────────
  /// La multilateracion convierte cada RSSI en una DISTANCIA usando el modelo
  /// log y despues resuelve una geometria. Eso hereda todos los errores del
  /// modelo, y muy cerca de un beacon el modelo es justamente donde peor anda
  /// (el RSSI se satura y deja de seguir la ley logaritmica).
  ///
  /// El fingerprinting no estima ninguna distancia: compara el VECTOR completo
  /// de RSSI contra un patron medido en esa misma celda. Si el patron coincide,
  /// se sabe donde esta el usuario sin haber modelado nada. Por eso es la
  /// herramienta correcta para las celdas singulares —una esquina donde hay que
  /// doblar, una puerta— donde acertar importa mas que el promedio.
  ///
  /// ── LA METRICA ES DIFERENCIAL Y ROBUSTA ───────────────────────────────────
  /// Se descuenta primero el desplazamiento COMUN (la MEDIANA de las
  /// diferencias) y despues se descarta el beacon que mas se aparta, antes de
  /// calcular el RMS con los que quedan. Las dos cosas atacan fuentes de error
  /// distintas:
  ///
  /// 1. El offset comun es la POSTURA: el cuerpo, la mano y la altura del
  ///    telefono atenuan todos los beacons a la vez. Medido, una atenuacion
  ///    uniforme de 10 dB daba RMS 10 dB (match perdido) y con la resta da 0.
  ///
  /// 2. Descartar el peor beacon es contra el FADING PROFUNDO. El multicamino
  ///    afecta a cada beacon de forma independiente, y basta un beacon metido
  ///    en un nulo de interferencia para arruinar un RMS (que eleva al
  ///    cuadrado). Medido con 5 dB de desviacion por beacon, parado en la
  ///    celda correcta: RMS simple mediana 5.68 dB, robusta 3.85 dB.
  ///
  /// Es el mismo criterio que ya usa esta clase para el RSSI (mediana truncada)
  /// y que usa el solver para los rangos (perdida de Huber): no dejar que una
  /// sola medicion mala decida.
  ///
  /// ── LO QUE ESTA METRICA NO PUEDE HACER ────────────────────────────────────
  /// Con fading de 5 dB por beacon, la distancia robusta apenas separa la celda
  /// correcta de una a 6 m (mediana 3.85 vs 4.94 dB, con solapamiento enorme).
  /// Promediar 15 ciclos deja todavia ~50 % de solape. La conclusion medida es
  /// que NINGUN umbral absoluto en dB puede resolver metros: la senal de
  /// distancia es mas chica que el fading.
  ///
  /// Lo que si discrimina es la comparacion RELATIVA: al enfrentar el MISMO
  /// vector vivo contra dos patrones, el fading del vector vivo es identico en
  /// ambas cuentas y se cancela en la diferencia. De ahi que se exija que el
  /// ganador le saque [_fpMargenDb] al mejor candidato de OTRA celda: si dos
  /// puntos clave dan parecido, la respuesta honesta es "no se". Y de ahi
  /// tambien que quien consume esto deba acotar el resultado con un radio
  /// espacial alrededor de la posicion que ya calculo la multilateracion: el
  /// fingerprint refina el ultimo metro, no ubica desde cero.
  static CoincidenciaFingerprint? compararFingerprints({
    required Map<String, double> lecturasVivas,
    required List<CalibracionRegistro> calibraciones,
  }) {
    CoincidenciaFingerprint? mejor;
    double mejorDb = double.infinity;
    double mejorOtraCeldaDb = double.infinity;

    for (final cal in calibraciones) {
      if (!cal.esFingerprint) continue;

      // Diferencias vivo - guardado sobre los beacons comunes.
      final difs = <double>[];
      for (final lectura in cal.lecturasBle) {
        final mac = lectura['mac'] as String?;
        final rssiGuardado = (lectura['rssi'] as num?)?.toDouble();
        if (mac == null || rssiGuardado == null) continue;
        final viva = lecturasVivas[mac];
        if (viva == null || viva <= _fpRssiMinimo || viva >= 0) continue;
        difs.add(viva - rssiGuardado);
      }
      final comunes = difs.length;
      if (comunes < _fpMinComunes) continue;

      // Offset comun robusto (mediana, no media: la media se corre si un
      // beacon esta en fading profundo).
      final ordenadas = List<double>.from(difs)..sort();
      final mitad = ordenadas.length ~/ 2;
      final mediana = ordenadas.length.isOdd
          ? ordenadas[mitad]
          : (ordenadas[mitad - 1] + ordenadas[mitad]) / 2.0;

      // Desvios respecto del offset comun, de mayor a menor.
      final desvios = difs.map((d) => (d - mediana).abs()).toList()
        ..sort((a, b) => b.compareTo(a));

      // Se descarta el peor beacon (fading profundo) siempre que queden al
      // menos 3 para el calculo.
      final usados = desvios.length >= 4
          ? desvios.sublist(1)
          : desvios;

      double suma = 0;
      for (final d in usados) {
        suma += d * d;
      }
      final rms = sqrt(suma / usados.length);
      if (rms < mejorDb) {
        // El anterior mejor pasa a ser "el mejor de otra celda" solo si
        // efectivamente era otra celda.
        if (mejor != null &&
            (mejor.celdaIx != cal.celdaIx || mejor.celdaIy != cal.celdaIy)) {
          mejorOtraCeldaDb = mejorDb;
        }
        mejorDb = rms;
        mejor = CoincidenciaFingerprint(
          celdaIx: cal.celdaIx,
          celdaIy: cal.celdaIy,
          etiqueta: cal.etiqueta,
          distanciaDb: rms,
          confianza: confianzaFingerprint(rms),
          beaconsComunes: comunes,
        );
      } else if (mejor != null &&
          (mejor.celdaIx != cal.celdaIx || mejor.celdaIy != cal.celdaIy) &&
          rms < mejorOtraCeldaDb) {
        mejorOtraCeldaDb = rms;
      }
    }

    if (mejor == null || mejor.confianza <= 0) return null;
    if (mejorOtraCeldaDb.isFinite &&
        (mejorOtraCeldaDb - mejor.distanciaDb) < _fpMargenDb) {
      return null; // ambiguo entre dos puntos clave
    }
    return mejor;
  }

  // --- AJUSTE DEL MODELO DE RANGO POR BEACON --------------------------------

  /// Minimo de puntos de calibracion para intentar la regresion. Con 2 puntos
  /// la recta pasa exacta por ambos y cualquier error de medicion se convierte
  /// integro en error de pendiente; con 3 ya hay algo de promediado.
  static const int _minPuntosAjuste = 3;

  /// Expuesto para que la UI/los logs puedan decir cuantas calibraciones faltan.
  static int get minPuntosAjuste => _minPuntosAjuste;

  /// Separacion minima entre el punto mas cercano y el mas lejano, en decadas
  /// de distancia (0.3 ~ un factor 2). Si todas las calibraciones se tomaron a
  /// distancias parecidas la pendiente no esta observada, y ajustarla seria
  /// amplificar ruido: se cae al modelo por defecto.
  static const double _minRangoLog = 0.3;

  /// Limites fisicos de n. Fuera de esto la regresion vio mas ruido que senal
  /// (interferencia, cuerpo del operador, beacon mal posicionado en el plano).
  static const double _nMin = 1.5;
  static const double _nMax = 4.5;

  /// Distancia minima de un punto de calibracion para entrar en la regresion.
  /// Por debajo de ~0.5 m el modelo log deja de valer (campo cercano) y el RSSI
  /// se satura: esos puntos sesgan la pendiente.
  static const double _dMinAjuste = 0.5;

  /// Ajusta ([txPower], [n]) por beacon con minimos cuadrados sobre las
  /// calibraciones guardadas.
  ///
  /// Cada [CalibracionRegistro] aporta un punto por beacon: la celda donde
  /// estaba parado el operador da la distancia REAL al beacon, y `lecturasBle`
  /// el RSSI medido ahi. Eso es todo lo que hace falta para la regresion; los
  /// datos ya se venian guardando, solo no se estaban aprovechando.
  ///
  /// Si un beacon no tiene datos suficientes se devuelve el modelo por defecto
  /// (n fijo y el txPower promediado de [txPowerCalibrado]), o sea el
  /// comportamiento anterior: el ajuste nunca empeora el punto de partida.
  static Map<String, ModeloRangoBeacon> ajustarModelosRango({
    required List<CalibracionRegistro> calibraciones,
    required Map<String, Offset> posicionesBeacons,
    required GrillaNav grilla,
  }) {
    final modelos = <String, ModeloRangoBeacon>{};

    // Puntos (log10 d, rssi) por beacon.
    final puntos = <String, List<({double x, double y})>>{};
    for (final cal in calibraciones) {
      final cx = grilla.centroX(cal.celdaIx);
      final cy = grilla.centroY(cal.celdaIy);
      for (final lectura in cal.lecturasBle) {
        final mac = lectura['mac'] as String?;
        final rssi = (lectura['rssi'] as num?)?.toDouble();
        if (mac == null || rssi == null || rssi >= 0 || rssi <= -100) continue;
        final pos = posicionesBeacons[mac];
        if (pos == null) continue;
        final dxm = (pos.dx - cx) * grilla.metrosX;
        final dym = (pos.dy - cy) * grilla.metrosY;
        final d = sqrt(dxm * dxm + dym * dym);
        if (!d.isFinite || d < _dMinAjuste) continue;
        puntos.putIfAbsent(mac, () => []).add((x: log(d) / ln10, y: rssi));
      }
    }

    ModeloRangoBeacon porDefecto(String mac, int n) => ModeloRangoBeacon(
          txPower: txPowerCalibrado(mac, calibraciones),
          n: _pathLossExponent,
          puntos: n,
        );

    for (final mac in posicionesBeacons.keys) {
      final pts = puntos[mac] ?? const <({double x, double y})>[];

      if (pts.length < _minPuntosAjuste) {
        modelos[mac] = porDefecto(mac, pts.length);
        continue;
      }

      double minX = pts.first.x, maxX = pts.first.x;
      double sx = 0, sy = 0;
      for (final p in pts) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        sx += p.x;
        sy += p.y;
      }
      if (maxX - minX < _minRangoLog) {
        modelos[mac] = porDefecto(mac, pts.length);
        continue;
      }

      final mediaX = sx / pts.length, mediaY = sy / pts.length;
      double sxy = 0, sxx = 0;
      for (final p in pts) {
        final dx = p.x - mediaX;
        sxy += dx * (p.y - mediaY);
        sxx += dx * dx;
      }
      if (sxx < 1e-9) {
        modelos[mac] = porDefecto(mac, pts.length);
        continue;
      }

      // rssi = tx + pendiente*log10(d),  con pendiente = -10*n.
      final pendiente = sxy / sxx;
      final nAjustado = -pendiente / 10.0;
      if (!nAjustado.isFinite || nAjustado < _nMin || nAjustado > _nMax) {
        debugPrint('[Rango] $mac: n ajustado fuera de rango '
            '(${nAjustado.toStringAsFixed(2)}); se usa el modelo por defecto.');
        modelos[mac] = porDefecto(mac, pts.length);
        continue;
      }

      final txAjustado = mediaY - pendiente * mediaX;
      modelos[mac] = ModeloRangoBeacon(
        txPower: txAjustado,
        n: nAjustado,
        ajustado: true,
        puntos: pts.length,
      );
      debugPrint('[Rango] $mac: n=${nAjustado.toStringAsFixed(2)} '
          'tx=${txAjustado.toStringAsFixed(1)} dBm '
          '(${pts.length} calibraciones)');
    }

    return modelos;
  }

  // ─── UTILIDADES ───────────────────────────────────────────────────────────

  void limpiar() {
    _ventanaRssi.clear();
    _varianzaRssi.clear();
    _ventanaEfectiva = _tamVentana;
  }
}

/// Resultado de comparar las lecturas actuales contra los fingerprints
/// guardados. Ver [ProcesadorSenal.compararFingerprints].
class CoincidenciaFingerprint {
  /// Celda del punto clave reconocido.
  final int celdaIx;
  final int celdaIy;

  /// Etiqueta que el operador le puso al punto clave (p. ej. "Esquina norte").
  final String? etiqueta;

  /// Distancia RMS en dB entre el patron guardado y el vector vivo.
  final double distanciaDb;

  /// Confianza en `[0,1]` derivada de [distanciaDb].
  final double confianza;

  /// Beacons que participaron de la comparacion.
  final int beaconsComunes;

  const CoincidenciaFingerprint({
    required this.celdaIx,
    required this.celdaIy,
    required this.etiqueta,
    required this.distanciaDb,
    required this.confianza,
    required this.beaconsComunes,
  });
}