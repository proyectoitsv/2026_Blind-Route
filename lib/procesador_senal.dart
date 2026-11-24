// Procesamiento de la señal de los beacons.
//
// ProcesadorSenal suaviza el RSSI de cada beacon (media truncada en una
// ventana de tiempo que se acorta al caminar), lo convierte en distancia con el
// modelo log-distancia, ajusta ese modelo para cada beacon con las
// calibraciones (n y RSSI a 1 m, por mínimos cuadrados) y compara la lectura en
// vivo contra los puntos clave (fingerprints). ModeloRangoBeacon es el modelo
// ajustado de un beacon; CoincidenciaFingerprint, el resultado de comparar.

import 'dart:math';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show debugPrint;
import 'calibracion_model.dart';
import 'grilla_nav.dart';

/// Modelo log-distancia AJUSTADO para un beacon concreto: ordenada al origen
/// ([txPower], RSSI a 1 m) y pendiente ([n], exponente de pérdida).
///
/// -- POR QUÉ SE AJUSTA n Y NO SÓLO txPower ----------------------------------
/// El modelo es `rssi = txPower - 10*n*log10(d)` y tiene DOS incógnitas. Si n
/// queda fijo (2,7) y se despeja txPower en cada calibración, cada punto da un
/// txPower distinto (absorbe el error de pendiente a SU distancia) y el
/// promedio sólo acierta a la distancia media de las calibraciones.
///
/// El efecto es una COMPRESIÓN de las distancias: si el n del modelo es mayor
/// que el real, `d_est = d_real^(n_real/n)`, o sea que las distancias cortas
/// se INFLAN y las largas se ACHICAN. Con n_real = 2,0 y calibraciones a
/// 2/5/8 m:
///   d_real 0,3 m -> 0,60 m (+100 %)   ...   d_real 20 m -> 13,4 m (-33 %)
/// Y de ahí salen dos síntomas:
///   - parado JUNTO a un beacon el rango mínimo estimado ronda 1 m, así que la
///     multilateración nunca puede poner al usuario encima del beacon;
///   - FUERA de la nube de beacons todos los rangos vienen achicados, así que
///     la solución que mejor los explica cae DENTRO de la nube.
/// La multilateración resuelve bien; la geometría le llega deformada.
///
/// Con tres o más calibraciones a distancias distintas se ajustan AMBOS
/// parámetros por mínimos cuadrados sobre `rssi` vs `log10(d)`, que es una
/// recta (ver [ProcesadorSenal.ajustarModelosRango]). Sobre los datos del
/// ejemplo la regresión recupera n = 2,00 y txPower = -60 exactos.
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

  /// Distancia (m) para un RSSI ya filtrado: el modelo despejado,
  /// `d = 10^((txPower - rssi) / (10*n))`. Es la distancia 3D, la que
  /// recorre la señal. Se acota a 0,1–30 m: fuera de eso el modelo no vale.
  double distancia(double rssiFiltrado) {
    if (rssiFiltrado >= 0) return 0.1;
    final d = pow(10.0, (txPower - rssiFiltrado) / (10.0 * n)).toDouble();
    return d.clamp(0.1, 30.0);
  }
}

class ProcesadorSenal {
  // ─── VENTANA DE MEDIANAS ──────────────────────────────────────────────────
  //
  // Media truncada sobre una ventana deslizante: se ordenan las lecturas, se
  // descarta el 20 % de cada punta (_corteMediana) y se promedia el resto.
  // Aguanta mejor que un Kalman el ruido del BLE, que no es gaussiano: el
  // multicamino da caídas bruscas de 10 dB o más que una media común
  // arrastraría.
  //
  // ── LA VENTANA ES DE TIEMPO, NO DE LECTURAS ───────────────────────────────
  // El atraso que agrega una ventana es la mitad de su duración EN TIEMPO, y
  // cuánto duran N lecturas depende de cada cuánto emite el beacon y de
  // cuántos paquetes se pierden: 7 lecturas son 1,1 s con un beacon que emite
  // cada 160 ms y 7 s con uno que emite cada segundo (el valor de fábrica de
  // muchos). Con una ventana de N segundos, un beacon lento aporta menos
  // lecturas (más ruido), pero el atraso no cambia.
  //
  // La ventana con el usuario quieto es larga (estabilidad) y caminando corta
  // (su retardo es la MAYOR fuente de latencia del pipeline: con 3 s serían
  // ~1,5 s de atraso, ~1,8 m a paso normal). Las dos son regulables
  // ([configurarVentanas]): en la navegación las fija el panel de ajustes.

