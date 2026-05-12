import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database.dart';
import 'pantalla_naveg.dart';

class ModoAutomatico extends StatefulWidget {
  const ModoAutomatico({super.key});

  @override
  State<ModoAutomatico> createState() => _ModoAutomaticoState();
}

class _ModoAutomaticoState extends State<ModoAutomatico> {
  bool _buscando = true;

  @override
  void initState() {
    super.initState();
    _iniciarBusquedaSilenciosa();
  }

  void _iniciarBusquedaSilenciosa() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((resultados) async {
      for (var res in resultados) {
        String mac = res.device.remoteId.str;
        
        // Consultamos a la base de datos si conocemos este Beacon
        final info = await DatabaseHelper.instance.obtenerInfoPorBeacon(mac);
        
        if (info != null && _buscando) {
          _buscando = false; // Evitamos que abra la pantalla muchas veces
          await FlutterBluePlus.stopScan();

          if (!mounted) return;
          
          // Saltamos directamente al mapa en modo navegación (solo lectura)
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