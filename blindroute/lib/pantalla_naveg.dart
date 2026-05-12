import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'database.dart';
import 'beacon_model.dart';
import 'procesador_senal.dart';

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

  // Beacons cargados desde la DB (solo lectura)
  Map<String, BeaconMarcado> _beaconsEnElMapa = {};

  // Posición calculada del usuario
  Offset? _posicionUsuario;

  bool _escaneando = false;

  @override
  void initState() {
    super.initState();
    _cargarBeaconsYEscanear();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // Carga los beacons configurados por el admin e inicia el escaneo automáticamente
  Future<void> _cargarBeaconsYEscanear() async {
    final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
    setState(() {
      _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
    });
    _iniciarEscaneo();
  }

  Future<void> _iniciarEscaneo() async {
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
        setState(() {
          _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave;
        });
      }
    }
    _calcularPosicion();
  }

  void _calcularPosicion() {
    var activos = _beaconsEnElMapa.values.where((b) => b.rssiFiltrado > -95).toList();
    if (activos.length < 2) return;

    double sumaX = 0, sumaY = 0, sumaPesos = 0;
    for (var b in activos) {
      double peso = pow(10, (b.rssiFiltrado + 100) / 20).toDouble();
      sumaX += b.posicion.dx * peso;
      sumaY += b.posicion.dy * peso;
      sumaPesos += peso;
    }

    if (sumaPesos > 0) {
      setState(() {
        _posicionUsuario = Offset(sumaX / sumaPesos, sumaY / sumaPesos);
      });
    }
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
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  child: Stack(
                    children: [
                      // Plano del piso (solo lectura, sin GestureDetector de edición)
                      Image.file(
                        File(widget.rutaImagen),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(child: Text("Plano no disponible")),
                      ),

                      // Beacons como referencia visual fija (no interactivos)
                      ..._beaconsEnElMapa.values.map((b) => Positioned(
                            left: b.posicion.dx - 5,
                            top: b.posicion.dy - 5,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.black26,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )),

                      // Posición del usuario
                      if (_posicionUsuario != null)
                        Positioned(
                          left: _posicionUsuario!.dx - 15,
                          top: _posicionUsuario!.dy - 15,
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.blue,
                            size: 35,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Indicador de estado del escaneo
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_escaneando)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_escaneando) const SizedBox(width: 8),
                Text(
                  _escaneando
                      ? 'Buscando tu ubicación...'
                      : _posicionUsuario != null
                          ? 'Ubicación detectada'
                          : 'Sin señal de beacons',
                  style: TextStyle(
                    color: Colors.indigo[700],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