  static const double ventanaQuietoPorDefectoSeg = 3.0;
  static const double ventanaCaminandoPorDefectoSeg = 1.1;
  double _ventanaQuietoSeg = ventanaQuietoPorDefectoSeg;
  double _ventanaCaminandoSeg = ventanaCaminandoPorDefectoSeg;
  static const double _corteMediana = 0.20;

  /// Lecturas mínimas para devolver un valor. Se usan siempre al menos
  /// estas, aunque alguna sea más vieja que la ventana: con una o dos no hay
  /// mediana que valga.
  static const int _minMuestras = 3;

  /// Tope de lecturas guardadas por beacon, por si llegan muy seguido (o
  /// repetidas, como en la pantalla de configuración): acota el ordenamiento.
  static const int _maxMuestras = 60;

  /// Cambia la ventana (s) con el usuario quieto (que es también lo que
  /// guarda el buffer) y la ventana caminando.
  void configurarVentanas({
    required double quietoSeg,
    required double caminandoSeg,
  }) {
    final q = max(0.2, quietoSeg);
    final c = caminandoSeg.clamp(0.1, q).toDouble();
    _ventanaQuietoSeg = q;
    _ventanaCaminandoSeg = c;
    _ventanaEfectivaSeg = _ventanaEfectivaSeg.clamp(c, q).toDouble();
  }

  final Map<String, List<({DateTime t, double rssi})>> _ventanaRssi = {};
  final Map<String, double> _varianzaRssi = {};

  /// MACs que el pipeline considera relevantes (los beacons configurados del
  /// piso). Si está vacío se rastrean todas.
  ///
  /// El scan BLE ve TODOS los dispositivos del ambiente —celulares, TVs,
  /// auriculares, balizas ajenas— y el resultado de un MAC que no es beacon
  /// del piso nunca se usa. Sin esta lista, cada uno dejaría una entrada en
  /// [_ventanaRssi] y [_varianzaRssi] que nunca se limpia: en un lugar
  /// concurrido (una terminal, un shopping) es memoria y CPU (un sort por
  /// dispositivo ajeno en cada callback) que crece durante toda la sesión.
  Set<String> _macsRelevantes = const {};

  /// Declara qué MACs son beacons configurados. A partir de acá
  /// [filtrarYPromediar] ignora cualquier MAC ajeno, y se sueltan las entradas
  /// ya acumuladas que no correspondan a un beacon (p. ej. las que dejó
  /// sembradas el modo automático mientras todavía no sabía el piso).
  void definirBeaconsRelevantes(Iterable<String> macs) {
    _macsRelevantes = macs.toSet();
    if (_macsRelevantes.isEmpty) return;
    _ventanaRssi.removeWhere((mac, _) => !_macsRelevantes.contains(mac));
    _varianzaRssi.removeWhere((mac, _) => !_macsRelevantes.contains(mac));
  }

  /// Duración (s) de la ventana que efectivamente se promedia (las lecturas
  /// más recientes). La controla [ajustarPorMovimiento].
  double _ventanaEfectivaSeg = ventanaQuietoPorDefectoSeg;

  double get ventanaEfectivaSeg => _ventanaEfectivaSeg;

