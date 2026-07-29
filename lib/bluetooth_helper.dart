import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper robusto para manejar el ciclo de vida del escaneo Bluetooth.
///
/// Regla principal: el scan BLE es un recurso GLOBAL y ÚNICO.
///
/// ── POR QUÉ ESTA CLASE ES DELICADA ─────────────────────────────────────────
/// Android impone un límite NO DOCUMENTADO en la API pero muy real: **5 inicios
/// de scan BLE cada 30 segundos por aplicación**. Al superarlo, el sistema NO
/// devuelve error al llamador: acepta el `startScan()`, no entrega ni un solo
/// resultado, y `FlutterBluePlus.isScanningNow` sigue reportando `true`.
///
/// Ese es exactamente el modo de falla que producía el congelamiento de la
/// posición al entrar y salir repetidas veces de la pantalla de navegación:
/// cada ciclo entrar/salir gastaba un arranque, al quinto Android dejaba de
/// entregar advertisements, y como `isScanningNow` decía `true`, el watchdog
/// que dependía de esa bandera concluía que todo estaba bien y no reiniciaba
/// nada. Sin resultados BLE no hay ciclos de posicionamiento: el ícono queda
/// clavado y no aparece ningún error en pantalla ni en el log.
///
/// De ahí las tres defensas que agrega esta versión:
///
///  1. **Contador propio de arranques** ([_arranques]): se lleva la cuenta de
///     los `startScan()` reales de los últimos 30 s y se deja un margen sobre
///     el límite de Android. Si no hay cupo, se ESPERA en lugar de quemar el
///     intento — quemarlo extiende la penalización.
///
///  2. **Watchdog por DATOS, no por bandera** ([ultimoResultado]): la única
///     prueba confiable de que el scan está vivo es que lleguen resultados. El
///     helper estampa la hora de cada callback y la expone para que la pantalla
///     detecte el silencio prolongado y fuerce un reinicio.
///
///  3. **Liberación explícita de la suscripción** ([liberarSuscripcion]):
///     cuando una pantalla se destruye pero el scan físico debe seguir vivo
///     para la siguiente, hay que soltar igual el listener. Si no, el stream
///     sigue entregando a una `State` ya desmontada cuyo callback descarta todo
///     por `!mounted`, y el scan queda "vivo pero mudo".
class BluetoothHelper {
  static StreamSubscription<List<ScanResult>>? _scanSubscription;
  static StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  // Guardamos los callbacks para poder relanzar el scan al reconectar.
  static void Function(List<ScanResult>)? _onResultadosActual;
  static void Function(Object)? _onErrorActual;
  static Duration _removeIfGoneActual = const Duration(seconds: 4);

  /// Si es true, detenerScanSeguro() no frena el scan físico.
  /// Se usa al navegar de ModoAutomatico → PantallaNavegacion.
  static bool mantenerScanActivo = false;

  // ── DUEÑO ACTUAL DEL SCAN ─────────────────────────────────────────────────
  //
  // POR QUÉ HACE FALTA (esta es LA causa del congelamiento):
  //
  // Flutter destruye la pantalla vieja DESPUÉS de construir la nueva. Con
  // `pushReplacement` (ModoAutomatico → PantallaNavegacion) y con el `pop`
  // normal, el `dispose()` de la pantalla saliente se ejecuta cuando la
  // entrante YA corrió su `initState` y su inicialización asíncrona.
  //
  // Como todo el estado de escaneo es estático, ese `dispose()` tardío
  // desarmaba la suscripción y los callbacks que acababa de registrar la
  // pantalla NUEVA. Resultado exacto del bug reportado:
  //   • el scan físico seguía vivo → `isScanningNow` = true,
  //   • pero no había ningún listener → no llegaba un solo resultado,
  //   • y `reiniciarScanForzado()` salía por `_onResultadosActual == null`,
  //     así que ni siquiera se podía recuperar solo.
  //
  // La evidencia estaba en el log: el TTS "Buscando ubicación" de la pantalla
  // nueva aparecía como `Interrupted: true`, interrumpido por el
  // `_voz.limpiar()` de la pantalla vieja. Ese `limpiar()` y el
  // `detenerScanSeguro()` viven en el mismo `dispose()`: si uno llegó tarde,
  // el otro también.
  //
  // Solución: cada pantalla registra un token (`this`) al tomar el scan. Las
  // operaciones destructivas solo tienen efecto si quien las pide sigue siendo
  // el dueño. Una pantalla que se destruye tarde ya no es dueña de nada y su
  // limpieza se vuelve inofensiva.
  static Object? _dueno;

