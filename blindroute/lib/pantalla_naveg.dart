import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'procesador_senal.dart';
import 'mapa_widget.dart';

class PantallaNavegacion extends StatefulWidget {
  final int pisoId;
  final String rutaImagen;

  const PantallaNavegacion({
    super.key,
    required this.pisoId,
    required this.rutaImagen,
  });

  @override
  State<PantallaNavegacion> createState() => _PantallaNavegacionState();
}

class _PantallaNavegacionState extends State<PantallaNavegacion> {
  final ProcesadorSenal _procesador = ProcesadorSenal();

  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ZonaNoTransitable> _zonas = [];

  // Posición normalizada suavizada con EMA
  Offset? _posicionSuavizada;
  static const double _alphaEMA = 0.25;

  bool _escaneando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosYSuscribirse();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _cargarDatosYSuscribirse() async {
    final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
    final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
    setState(() {
      _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
      _zonas = zonas;
    });

    if (FlutterBluePlus.isScanningNow) {
      setState(() => _escaneando = true);
      FlutterBluePlus.scanResults.listen((resultados) {
        if (!mounted) return;
        _actualizarSenales(resultados);
      });
    } else {
      _iniciarEscaneoPropio();
    }
  }

  Future<void> _iniciarEscaneoPropio() async {
    var permisos = await [Permission.bluetoothScan, Permission.location].request();
    if (!permisos.values.every((s) => s.isGranted)) return;
    setState(() => _escaneando = true);
    await FlutterBluePlus.startScan(continuousUpdates: true);
    FlutterBluePlus.scanResults.listen((resultados) {
      if (!mounted) return;
      _actualizarSenales(resultados);
    });
  }

  void _actualizarSenales(List<ScanResult> resultados) {
    for (var res in resultados) {
      String mac = res.device.remoteId.str;
      double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
      if (rssiSuave != null && _beaconsEnElMapa.containsKey(mac)) {
        _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave;
      }
    }
    _calcularYSuavizarPosicion();
  }

  void _calcularYSuavizarPosicion() {
    var activos = _beaconsEnElMapa.values.where((b) => b.rssiFiltrado > -95).toList();
    if (activos.length < 2) return;

    double sumaX = 0, sumaY = 0, sumaPesos = 0;
    for (var b in activos) {
      double peso = pow(10, (b.rssiFiltrado + 100) / 20).toDouble();
      sumaX += b.posicion.dx * peso;
      sumaY += b.posicion.dy * peso;
      sumaPesos += peso;
    }
    if (sumaPesos == 0) return;

    final nuevaPosicion = Offset(sumaX / sumaPesos, sumaY / sumaPesos);
    setState(() {
      _posicionSuavizada = _posicionSuavizada == null
          ? nuevaPosicion
          : Offset(
              _alphaEMA * nuevaPosicion.dx + (1 - _alphaEMA) * _posicionSuavizada!.dx,
              _alphaEMA * nuevaPosicion.dy + (1 - _alphaEMA) * _posicionSuavizada!.dy,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navegación'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: MapaWidget(
                rutaImagen: widget.rutaImagen,
                beacons: _beaconsEnElMapa,
                zonas: _zonas,
                posicionUsuario: _posicionSuavizada,
                modoEdicion: false,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_escaneando && _posicionSuavizada == null)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_escaneando && _posicionSuavizada == null) const SizedBox(width: 8),
                Text(
                  _posicionSuavizada != null
                      ? 'Ubicación detectada'
                      : _escaneando
                          ? 'Buscando tu ubicación...'
                          : 'Sin señal de beacons',
                  style: TextStyle(color: Colors.indigo[700], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