  /// Acorta la ventana de mediana a medida que el usuario se mueve.
  /// [factor]: 0 = quieto (ventana completa, máxima estabilidad),
  ///           1 = caminando (ventana mínima, mínima latencia).
  /// El buffer sigue guardando la ventana de quieto: solo cambia cuánto se
  /// usa, así volver al estado "quieto" recupera el suavizado al instante,
  /// sin tener que re-llenar nada.
  void ajustarPorMovimiento(double factor) {
    final f = factor.clamp(0.0, 1.0);
    _ventanaEfectivaSeg =
        _ventanaQuietoSeg + (_ventanaCaminandoSeg - _ventanaQuietoSeg) * f;
  }

  // ─── MODELO DE DISTANCIA POR DEFECTO ──────────────────────────────────────
  //
  // Lo que se usa cuando un beacon no tiene calibraciones suficientes para
  // ajustar su propio modelo (ver [ajustarModelosRango]).
  //
  // _txPower: RSSI a 1 m (-55 dBm; un beacon típico da entre -50 y -60). Es
  //   la *ordenada al origen* del modelo. Sólo se usa si el beacon no tiene
  //   ninguna calibración.
  //
  // _pathLossExponent: n, la *pendiente* del modelo. Depende del lugar, no del
  //   beacon:
  //   2.0 = pasillo despejado  |  2.5 = oficina abierta
  //   2.7 = interior típico    |  3.0 = varias paredes
  //   3.5 = hormigón/subterráneo

  static const double _txPower = -55.0;
  static const double _pathLossExponent = 2.7;

  /// Exponente de pérdida de propagación (n) del modelo log-distancia. Expuesto
  /// para que la calibración use el mismo valor al despejar txPower.
  static double get pathLossExponent => _pathLossExponent;

  // ─── ALTURAS ──────────────────────────────────────────────────────────────
  //
  // El plano es 2D y la señal viaja en 3D. La distancia que "ve" el RSSI es
  //   d = √(d_plano² + Δh²),   Δh = altura del beacon − altura del teléfono.
  // Usar d_plano (en la calibración o en el posicionamiento) equivale a
  // suponer Δh = 0. Con un beacon en el techo (Δh ≈ 1,4 m) eso deforma el
  // modelo de cada beacon: la regresión sobre d_plano da un n más
  // bajo que el real (2,0 → 1,53 en una simulación con calibraciones a 1, 3,
  // 6 y 10 m) y el rango queda inflado cerca del beacon (+0,8 m justo debajo)
  // y torcido lejos (−0,45 m a 4 m, +2 m a 12 m). Con beacons a alturas
  // DISTINTAS cada uno se deforma distinto, así que las circunferencias dejan
  // de cruzarse en un punto y la posición se corre. Un techo más alto puede
  // llevar el n ajustado por debajo de [_nMin]: entonces se descarta la
  // regresión y se usa el modelo por defecto, que es peor todavía.

  /// Altura (m sobre el piso) a la que se supone el teléfono: en la mano o en
  /// el pecho, tanto al calibrar como al navegar. Medida: el teléfono se lleva
  /// a ~1,1 m. Es fija y no se le pide a cada persona: en una simulación con 5 beacons en el techo, llevar el
  /// teléfono a 0,8 o a 1,6 m suma 0,1–0,15 m de error medio (0,4 m en el
  /// peor caso, justo debajo de un beacon), mucho menos que el ruido del
  /// RSSI. La que más pesa es la del admin al calibrar, porque deforma el
  /// modelo para todos.
  static const double alturaTelefonoM = 1.1;

  /// Altura del beacon menos la del teléfono (m). Null (beacon sin altura
  /// indicada) se toma como "a la altura del teléfono": 0, lo de antes.
  static double alturaRelativa(double? alturaBeacon) =>
      (alturaBeacon == null || !alturaBeacon.isFinite)
          ? 0.0
          : alturaBeacon - alturaTelefonoM;

