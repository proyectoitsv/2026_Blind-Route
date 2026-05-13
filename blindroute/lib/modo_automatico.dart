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
  bool _navegando = false; // Evita abrir la pantalla varias veces

  @override
  void initState() {
    super.initState();
    _iniciarBusquedaSilenciosa();
  }

  @override
  void dispose() {
    // Solo detenemos el scan si todavía no navegamos a la siguiente pantalla.
    // Si ya navegamos, PantallaNavegacion heredó el scan y lo maneja ella.
    if (!_navegando) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  void _iniciarBusquedaSilenciosa() async {
    var permisos = await [Permission.bluetoothScan, Permission.location].request();
    if (!permisos.values.every((s) => s.isGranted)) return;

    // Iniciamos el scan SIN timeout y SIN llamar stopScan al encontrar el beacon.
    // PantallaNavegacion recibirá este mismo stream y lo seguirá usando.
    await FlutterBluePlus.startScan(continuousUpdates: true);

    FlutterBluePlus.scanResults.listen((resultados) async {
      if (_navegando) return;

      for (var res in resultados) {
        String mac = res.device.remoteId.str;
        final info = await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);

        if (info != null) {
          _navegando = true; // Bloqueamos futuras llamadas

          if (!mounted) return;

          // CLAVE: NO detenemos el scan. PantallaNavegacion lo hereda activo.
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
              "Buscando señales de BlindRoute...",
              style: TextStyle(fontSize: 24, color: Colors.indigo[900]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
