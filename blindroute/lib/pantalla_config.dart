import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'beacon_model.dart';
import 'database.dart'; // Importante para la persistencia real
import 'procesador_senal.dart'; // Para el filtrado de señales

class PantallaConfiguracion extends StatefulWidget {
  final int pisoId;
  final String rutaImagen;
  

  const PantallaConfiguracion({
    super.key, 
    required this.pisoId, 
    required this.rutaImagen
  });

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  final ProcesadorSenal _procesador = ProcesadorSenal();
  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ScanResult> _dispositivosCercanos = [];
  ScanResult? _seleccionado;
  bool _escaneando = false;
  Offset? _posicionUsuario;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  // Carga los beacons desde la DB. La imagen ya viene por el constructor.
  Future<void> _cargarDatosIniciales() async {
    final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
    setState(() {
      _beaconsEnElMapa = { for (var b in beacons) b.mac : b };
    });
  }

  // Cada vez que agregamos o quitamos algo, actualizamos SQLite
  Future<void> _sincronizarDB() async {
    await DatabaseHelper.instance.guardarBeacons(widget.pisoId, _beaconsEnElMapa.values.toList());
  }

  void _borrarBeacon(String mac) async {
    setState(() {
      _beaconsEnElMapa.remove(mac);
    });
    await _sincronizarDB();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Beacon eliminado"))
    );
  }

  void _conmutarEscaner() async {
    if (_escaneando) {
      await FlutterBluePlus.stopScan();
      setState(() => _escaneando = false);
      return;
    }

    var permisos = await [Permission.bluetoothScan, Permission.location].request();
    if (permisos.values.every((stat) => stat.isGranted)) {
      setState(() => _escaneando = true);
      await FlutterBluePlus.startScan(continuousUpdates: true);

      FlutterBluePlus.scanResults.listen((resultados) {
        if (!mounted) return;
        setState(() {
          _dispositivosCercanos = resultados;
          _actualizarSenales(resultados);
        });
      });
    }
  }

  void _actualizarSenales(List<ScanResult> resultados) {
  for (var res in resultados) {
    String mac = res.device.remoteId.str;
    
    // Aquí ocurre la magia: el procesador decide si la lectura es válida
    double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);

    if (rssiSuave != null && _beaconsEnElMapa.containsKey(mac)) {
      setState(() {
        // Guardamos el promedio suavizado en lugar del RSSI bruto
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

  void _ubicarEnMapa(TapDownDetails det) async {
    if (_seleccionado == null) return;
    
    String mac = _seleccionado!.device.remoteId.str;
    setState(() {
      _beaconsEnElMapa[mac] = BeaconMarcado(
        posicion: det.localPosition,
        nombre: _seleccionado!.device.advName.isEmpty ? 'Beacon' : _seleccionado!.device.advName,
        mac: mac,
      );
      _seleccionado = null; 
    });
    await _sincronizarDB();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Piso'),
        backgroundColor: Colors.teal[800],
      ),
      body: Column(
        children: [
          GestureDetector(
            onTapDown: _ubicarEnMapa,
            child: Container(
              height: 400,
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.teal),
                color: Colors.grey[200],
              ),
              child: Stack(
                children: [
                  // La imagen ahora es persistente porque la cargamos de la ruta guardada
                  Image.file(
                    File(widget.rutaImagen), 
                    fit: BoxFit.fill, 
                    width: double.infinity, 
                    height: 400,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text("Plano no encontrado"),
                    ),
                  ),
                  
                  ..._beaconsEnElMapa.values.map((b) => Positioned(
                    left: b.posicion.dx - 10,
                    top: b.posicion.dy - 10,
                    child: GestureDetector(
                      onLongPress: () => _borrarBeacon(b.mac),
                      child: const Icon(Icons.radio_button_checked, color: Colors.red, size: 20),
                    ),
                  )),

                  if (_posicionUsuario != null)
                    Positioned(
                      left: _posicionUsuario!.dx - 15,
                      top: _posicionUsuario!.dy - 15,
                      child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 35),
                    ),
                ],
              ),
            ),
          ),
          // ... resto del UI de la lista de dispositivos (se mantiene igual)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ElevatedButton.icon(
              onPressed: _conmutarEscaner,
              icon: Icon(_escaneando ? Icons.stop : Icons.play_arrow),
              label: Text(_escaneando ? 'Detener' : 'Probar Rastreo'),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _dispositivosCercanos.length,
              itemBuilder: (context, i) {
                var d = _dispositivosCercanos[i];
                return ListTile(
                  tileColor: _seleccionado == d ? Colors.teal[50] : null,
                  title: Text(d.device.advName.isEmpty ? "Desconocido" : d.device.advName),
                  subtitle: Text("${d.device.remoteId.str} | ${d.rssi} dBm"),
                  onTap: () => setState(() => _seleccionado = d),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}