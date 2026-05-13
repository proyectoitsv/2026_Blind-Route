import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'procesador_senal.dart';
import 'mapa_widget.dart';
import 'pathfinder.dart';

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
  final ResolvedorCaminos _resolvedor = ResolvedorCaminos();

  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ZonaNoTransitable> _zonas = [];
  List<LugarInteres> _lugares = [];

  // Estabilizacion de posicion
  Offset? _posicionEMA;
  static const double _alphaEMA = 0.12;
  Offset? _posicionConfirmada;
  int _contadorEstabilidad = 0;
  static const int _lecturasParaConfirmar = 8;
  static const double _umbralEstabilidad = 0.025;
  final List<Offset> _historialPosiciones = [];
  static const int _ventanaCentroid = 6;
  Offset? _posicionFinal;

  bool _escaneando = false;
  String _estadoScan = 'Iniciando...';

  // Navegacion
  LugarInteres? _destinoSeleccionado;
  List<Offset>? _rutaActual;
  String _estadoRuta = '';

  // Histeresis de ruta
  Offset? _ultimaPosicionRuta;
  static const double _umbralRecalcularRuta = 0.05;

  // Parametros de trilateracion
  static const int _minBeaconsActivos = 3;
  static const int _maxBeaconsParaCalcular = 5;
  static const double _umbralRSSI = -88;
  static const double _exponentePeso = 2.5;

  // NUEVO: Suscripcion al stream de scan
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _cargarDatosYIniciarScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _cargarDatosYIniciarScan() async {
    // 1. Cargar datos de DB
    final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
    final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
    final lugares = await DatabaseHelper.instance.obtenerLugaresPorPiso(widget.pisoId);
    setState(() {
      _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
      _zonas = zonas;
      _lugares = lugares;
    });

    _resolvedor.inicializar(_zonas);

    // 2. Esperar a que Bluetooth este encendido
    setState(() => _estadoScan = 'Verificando Bluetooth...');
    await _esperarBluetoothEncendido();

    // 3. Iniciar scan
    await _iniciarEscaneoPropio();
  }

  Future<void> _esperarBluetoothEncendido() async {
    // En Android, asegurar que Bluetooth este encendido
    if (!await FlutterBluePlus.isSupported) {
      setState(() => _estadoScan = 'Bluetooth no soportado en este dispositivo');
      return;
    }

    // Esperar a que el adapter este encendido
    var state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.unknown) {
      await Future.delayed(const Duration(seconds: 1));
      state = await FlutterBluePlus.adapterState.first;
    }

    if (state == BluetoothAdapterState.off) {
      // Intentar encender (solo Android)
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        setState(() => _estadoScan = 'Por favor, encendé el Bluetooth');
        return;
      }
    }

    // Esperar confirmacion de encendido
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.off);
  }

  Future<void> _iniciarEscaneoPropio() async {
    var permisos = await [Permission.bluetoothScan, Permission.location].request();
    if (!permisos.values.every((s) => s.isGranted)) {
      setState(() => _estadoScan = 'Permisos denegados');
      return;
    }

    // Detener scan previo si existe
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() => _escaneando = true);

    // NUEVO: Suscribirse ANTES de iniciar el scan, usando onScanResults
    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (resultados) {
        if (!mounted) return;
        _actualizarSenales(resultados);
      },
      onError: (e) {
        if (mounted) {
          setState(() => _estadoScan = 'Error en scan: $e');
        }
      },
    );

    // NUEVO: Limpiar resultados previos

    // Iniciar scan con removeIfGone para que desaparezcan beacons no detectados
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
      removeIfGone: const Duration(seconds: 4),
    );

    setState(() => _estadoScan = 'Buscando beacons...');

    // Timeout de seguridad: si no detectamos nada en 10 segundos, mostrar mensaje
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _posicionFinal == null) {
        setState(() => _estadoScan = 'No se detectan beacons suficientes. Acercate a un beacon configurado.');
      }
    });
  }

  void _actualizarSenales(List<ScanResult> resultados) {
    // NUEVO: Reiniciar RSSI de todos los beacons a valor por defecto
    // para que los que no aparecen en esta lectura no sigan con valores viejos
    for (var beacon in _beaconsEnElMapa.values) {
      beacon.rssiFiltrado = -100.0;
    }

    // Procesar solo los resultados actuales
    for (var res in resultados) {
      String mac = res.device.remoteId.str;
      double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
      if (rssiSuave != null && _beaconsEnElMapa.containsKey(mac)) {
        _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave;
      }
    }

    _calcularPosicionRobusta();
  }

  void _calcularPosicionRobusta() {
    var candidatos = _beaconsEnElMapa.values
        .where((b) => b.rssiFiltrado > _umbralRSSI)
        .toList();

    if (candidatos.length < _minBeaconsActivos) {
      setState(() => _estadoScan = 'Beacons detectados: ${candidatos.length} (necesitamos $_minBeaconsActivos)');
      return;
    }

    candidatos.sort((a, b) => b.rssiFiltrado.compareTo(a.rssiFiltrado));
    final activos = candidatos.take(_maxBeaconsParaCalcular).toList();

    double sumaX = 0, sumaY = 0, sumaPesos = 0;
    for (var b in activos) {
      double peso = pow(10, (b.rssiFiltrado + 100) / 20 * _exponentePeso).toDouble();
      sumaX += b.posicion.dx * peso;
      sumaY += b.posicion.dy * peso;
      sumaPesos += peso;
    }
    if (sumaPesos == 0) return;

    final nuevaPosicionRaw = Offset(sumaX / sumaPesos, sumaY / sumaPesos);

    // Nivel 1: EMA
    final nuevaPosicionEMA = _posicionEMA == null
        ? nuevaPosicionRaw
        : Offset(
            _alphaEMA * nuevaPosicionRaw.dx + (1 - _alphaEMA) * _posicionEMA!.dx,
            _alphaEMA * nuevaPosicionRaw.dy + (1 - _alphaEMA) * _posicionEMA!.dy,
          );
    _posicionEMA = nuevaPosicionEMA;

    // Nivel 2: Confirmacion por estabilidad
    if (_posicionConfirmada == null) {
      _posicionConfirmada = nuevaPosicionEMA;
      _contadorEstabilidad = _lecturasParaConfirmar;
    } else {
      final distancia = (nuevaPosicionEMA - _posicionConfirmada!).distance;
      if (distancia < _umbralEstabilidad) {
        _contadorEstabilidad = min(_contadorEstabilidad + 1, _lecturasParaConfirmar + 3);
      } else {
        _contadorEstabilidad--;
      }

      if (_contadorEstabilidad >= _lecturasParaConfirmar) {
        _posicionConfirmada = nuevaPosicionEMA;
      }
      if (_contadorEstabilidad <= -5) {
        _posicionConfirmada = nuevaPosicionEMA;
        _contadorEstabilidad = 0;
      }
    }

    // Nivel 3: Centroid
    if (_posicionConfirmada != null) {
      _historialPosiciones.add(_posicionConfirmada!);
      if (_historialPosiciones.length > _ventanaCentroid) {
        _historialPosiciones.removeAt(0);
      }

      double cx = 0, cy = 0;
      for (var p in _historialPosiciones) {
        cx += p.dx;
        cy += p.dy;
      }
      final nuevaPosicionFinal = Offset(cx / _historialPosiciones.length, cy / _historialPosiciones.length);

      setState(() {
        _posicionFinal = nuevaPosicionFinal;
        _estadoScan = 'Ubicacion estable (${activos.length} beacons)';
      });
    }

    // Recalcular ruta con histeresis
    if (_destinoSeleccionado != null && _posicionFinal != null) {
      final debeRecalcular = _ultimaPosicionRuta == null ||
          (_posicionFinal! - _ultimaPosicionRuta!).distance > _umbralRecalcularRuta;

      if (debeRecalcular) {
        _calcularRuta();
        _ultimaPosicionRuta = _posicionFinal;
      }
    }
  }

  void _calcularRuta() {
    if (_posicionFinal == null || _destinoSeleccionado == null) return;

    final camino = _resolvedor.encontrarCamino(
      _posicionFinal!,
      _destinoSeleccionado!.posicion,
    );

    setState(() {
      _rutaActual = camino;
      if (camino == null) {
        _estadoRuta = 'No se encontro ruta disponible';
      } else {
        final distancia = _calcularDistancia(camino);
        _estadoRuta = 'Ruta a ${_destinoSeleccionado!.nombre}: ${distancia.toStringAsFixed(1)}m';
      }
    });
  }

  double _calcularDistancia(List<Offset> camino) {
    double dist = 0;
    for (int i = 1; i < camino.length; i++) {
      dist += (camino[i] - camino[i - 1]).distance;
    }
    return dist * 50;
  }

  void _seleccionarDestino() async {
    if (_lugares.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay lugares de interes configurados')),
      );
      return;
    }

    final seleccion = await showDialog<LugarInteres>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('A donde queres ir?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _lugares.length,
            itemBuilder: (context, i) {
              final l = _lugares[i];
              return ListTile(
                leading: const Icon(Icons.place, color: Colors.purple),
                title: Text(l.nombre),
                subtitle: l.descripcion != null ? Text(l.descripcion!) : null,
                onTap: () => Navigator.pop(ctx, l),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (seleccion != null) {
      setState(() {
        _destinoSeleccionado = seleccion;
        _rutaActual = null;
        _estadoRuta = 'Calculando ruta...';
        _ultimaPosicionRuta = null;
      });
      _calcularRuta();
    }
  }

  void _cancelarNavegacion() {
    setState(() {
      _destinoSeleccionado = null;
      _rutaActual = null;
      _estadoRuta = '';
      _ultimaPosicionRuta = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navegacion'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_destinoSeleccionado != null)
            IconButton(
              icon: const Icon(Icons.cancel),
              tooltip: 'Cancelar navegacion',
              onPressed: _cancelarNavegacion,
            ),
        ],
      ),
      body: Column(
        children: [
          // Barra de destino
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.indigo[50],
            child: Row(
              children: [
                Expanded(
                  child: _destinoSeleccionado != null
                      ? Row(
                          children: [
                            const Icon(Icons.place, color: Colors.purple),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Destino: ${_destinoSeleccionado!.nombre}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  if (_estadoRuta.isNotEmpty)
                                    Text(
                                      _estadoRuta,
                                      style: TextStyle(fontSize: 12, color: Colors.indigo[700]),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Selecciona un destino para comenzar',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
                ElevatedButton.icon(
                  onPressed: _seleccionarDestino,
                  icon: Icon(_destinoSeleccionado != null ? Icons.edit : Icons.navigation),
                  label: Text(_destinoSeleccionado != null ? 'Cambiar' : 'Destino'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Mapa
          Expanded(
            child: InteractiveViewer(
              child: MapaWidget(
                rutaImagen: widget.rutaImagen,
                beacons: _beaconsEnElMapa,
                zonas: _zonas,
                lugares: _lugares,
                posicionUsuario: _posicionFinal,
                modoEdicion: false,
                ruta: _rutaActual,
              ),
            ),
          ),

          // Estado inferior con info detallada
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_escaneando && _posicionFinal == null)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_escaneando && _posicionFinal == null) const SizedBox(width: 8),
                    Text(
                      _estadoScan,
                      style: TextStyle(color: Colors.indigo[700], fontSize: 14),
                    ),
                  ],
                ),
                if (_posicionFinal != null)
                  Text(
                    'Beacons activos: ${_beaconsEnElMapa.values.where((b) => b.rssiFiltrado > _umbralRSSI).length} / ${_beaconsEnElMapa.length} configurados',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}