  /// Distancia real (3D, en m) entre el teléfono y un beacon separados
  /// [dxm] × [dym] metros sobre el plano.
  static double distanciaReal(double dxm, double dym, double? alturaBeacon) {
    final dz = alturaRelativa(alturaBeacon);
    return sqrt(dxm * dxm + dym * dym + dz * dz);
  }

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

  /// Agrega una lectura de [mac] y devuelve su RSSI suavizado (dBm), o null
  /// si todavía no hay [_minMuestras] lecturas o el MAC no es un beacon del
  /// piso. Usa las lecturas de la ventana efectiva (ver
  /// [ajustarPorMovimiento]): las ordena, descarta el 20 % de cada punta y
  /// promedia el resto. Deja también la varianza de esas lecturas
  /// ([varianzaBeacon]).
  double? filtrarYPromediar(String mac, int rssiActual) {
    // MACs que no son beacons del piso: se descartan antes de guardar nada
    // (ver [definirBeaconsRelevantes]).
    if (_macsRelevantes.isNotEmpty && !_macsRelevantes.contains(mac)) {
      return null;
    }
    if (rssiActual > -20 || rssiActual < -110) return null;

    final ahora = DateTime.now();
    final v = _ventanaRssi.putIfAbsent(mac, () => []);
    v.add((t: ahora, rssi: rssiActual.toDouble()));
    // El buffer guarda la ventana más larga (la de quieto), con al menos
    // _minMuestras y a lo sumo _maxMuestras lecturas.
    final limiteBuffer = ahora.subtract(
        Duration(microseconds: (_ventanaQuietoSeg * 1e6).round()));
    while (v.length > _minMuestras && v.first.t.isBefore(limiteBuffer)) {
      v.removeAt(0);
    }
    while (v.length > _maxMuestras) {
      v.removeAt(0);
    }
    if (v.length < _minMuestras) return null;

    // Solo las lecturas de la ventana efectiva (según movimiento), y nunca
    // menos de _minMuestras.
    final limiteVentana = ahora.subtract(
        Duration(microseconds: (_ventanaEfectivaSeg * 1e6).round()));
    var desde = v.length;
    while (desde > 0 && !v[desde - 1].t.isBefore(limiteVentana)) {
      desde--;
    }
    desde = min(desde, v.length - _minMuestras);
    final n = v.length - desde;

    // Hot path: se ejecuta por cada lectura nueva de cada beacon. Se recorre
    // el rango interior con índices directos en vez de sublist()/reduce().
    final ordenados = List<double>.generate(n, (i) => v[desde + i].rssi)
      ..sort();
    final corte = (n * _corteMediana).round().clamp(1, n ~/ 3);
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
  /// Un corte en 6 dB rechazaría más o menos la mitad de las coincidencias
  /// buenas. Estos valores dejan pasar hasta el percentil 90.
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

  /// Tolerancia angular (grados) entre el rumbo actual y el rumbo con el que se
  /// capturo el fingerprint.
  ///
  /// El cuerpo del usuario tapa los beacons que quedan DETRAS y deja libres los
  /// de adelante, asi que la atenuacion es desigual y no la cancela la resta del
  /// offset comun. Medido con hasta 12 dB de sombra corporal, distancia robusta
  /// parado en la celda CORRECTA:
  ///   orientacion cualquiera -> mediana 5.63 dB (p90 9.54)
  ///   dentro de +/- 90 grados -> mediana 4.65 dB (p90 7.94)
  ///   dentro de +/- 45 grados -> mediana 4.19 dB (p90 7.10)
  ///   dentro de +/- 20 grados -> mediana 3.98 dB (p90 6.84)
  /// La referencia sin sombra era 3.85 dB: con +/- 45 se recupera casi todo el
  /// terreno perdido. Y lo que mas mejora es la separacion contra un falso
  /// positivo a 6 m, que pasa de 0.82 dB a 1.50 dB de brecha.
  ///
  /// Se usa +/- 90 y no +/- 45: con 45, parado justo en el punto clave pero
  /// mirando hacia otro lado, el patrón queda afuera y la posición no se
  /// corrige nunca. Con +/- 90 la mediana empeora poco (4.65 contra 4.19 dB) y
  /// sigue afuera lo peor: mirar para el lado contrario, con el cuerpo tapando
  /// los beacons de adelante del patrón.
  ///
  /// Bajarlo afina mas pero exige capturar mas orientaciones por celda; subirlo
  /// deja pasar mas sombra corporal.
  static const double _fpToleranciaRumbo = 90.0;

  /// Diferencia angular minima con signo entre dos rumbos, en `[-180, 180]`.
  static double _difRumbo(double a, double b) {
    var d = (a - b) % 360.0;
    if (d > 180.0) d -= 360.0;
    if (d < -180.0) d += 360.0;
    return d;
  }

  /// Convierte una distancia robusta en dB a confianza `[0,1]`.
  ///
  /// Expuesto para que el consumidor pueda suavizar el rms en el tiempo antes
  /// de convertirlo: promediar la distancia y despues mapear es mas estable que
  /// promediar confianzas ya saturadas en 0 o en 1.
  ///
  /// [dbMalo] y [dbBueno]: la coincidencia mínima y la perfecta (ver
  /// [_fpDbMalo] y [_fpDbBueno]); las regula el admin. Entre las dos la
  /// confianza baja en línea recta de 1 a 0.
  static double confianzaFingerprint(
    double rms, {
    double dbMalo = _fpDbMalo,
    double dbBueno = _fpDbBueno,
  }) =>
      ((dbMalo - rms) / max(dbMalo - dbBueno, 0.5)).clamp(0.0, 1.0);

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
  /// Es el mismo criterio que usa esta clase para el RSSI (media truncada)
  /// y que usa el solver para los rangos (perdida de Huber): no dejar que una
  /// sola medicion mala decida.
  ///
  /// 3. Lo que NINGUNA de las dos arregla es la SOMBRA CORPORAL, porque no es
  ///    comun (no afecta a todos los beacons) ni es un solo outlier (afecta a
  ///    todos los que quedan detras del usuario). Para eso esta la puerta
  ///    angular [_fpToleranciaRumbo]: un patron solo compite si fue capturado
  ///    mirando hacia donde el usuario mira ahora. Es la razon por la que una
  ///    esquina a la que se llega desde dos direcciones necesita DOS
  ///    fingerprints en la misma celda, uno por sentido. Dos patrones de la
  ///    misma celda no compiten entre si: el margen se mide contra el mejor de
  ///    OTRA celda.
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
  ///
  /// [dbMalo], [dbBueno] y [toleranciaRumbo]: la coincidencia mínima, la
  /// perfecta y la tolerancia de rumbo, que el admin regula desde el panel de
  /// ajustes (por defecto, [_fpDbMalo], [_fpDbBueno] y [_fpToleranciaRumbo]).
  ///
  /// [diagnostico]: si se pasa, se le agrega una línea por punto clave con lo
  /// que dio la comparación o por qué quedó afuera (para el log).
  static CoincidenciaFingerprint? compararFingerprints({
    required Map<String, double> lecturasVivas,
    required List<CalibracionRegistro> calibraciones,
    double? rumboVivo,
    double dbMalo = _fpDbMalo,
    double dbBueno = _fpDbBueno,
    double toleranciaRumbo = _fpToleranciaRumbo,
    List<String>? diagnostico,
  }) {
    CoincidenciaFingerprint? mejor;
    double mejorDb = double.infinity;
    double mejorOtraCeldaDb = double.infinity;

    for (final cal in calibraciones) {
      if (!cal.esFingerprint) continue;
      final nombre = '${cal.etiqueta ?? ""}(${cal.celdaIx},${cal.celdaIy})';

      // Puerta angular: el patrón sólo compite si fue capturado mirando en una
      // dirección parecida a la actual. Si falta cualquiera de los dos rumbos
      // (no hay brújula, o el punto clave se guardó sin rumbo) se compara sin
      // la puerta en vez de descartarlo. El error que puede meter un match así
      // sigue acotado por el radio espacial que aplica quien consume esto.
      final rumboGuardado = cal.rumboCaptura;
      if (rumboVivo != null && rumboGuardado != null) {
        final dif = _difRumbo(rumboVivo, rumboGuardado).abs();
        if (dif > toleranciaRumbo) {
          diagnostico?.add('$nombre mirando a ${dif.round()}° del patrón');
          continue;
        }
      }

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
      if (comunes < _fpMinComunes) {
        diagnostico?.add('$nombre $comunes beacons en común');
        continue;
      }

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
      diagnostico?.add('$nombre ${rms.toStringAsFixed(1)} dB');
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
          confianza: confianzaFingerprint(rms, dbMalo: dbMalo, dbBueno: dbBueno),
          beaconsComunes: comunes,
        );
      } else if (mejor != null &&
          (mejor.celdaIx != cal.celdaIx || mejor.celdaIy != cal.celdaIy) &&
          rms < mejorOtraCeldaDb) {
        mejorOtraCeldaDb = rms;
      }
    }

