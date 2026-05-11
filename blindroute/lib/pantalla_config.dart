import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/semantics.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'beacon_model.dart';
import 'dart:convert'; // Necesario para JSON
import 'package:shared_preferences/shared_preferences.dart';





class PantallaConfiguracion extends StatefulWidget {
  // Estos son los "tomacorrientes" que vamos a crear:
  final int pisoId;
  final String rutaImagen;

  // Actualizamos el constructor para que pida estos datos obligatoriamente
  const PantallaConfiguracion({
    super.key, 
    required this.pisoId, 
    required this.rutaImagen
  });

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ScanResult> _dispositivosCercanos = [];
  ScanResult? _seleccionado;
  bool _escaneando = false;
  File? _planoImagen;
  Offset? _posicionUsuario;

  // 1. INICIALIZACIÓN: Carga los datos apenas abre la pantalla
  @override
  void initState() {
    super.initState();
    _cargarBeaconsGuardados();
  }

  // 2. PERSISTENCIA: Guardar en el almacenamiento interno
  Future<void> _guardarBeacons() async {
    final prefs = await SharedPreferences.getInstance();
    // Convertimos el mapa a una cadena de texto JSON
    String datos = jsonEncode(_beaconsEnElMapa.map((key, value) => MapEntry(key, value.toJson())));
    await prefs.setString('beacons_guardados', datos);
  }

  // 3. PERSISTENCIA: Cargar desde el almacenamiento interno
  Future<void> _cargarBeaconsGuardados() async {
    final prefs = await SharedPreferences.getInstance();
    String? datos = prefs.getString('beacons_guardados');
    if (datos != null) {
      Map<String, dynamic> decoded = jsonDecode(datos);
      setState(() {
        _beaconsEnElMapa = decoded.map((key, value) => 
          MapEntry(key, BeaconMarcado.fromJson(value)));
      });
    }
  }

  // 4. GESTIÓN: Borrar un beacon específico
  void _borrarBeacon(String mac) {
    setState(() {
      _beaconsEnElMapa.remove(mac);
    });
    _guardarBeacons(); // Guardamos el cambio (el mapa ahora tiene uno menos)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Beacon eliminado correctamente"))
    );
  }

  // Lógica de carga de imagen
  Future<void> _cargarPlano() async {
    final selector = ImagePicker();
    final imagen = await selector.pickImage(source: ImageSource.gallery);
    if (imagen != null) {
      setState(() => _planoImagen = File(imagen.path));
    }
  }

  // Lógica de Bluetooth
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
          _actualizarSenalesYPosicion(resultados);
        });
      });
    }
  }

  void _actualizarSenalesYPosicion(List<ScanResult> resultados) {
    for (var res in resultados) {
      String mac = res.device.remoteId.str;
      if (_beaconsEnElMapa.containsKey(mac)) {
        _beaconsEnElMapa[mac]!.agregarLectura(res.rssi.toDouble());
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

  void _ubicarEnMapa(TapDownDetails det) {
    if (_seleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seleccioná un beacon de la lista abajo para ubicarlo"))
      );
      return;
    }
    
    String mac = _seleccionado!.device.remoteId.str;
    setState(() {
      _beaconsEnElMapa[mac] = BeaconMarcado(
        posicion: det.localPosition,
        nombre: _seleccionado!.device.advName.isEmpty ? 'Beacon' : _seleccionado!.device.advName,
        mac: mac,
      );
      _seleccionado = null; 
    });
    _guardarBeacons(); // Guardamos automáticamente al ubicar uno nuevo
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BlindRoute GPS Interno'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _cargarPlano),
        ],
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
                  if (_planoImagen != null) 
                    Image.file(_planoImagen!, fit: BoxFit.fill, width: double.infinity, height: 400),
                  
                  if (_planoImagen == null)
                    const Center(child: Text("Tocá el ícono de imagen arriba para cargar el plano")),

                  // Puntos de los Beacons fijos
                  ..._beaconsEnElMapa.values.map((b) => Positioned(
                    left: b.posicion.dx - 10,
                    top: b.posicion.dy - 10,
                    child: GestureDetector(
                      onLongPress: () => _borrarBeacon(b.mac), // Toque largo para borrar
                      child: const Icon(Icons.radio_button_checked, color: Colors.red, size: 20),
                    ),
                  )),

                  // Punto azul del usuario
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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ElevatedButton.icon(
              onPressed: _conmutarEscaner,
              icon: Icon(_escaneando ? Icons.stop : Icons.play_arrow),
              label: Text(_escaneando ? 'Detener Rastreo' : 'Iniciar Rastreo en Tiempo Real'),
            ),
          ),

          const Divider(),
          
          Expanded(
            child: ListView.builder(
              itemCount: _dispositivosCercanos.length,
              itemBuilder: (context, i) {
                var d = _dispositivosCercanos[i];
                bool isSelected = _seleccionado == d;
                return ListTile(
                  dense: true,
                  tileColor: isSelected ? Colors.teal[50] : null,
                  title: Text(d.device.advName.isEmpty ? "Dispositivo oculto" : d.device.advName),
                  subtitle: Text("MAC: ${d.device.remoteId.str} | RSSI: ${d.rssi} dBm"),
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