import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'bluetooth_helper.dart';
import 'pantalla_naveg.dart';
import 'supabase_service.dart';
import 'voz_service.dart';
import 'tema.dart';
 
class ModoAutomatico extends StatefulWidget {
  const ModoAutomatico({super.key});
 
  @override
  State<ModoAutomatico> createState() => _ModoAutomaticoState();
}
 
class _ModoAutomaticoState extends State<ModoAutomatico> {
  bool _navegando = false;
  bool _resolviendo = false; // en medio de resolver una llegada (chequeo/descarga)
  String _estado = 'Iniciando...';
  int _beaconsDetectados = 0;

  // Optimización de red: no consultar la nube en cada barrido. Se recuerdan las
  // MACs que ya se consultaron sin resultado y se limita la frecuencia.
  final Set<String> _macsSinMapa = {};
  DateTime? _ultimaConsultaNube;

  Timer? _timeoutTimer;
  Timer? _mapaTimer;
 
  // Procesador compartido que se pasara a PantallaNavegacion
  final ProcesadorSenal _procesador = ProcesadorSenal();
  final VozService _voz = VozService();
 
  @override
  void initState() {
    super.initState();
    _iniciarBusqueda();
  }
 
  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _mapaTimer?.cancel();
    // NO detenemos el scan aqui - PantallaNavegacion lo necesita activo
    // Solo cancelamos si no navegamos
    if (!_navegando) {
      BluetoothHelper.detenerScanSeguro(dueno: this);
    }
    super.dispose();
  }
 
  Future<void> _iniciarBusqueda() async {
    final ok = await BluetoothHelper.verificarPrecondiciones(context);
    if (!ok) {
      if (mounted) {
        setState(() => _estado = 'Bluetooth o permisos no disponibles.');
      }
      return;
    }
 
    if (mounted) {
      setState(() => _estado = 'Buscando beacons de BlindRoute...');
    }
 
    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) => _procesarResultados(resultados),
      onError: (e) {
        if (mounted) {
          setState(() => _estado = 'Error en scan: $e');
        }
      },
      removeIfGone: const Duration(seconds: 3),
    );
 
    if (!scanOk && mounted) {
      setState(() => _estado = 'No se pudo iniciar el escaneo');
      return;
    }
 
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_navegando && _beaconsDetectados == 0) {
        setState(() => _estado = 'No se encontraron mapas.');
        _voz.hablar('No se encontraron mapas.');
      }
    });
  }
 
  Future<void> _procesarResultados(List<ScanResult> resultados) async {
    if (_navegando || _resolviendo) return;
 
    // Procesar señales para ir llenando la ventana de mediana de cada beacon,
    // así al pasar a PantallaNavegacion (mismo ProcesadorSenal compartido) el
    // filtro ya tiene historial y la ubicación se estabiliza más rápido.
    for (var res in resultados) {
      try {
        String mac = res.device.remoteId.str;
        _procesador.filtrarYPromediar(mac, res.rssi);
      } catch (e) {
        // Ignorar
      }
    }
 
    // 1) ¿Alguna MAC está en un mapa LOCAL? Se recorre todo una sola vez.
    final macs = <String>[];
    Map<String, dynamic>? infoLocal;
    for (var res in resultados) {
      final mac = res.device.remoteId.str;
      macs.add(mac);
      if (infoLocal == null) {
        try {
          final info = await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);
          if (info != null) infoLocal = info;
        } catch (e) {
          // Ignorar errores de DB individuales
        }
      }
    }

    // Tiene el mapa local: navegar (chequeando si hay una versión más nueva).
    if (infoLocal != null) {
      _resolviendo = true;
      await _resolverLlegadaLocal(infoLocal, macs);
      return;
    }

    // 2) No hay mapa local. Buscar en la nube y autodescargar. Optimización:
    //    se consulta una sola vez por conjunto de MACs (se recuerdan las que no
    //    tienen mapa) y como mucho cada 10 s, para no golpear el servidor en
    //    cada barrido si el lugar no tiene mapa o no hay conexión.
    final ahora = DateTime.now();
    final hayMacsNuevas = macs.any((m) => !_macsSinMapa.contains(m));
    final pasoThrottle = _ultimaConsultaNube == null ||
        ahora.difference(_ultimaConsultaNube!) > const Duration(seconds: 10);
    if (macs.isNotEmpty &&
        hayMacsNuevas &&
        pasoThrottle &&
        SupabaseService.instance.configurado) {
      _ultimaConsultaNube = ahora;
      _resolviendo = true;
      try {
        final remoteId = await SupabaseService.instance.buscarMapaPorMacs(macs);
        if (remoteId != null && !_navegando) {
          if (mounted) {
            setState(() => _estado = 'Descargando mapa de este lugar...');
          }
          _voz.hablar('Descargando el mapa de este lugar.');
          await SupabaseService.instance.descargarMapa(remoteId);
          for (final mac in macs) {
            final info = await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);
            if (info != null) {
              _irANavegacion(info);
              return;
            }
          }
        } else if (remoteId == null) {
          // No hay mapa para estas MACs: no volver a consultarlas.
          _macsSinMapa.addAll(macs);
        }
      } catch (e) {
        // Error / sin datos: no se marcan como "sin mapa" para poder reintentar
        // cuando vuelva la conexión (limitado por el throttle de 10 s).
      } finally {
        if (!_navegando) _resolviendo = false;
      }
    }
 
    // 3) Feedback de dispositivos detectados sin mapa (comportamiento de siempre)
    if (mounted && !_navegando && !_resolviendo && macs.isNotEmpty) {
      setState(() {
        _beaconsDetectados = macs.length;
        _estado = 'Detectados ${macs.length} dispositivo(s)...';
      });
      // Iniciar timer de mapa solo una vez, cuando aparecen beacons sin mapa
      _mapaTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && !_navegando && !_resolviendo) {
          setState(() => _estado = 'Mapa no encontrado.');
          _voz.hablar('Mapa no encontrado.');
        }
      });
    }
  }

  /// Resuelve la llegada a un lugar con mapa ya descargado. Si hay conexión y el
  /// mapa fue actualizado por el admin, avisa por voz, baja la nueva versión y
  /// navega con ella. Si no hay datos (o falla), navega con la versión local.
  /// Siempre termina navegando: nunca deja al usuario esperando.
  Future<void> _resolverLlegadaLocal(
      Map<String, dynamic> info, List<String> macs) async {
    final remoteId = info['remote_id'] as String?;
    final localTs = info['remote_actualizado'] as String?;

    // Sólo tiene sentido chequear si el mapa vino de la nube y sabemos su
    // versión local (los descargados antes de guardar versión no se comparan).
    if (remoteId != null &&
        localTs != null &&
        SupabaseService.instance.configurado) {
      try {
        final serverTs = await SupabaseService.instance
            .obtenerActualizadoEn(remoteId)
            .timeout(const Duration(seconds: 3));
        final localDt = DateTime.tryParse(localTs);
        if (serverTs != null &&
            localDt != null &&
            serverTs.isAfter(localDt)) {
          // Hay versión más nueva y hubo respuesta => hay conexión: actualizar.
          if (mounted) setState(() => _estado = 'Actualizando mapa...');
          _voz.hablar('Actualizando el mapa de este lugar.');
          await SupabaseService.instance
              .descargarMapa(remoteId)
              .timeout(const Duration(seconds: 20));
          for (final mac in macs) {
            final fresco =
                await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);
            if (fresco != null) {
              _irANavegacion(fresco);
              return;
            }
          }
        }
      } catch (e) {
        // Sin datos / timeout / error: se sigue con la versión local.
      }
    }

    // Sin actualización, sin conexión o error: navegar con lo que ya está.
    _irANavegacion(info);
  }

  /// Pasa a la pantalla de navegación con los datos del piso (local).
  void _irANavegacion(Map<String, dynamic> info) {
    _navegando = true;
    _timeoutTimer?.cancel();
    _mapaTimer?.cancel();

    // IMPORTANTE: Indicar que NO se detenga el scan al dispose
    BluetoothHelper.mantenerScanActivo = true;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PantallaNavegacion(
            pisoId: info['id'],
            rutaImagen: info['ruta_imagen'],
            escalaX: (info['escala_metros'] as num?)?.toDouble() ?? 50,
            escalaY: (info['escala_metros_alto'] as num?)?.toDouble() ?? 50,
            tamCeldaMetros:
                (info['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
            rotacionMapa: (info['rotacion_mapa'] as num?)?.toDouble() ?? 0.0,
            procesadorCompartido: _procesador, // Pasar el mismo procesador
          ),
        ),
      );
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: TemaApp.acento,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _estado,
                style: const TextStyle(fontSize: 22, color: TemaApp.textoBlanco, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (_beaconsDetectados > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '$_beaconsDetectados dispositivo(s) en rango',
                    style: const TextStyle(fontSize: 15, color: TemaApp.textoSecundario),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}