import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database.dart';
import 'pantalla_naveg.dart';

class ModoAutomatico extends StatefulWidget {
  const ModoAutomatico({super.key});

  @override
  State<ModoAutomatico> createState() => _ModoAutomaticoState();
}

class _ModoAutomaticoState extends State<ModoAutomatico> {
  bool _navegando = false;
  String _estado = 'Buscando senales de BlindRoute...';
  int _beaconsDetectados = 0;

  // NUEVO: Suscripcion al stream
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _iniciarBusquedaSilenciosa();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    if (!_navegando) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  Future<void> _iniciarBusquedaSilenciosa() async {
    var permisos = await [Permission.bluetoothScan, Permission.location].request();
    if (!permisos.values.every((s) => s.isGranted)) {
      setState(() => _estado = 'Permisos denegados. Habilita Bluetooth y Location.');
      return;
    }

    // Esperar Bluetooth encendido
    if (!await FlutterBluePlus.isSupported) {
      setState(() => _estado = 'Bluetooth no soportado');
      return;
    }

    var state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        setState(() => _estado = 'Por favor, encende el Bluetooth');
        return;
      }
    }

    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.off);

    // Asegurar que no haya scan activo previo
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Limpiar resultados previos

    // NUEVO: Suscribirse con onScanResults antes de iniciar scan
    _scanSubscription = FlutterBluePlus.onScanResults.listen((resultados) async {
      if (_navegando) return;

      for (var res in resultados) {
        String mac = res.device.remoteId.str;
        final info = await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);

        if (info != null) {
          _navegando = true;

          if (!mounted) return;

          // Cancelar suscripcion antes de navegar
          _scanSubscription?.cancel();

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaNavegacion(
                pisoId: info['id'],
                rutaImagen: info['ruta_imagen'],
              ),
            ),
          );
          break;
        }
      }

      // Contador para feedback visual
      if (mounted && !_navegando) {
        setState(() {
          _beaconsDetectados = resultados.length;
          if (resultados.isNotEmpty) {
            _estado = 'Detectados $_beaconsDetectados dispositivo(s)...';
          }
        });
      }
    });

    // Iniciar scan
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
      removeIfGone: const Duration(seconds: 3),
    );

    // Timeout de seguridad
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && !_navegando && _beaconsDetectados == 0) {
        setState(() => _estado = 'No se detectaron beacons conocidos. Asegurate de estar cerca de un beacon configurado.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _estado,
              style: TextStyle(fontSize: 24, color: Colors.indigo[900]),
              textAlign: TextAlign.center,
            ),
            if (_beaconsDetectados > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '$_beaconsDetectados dispositivo(s) en rango',
                  style: TextStyle(fontSize: 14, color: Colors.indigo[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}