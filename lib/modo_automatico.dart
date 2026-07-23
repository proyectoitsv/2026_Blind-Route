import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'bluetooth_helper.dart';
import 'pantalla_naveg.dart';
import 'voz_service.dart';
import 'tema.dart';
 
class ModoAutomatico extends StatefulWidget {
  const ModoAutomatico({super.key});
 
  @override
  State<ModoAutomatico> createState() => _ModoAutomaticoState();
}
 
class _ModoAutomaticoState extends State<ModoAutomatico> {
  bool _navegando = false;
  String _estado = 'Iniciando...';
  int _beaconsDetectados = 0;
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
      BluetoothHelper.detenerScanSeguro();
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
    if (_navegando) return;
 
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
 
    int detectados = 0;
    for (var res in resultados) {
      String mac = res.device.remoteId.str;
      try {
        final info = await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);
        if (info != null) {
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
                  tamCeldaMetros: (info['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
                  rotacionMapa: (info['rotacion_mapa'] as num?)?.toDouble() ?? 0.0,
                  procesadorCompartido: _procesador, // Pasar el mismo procesador
                ),
              ),
            );
          }
          return;
        }
      } catch (e) {
        // Ignorar errores de DB individuales
      }
      detectados++;
    }
 
    if (mounted && !_navegando && detectados > 0) {
      setState(() {
        _beaconsDetectados = detectados;
        _estado = 'Detectados $detectados dispositivo(s)...';
      });
      // Iniciar timer de mapa solo una vez, cuando aparecen beacons sin mapa
      _mapaTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && !_navegando) {
          setState(() => _estado = 'Mapa no encontrado.');
          _voz.hablar('Mapa no encontrado.');
        }
      });
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