    if (mejor == null) return null;
    if (mejor.confianza <= 0) {
      diagnostico?.add('ninguno por debajo de ${dbMalo.toStringAsFixed(1)} dB');
      return null;
    }
    if (mejorOtraCeldaDb.isFinite &&
        (mejorOtraCeldaDb - mejor.distanciaDb) < _fpMargenDb) {
      diagnostico?.add('ambiguo entre dos celdas');
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

  /// Distancia mínima (3D) de un punto de calibración para entrar en la
  /// regresión. Por debajo de ~0,5 m el modelo log deja de valer (campo
  /// cercano) y el RSSI se satura: esos puntos sesgan la pendiente.
  static const double _dMinAjuste = 0.5;

  /// Ajusta ([txPower], [n]) por beacon con mínimos cuadrados sobre las
  /// calibraciones guardadas. Se llama una vez al empezar la navegación.
  ///
  /// ── Paso a paso ──────────────────────────────────────────────────────────
  ///  1. Cada [CalibracionRegistro] aporta un punto por beacon, también los
  ///     puntos clave. El punto donde estaba parado el admin (o el centro de
  ///     la celda, en las calibraciones viejas) y la posición y altura del
  ///     beacon dan la distancia REAL (3D) `d`; `lecturasBle` da el RSSI
  ///     medido ahí (la media truncada de la toma). Dos calibraciones en el
  ///     mismo lugar no se promedian ni se descartan: son dos puntos más, y
  ///     ese lugar pesa el doble en la recta.
  ///  2. Cada punto se guarda como `(x = log10(d), y = rssi)`. En esos ejes
  ///     el modelo `rssi = txPower - 10·n·log10(d)` es una recta: pendiente
  ///     `-10·n`, ordenada `txPower` (el RSSI en d = 1 m, donde log10(d) = 0).
  ///  3. Con la recta de mínimos cuadrados, `pendiente = Σ(x-x̄)(y-ȳ) /
  ///     Σ(x-x̄)²` y `txPower = ȳ - pendiente·x̄`. De ahí, `n = -pendiente/10`.
  ///
  /// ── Cuándo NO se confía en la recta ──────────────────────────────────────
  /// Se usa el modelo por defecto (n = [pathLossExponent] y el txPower
  /// promedio de sus puntos) si el beacon tiene menos de 3 puntos, si todos
  /// están a distancias parecidas (la pendiente no se ve) o si n sale fuera
  /// de 1,5–4,5 (vio más ruido que señal). Así el ajuste nunca queda peor que
  /// el modelo fijo. Los puntos a menos de 0,5 m no entran: ahí el RSSI se
  /// satura y el modelo deja de valer.
  ///
  /// [alturasBeacons]: la altura de cada beacon (m sobre el piso; null o
  /// ausente = a la altura del teléfono). Las distancias son 3D, con
  /// [distanciaReal]: ver "ALTURAS" más arriba.
  static Map<String, ModeloRangoBeacon> ajustarModelosRango({
    required List<CalibracionRegistro> calibraciones,
    required Map<String, Offset> posicionesBeacons,
    required GrillaNav grilla,
    Map<String, double?> alturasBeacons = const {},
  }) {
    final modelos = <String, ModeloRangoBeacon>{};

    // Puntos (log10 d, rssi) por beacon.
    final puntos = <String, List<({double x, double y})>>{};
    for (final cal in calibraciones) {
      final donde = cal.centro(
        (ix, iy) => Offset(grilla.centroX(ix), grilla.centroY(iy)),
      );
      final cx = donde.dx;
      final cy = donde.dy;
      for (final lectura in cal.lecturasBle) {
        final mac = lectura['mac'] as String?;
        final rssi = (lectura['rssi'] as num?)?.toDouble();
        if (mac == null || rssi == null || rssi >= 0 || rssi <= -100) continue;
        final pos = posicionesBeacons[mac];
        if (pos == null) continue;
        final dxm = (pos.dx - cx) * grilla.metrosX;
        final dym = (pos.dy - cy) * grilla.metrosY;
        final d = distanciaReal(dxm, dym, alturasBeacons[mac]);
        if (!d.isFinite || d < _dMinAjuste) continue;
        puntos.putIfAbsent(mac, () => []).add((x: log(d) / ln10, y: rssi));
      }
    }

    // El txPower por defecto sale de las MISMAS lecturas, con la distancia de
    // ahora (posición y altura actuales del beacon). No se promedia el
    // txPowerAjustado guardado en cada calibración: ese se calculó con la
    // altura que tenía el beacon al calibrar (o sin altura, en las
    // calibraciones viejas), y cambiarle la altura después no lo actualiza.
    // Solo si no queda ningún punto útil se cae a lo guardado.
    ModeloRangoBeacon porDefecto(
      String mac,
      List<({double x, double y})> pts,
    ) {
      if (pts.isEmpty) {
        return ModeloRangoBeacon(
          txPower: txPowerCalibrado(mac, calibraciones),
          n: _pathLossExponent,
        );
      }
      double suma = 0;
      for (final p in pts) {
        suma += p.y + 10 * _pathLossExponent * p.x; // rssi + 10·n·log10(d)
      }
      return ModeloRangoBeacon(
        txPower: suma / pts.length,
        n: _pathLossExponent,
        puntos: pts.length,
      );
    }

    for (final mac in posicionesBeacons.keys) {
      final pts = puntos[mac] ?? const <({double x, double y})>[];

      if (pts.length < _minPuntosAjuste) {
        modelos[mac] = porDefecto(mac, pts);
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
        modelos[mac] = porDefecto(mac, pts);
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
        modelos[mac] = porDefecto(mac, pts);
        continue;
      }

      // rssi = tx + pendiente*log10(d),  con pendiente = -10*n.
      final pendiente = sxy / sxx;
      final nAjustado = -pendiente / 10.0;
      if (!nAjustado.isFinite || nAjustado < _nMin || nAjustado > _nMax) {
        debugPrint('[Rango] $mac: n ajustado fuera de rango '
            '(${nAjustado.toStringAsFixed(2)}); se usa el modelo por defecto.');
        modelos[mac] = porDefecto(mac, pts);
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
    _ventanaEfectivaSeg = _ventanaQuietoSeg;
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