  /// `true` si [candidato] es quien tiene registrado el scan ahora mismo.
  static bool esDueno(Object candidato) => identical(_dueno, candidato);

  // ── Cuota de arranques (límite de Android) ────────────────────────────────

  /// Momentos en que se llamó realmente a `startScan()`.
  static final List<DateTime> _arranques = <DateTime>[];

  /// Ventana del límite de Android.
  static const Duration _ventanaArranques = Duration(seconds: 30);

  /// Máximo de arranques por ventana. Android permite 5; usamos 4 para dejar
  /// un margen: si se llega al 5 exacto, la penalización se dispara igual y
  /// dura más de lo que uno espera.
  static const int _maxArranquesPorVentana = 4;

  // ── Watchdog por datos ────────────────────────────────────────────────────

  /// Hora del último lote de resultados BLE efectivamente recibido.
  static DateTime? _ultimoResultado;

  /// Hora del último lote de resultados BLE recibido. `null` si todavía no
  /// llegó ninguno desde que arrancó el proceso.
  static DateTime? get ultimoResultado => _ultimoResultado;

  /// `true` si hay callbacks registrados (es decir, alguna pantalla espera
  /// resultados). Sirve para no reiniciar un scan que nadie está escuchando.
  static bool get hayListenerActivo => _onResultadosActual != null;

  /// Evita reinicios solapados (el watchdog corre en timer y el listener del
  /// adaptador puede dispararse al mismo tiempo).
  static bool _reinicioEnCurso = false;

  // ─── PRECONDICIONES ───────────────────────────────────────────────────────

  static Future<bool> verificarPrecondiciones(BuildContext context) async {
    if (!await FlutterBluePlus.isSupported) return false;

    var state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        return false;
      }
    }

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      return false;
    }

    var permisos = await [
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    return permisos.values.every((s) => s.isGranted);
  }

  // ─── CUOTA DE ARRANQUES ───────────────────────────────────────────────────

  static void _purgarArranques() {
    final limite = DateTime.now().subtract(_ventanaArranques);
    _arranques.removeWhere((t) => t.isBefore(limite));
  }

  /// Cuánto hay que esperar para poder llamar a `startScan()` sin superar la
  /// cuota de Android. `Duration.zero` si se puede arrancar ya.
  static Duration esperaParaArrancar() {
    _purgarArranques();
    if (_arranques.length < _maxArranquesPorVentana) return Duration.zero;
    final masViejo = _arranques.first;
    final libera = masViejo.add(_ventanaArranques);
    final falta = libera.difference(DateTime.now());
    return falta.isNegative ? Duration.zero : falta;
  }

  // ─── INICIAR SCAN ─────────────────────────────────────────────────────────

  /// Inicia el escaneo o reutiliza el scan ya activo.
  ///
  /// NUNCA llama `startScan()` si ya hay un scan corriendo — solo reemplaza el
  /// listener. Y si el scan hay que arrancarlo pero no queda cupo en la ventana
  /// de 30 s, devuelve `false` sin quemar el intento; el llamador decide si
  /// espera y reintenta (ver [esperaParaArrancar]).
  static Future<bool> iniciarScanSeguro({
    required Object dueno,
    required void Function(List<ScanResult>) onResultados,
    void Function(Object)? onError,
    Duration? removeIfGone,
  }) async {
    mantenerScanActivo = false;

    // Quien inicia pasa a ser el dueño: cualquier limpieza pendiente de una
    // pantalla anterior queda invalidada a partir de acá.
    _dueno = dueno;

    // Guardar callbacks para reutilizar en reconexión automática y reinicios.
    _onResultadosActual = onResultados;
    _onErrorActual = onError;
    _removeIfGoneActual = removeIfGone ?? const Duration(seconds: 4);

    await _suscribir();

    final ok = await _asegurarScanFisico();

    // Activar reconexión automática ante cortes de BT
    escucharEstadoAdaptador();

    return ok;
  }

  /// (Re)crea la suscripción al stream de resultados envolviendo el callback
  /// del llamador para estampar la hora de cada lote (watchdog por datos).
  static Future<void> _suscribir() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (resultados) {
        _ultimoResultado = DateTime.now();
        _onResultadosActual?.call(resultados);
      },
      onError: (e) => _onErrorActual?.call(e),
    );
  }

  /// Arranca el scan físico si no hay uno corriendo. Respeta la cuota.
  static Future<bool> _asegurarScanFisico() async {
    // La ÚNICA fuente de verdad sobre si hay scan es el plugin. Antes había una
    // bandera estática `_scanIniciado` en paralelo que se desincronizaba: al
    // salir de la pantalla con `mantenerScanActivo` quedaba en `true` aunque el
    // scan hubiera muerto, y entonces esta función no volvía a arrancarlo nunca.
    if (FlutterBluePlus.isScanningNow) return true;

    final espera = esperaParaArrancar();
    if (espera > Duration.zero) {
      debugPrint('[BLE] Sin cupo de arranques de scan; '
          'faltan ${espera.inSeconds}s para poder reintentar.');
      return false;
    }

    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.balanced,
        removeIfGone: _removeIfGoneActual,
      ).timeout(const Duration(seconds: 5));
      _arranques.add(DateTime.now());
      // Se considera "vivo" desde el arranque: si en los próximos segundos no
      // llega nada, el watchdog de la pantalla lo va a detectar.
      _ultimoResultado ??= DateTime.now();
      debugPrint('[BLE] Scan iniciado '
          '(${_arranques.length}/$_maxArranquesPorVentana en la ventana).');
      return true;
    } catch (e) {
      // Aunque haya fallado, Android ya contabilizó el intento.
      _arranques.add(DateTime.now());
      debugPrint('[BLE] Error al iniciar scan: $e');
      _onErrorActual?.call(e);
      return false;
    }
  }

  /// Reinicio completo del scan: baja el scan físico y lo vuelve a levantar.
  ///
  /// Es la salida para el caso "Android dice que está escaneando pero no
  /// entrega nada". Devuelve `false` si no hay cupo o si ya hay un reinicio en
  /// curso; el llamador debe reintentar más tarde y NO insistir en bucle.
  static Future<bool> reiniciarScanForzado() async {
    // Toda salida temprana se loguea. En la version anterior estas dos
    // devolvian `false` en silencio, y por eso el log solo mostraba
    // "Forzando reinicio" una y otra vez sin ninguna pista de por que no
    // pasaba nada. Un camino de fallo sin log es un camino de fallo invisible.
    if (_reinicioEnCurso) {
      debugPrint('[BLE] Reinicio ignorado: ya hay uno en curso.');
      return false;
    }
    if (_onResultadosActual == null) {
      debugPrint('[BLE] Reinicio abortado: no hay listener registrado. '
          'El dueño del scan se perdió; la pantalla debe re-registrarse.');
      return false;
    }

    if (esperaParaArrancar() > Duration.zero) {
      debugPrint('[BLE] Reinicio forzado pospuesto: sin cupo de arranques.');
      return false;
    }

    _reinicioEnCurso = true;
    try {
      try {
        if (FlutterBluePlus.isScanningNow) {
          // Timeout defensivo: si la llamada a la plataforma se cuelga, el
          // `finally` no correria nunca y `_reinicioEnCurso` quedaria trabado
          // en true para siempre, bloqueando todos los reintentos futuros.
          await FlutterBluePlus.stopScan()
              .timeout(const Duration(seconds: 3));
        }
      } catch (e) {
        debugPrint('[BLE] stopScan falló o expiró: $e');
      }
      // Respiro para que la pila BLE de Android libere el cliente de scan.
      await Future.delayed(const Duration(milliseconds: 400));

      await _suscribir();
      final ok = await _asegurarScanFisico();
      if (ok) {
        _ultimoResultado = DateTime.now();
        debugPrint('[BLE] Reinicio forzado del scan completado.');
      }
      return ok;
    } finally {
      _reinicioEnCurso = false;
    }
  }

  // ─── RECONEXIÓN AUTOMÁTICA ────────────────────────────────────────────────

  /// Escucha el estado del adaptador BT y relanza el scan automáticamente
  /// si se cortó y volvió.
  ///
  /// Seguro llamar múltiples veces: cancela el listener anterior antes de crear
  /// uno nuevo. El guard [_reinicioEnCurso] evita la reentrada: como
  /// `adapterState` emite el estado actual apenas uno se suscribe, sin ese
  /// guard esta función podía llamarse a sí misma en cadena.
  static void escucharEstadoAdaptador() {
    _adapterSubscription?.cancel();
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) async {
      if (state != BluetoothAdapterState.on) return;
      if (_onResultadosActual == null) return;
      if (_reinicioEnCurso) return;
      if (FlutterBluePlus.isScanningNow) return;
      // BT volvió a estar disponible y no hay scan: relanzar con los mismos
      // callbacks, respetando la cuota.
      await _asegurarScanFisico();
    });
  }

  // ─── DETENER / LIBERAR ────────────────────────────────────────────────────

  /// Suelta la suscripción y los callbacks SIN tocar el scan físico.
  ///
  /// Es lo que tiene que llamar una pantalla que se destruye pero quiere dejar
  /// el scan corriendo para la siguiente. Antes esas pantallas no llamaban a
  /// nada: la suscripción sobrevivía apuntando a una `State` desmontada, cuyo
  /// callback descarta todo por `!mounted`. El scan seguía "vivo" pero sus
  /// resultados no llegaban a ninguna parte, y encima el listener del adaptador
  /// podía resucitarlo con esos callbacks muertos.
  static Future<void> liberarSuscripcion(Object dueno) async {
    if (!esDueno(dueno)) {
      // Otra pantalla ya tomó el scan: esta limpieza llegó tarde y desarmaría
      // recursos ajenos. Ver la nota de [_dueno].
      debugPrint('[BLE] liberarSuscripcion ignorada: el solicitante ya no es '
          'el dueño del scan.');
      return;
    }
    _dueno = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    _onResultadosActual = null;
    _onErrorActual = null;
  }

  /// Detiene el scan. Si se pasa [dueno], la operación se ignora cuando ese
  /// objeto ya no es el dueño registrado (limpieza tardía de una pantalla
  /// destruida después de que otra tomó el scan).
  static Future<void> detenerScanSeguro({Object? dueno}) async {
    if (dueno != null && !esDueno(dueno)) {
      debugPrint('[BLE] detenerScanSeguro ignorado: el solicitante ya no es '
          'el dueño del scan.');
      return;
    }
    _dueno = null;

    // Siempre cancelar el listener del adaptador al detener
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    _onResultadosActual = null;
    _onErrorActual = null;

    if (mantenerScanActivo) {
      // Solo cancelar el listener; el scan físico sigue para la próxima pantalla
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      mantenerScanActivo = false;
      return;
    }

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {
      // Ignorar errores al detener
    }
  }

  // ─── UTILIDAD ─────────────────────────────────────────────────────────────

  static void setStateSeguro(VoidCallback setStateFn, bool mounted) {
    if (mounted) setStateFn();
  }
}