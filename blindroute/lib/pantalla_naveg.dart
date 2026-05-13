import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'database.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'procesador_senal.dart';
import 'mapa_widget.dart';
import 'pathfinder.dart';
import 'bluetooth_helper.dart';
import 'orientacion_service.dart';

class PantallaNavegacion extends StatefulWidget {
  final int pisoId;
  final String rutaImagen;
  final ProcesadorSenal? procesadorCompartido;

  const PantallaNavegacion({
    super.key,
    required this.pisoId,
    required this.rutaImagen,
    this.procesadorCompartido,
  });

  @override
  State<PantallaNavegacion> createState() => _PantallaNavegacionState();
}

class _PantallaNavegacionState extends State<PantallaNavegacion> {
  late final ProcesadorSenal _procesador;
  final ResolvedorCaminos _resolvedor = ResolvedorCaminos();
  final OrientacionService _orientacion = OrientacionService();

  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ZonaNoTransitable> _zonas = [];
  List<LugarInteres> _lugares = [];

  // Posicion
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
  Offset? _ultimaPosicionRuta;
  static const double _umbralRecalcularRuta = 0.05;

  // Orientacion
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool _compassDisponible = false;

  // Trilateracion
  static const int _minBeaconsActivos = 3;
  static const int _maxBeaconsParaCalcular = 5;
  static const double _umbralRSSI = -88;
  static const double _exponentePeso = 2.5;

  Timer? _timeoutTimer;
  int _contadorLecturas = 0;

  @override
  void initState() {
    super.initState();
    _procesador = widget.procesadorCompartido ?? ProcesadorSenal();
    _inicializar();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _compassSubscription?.cancel();
    _orientacion.limpiar();
    if (widget.procesadorCompartido == null) {
      BluetoothHelper.detenerScanSeguro();
    }
    super.dispose();
  }

  Future<void> _inicializar() async {
    try {
      final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
      final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
      final lugares = await DatabaseHelper.instance.obtenerLugaresPorPiso(widget.pisoId);

      if (!mounted) return;
      setState(() {
        _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
        _zonas = zonas;
        _lugares = lugares;
      });

      _resolvedor.inicializar(_zonas);
      await _iniciarBrujula();

      if (widget.procesadorCompartido != null && FlutterBluePlus.isScanningNow) {
        if (mounted) {
          setState(() {
            _escaneando = true;
            _estadoScan = 'Continuando escaneo...';
          });
        }
        _suscribirAScan();
        return;
      }

      final ok = await BluetoothHelper.verificarPrecondiciones(context);
      if (!ok) {
        if (mounted) {
          setState(() => _estadoScan = 'Bluetooth o permisos no disponibles');
        }
        return;
      }

      await _iniciarEscaneo();
    } catch (e) {
      if (mounted) {
        setState(() => _estadoScan = 'Error de inicializacion: $e');
      }
    }
  }

  Future<void> _iniciarBrujula() async {
    try {
      _compassDisponible = await FlutterCompass.events != null;
      if (!_compassDisponible) return;

      _compassSubscription = FlutterCompass.events!.listen(
        (CompassEvent event) {
          if (mounted && event.heading != null) {
            _orientacion.actualizarHeadingBrujula(event.heading!);
          }
        },
        onError: (e) {
          _compassDisponible = false;
        },
      );
    } catch (e) {
      _compassDisponible = false;
    }
  }

  void _suscribirAScan() {
    BluetoothHelper.iniciarScanSeguro(
      onResultados: (resultados) => _actualizarSenales(resultados),
      onError: (e) {
        if (mounted) {
          setState(() => _estadoScan = 'Error en scan: $e');
        }
      },
      removeIfGone: const Duration(seconds: 4),
    );

    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _posicionFinal == null) {
        setState(() => _estadoScan = 'Escaneando... esperando señal estable');
      }
    });
  }

  Future<void> _iniciarEscaneo() async {
    if (!mounted) return;
    setState(() => _escaneando = true);

    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      onResultados: (resultados) => _actualizarSenales(resultados),
      onError: (e) {
        if (mounted) {
          setState(() => _estadoScan = 'Error en scan: $e');
        }
      },
      removeIfGone: const Duration(seconds: 4),
    );

    if (!scanOk) {
      if (mounted) {
        setState(() => _estadoScan = 'No se pudo iniciar el escaneo');
      }
      return;
    }

    if (mounted) {
      setState(() => _estadoScan = 'Buscando beacons...');
    }

    _timeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _posicionFinal == null) {
        setState(() => _estadoScan = 'No se detectan beacons suficientes.\nAcercate a un beacon configurado.');
      }
    });
  }

  void _actualizarSenales(List<ScanResult> resultados) {
    if (!mounted) return;
    _contadorLecturas++;

    for (var beacon in _beaconsEnElMapa.values) {
      beacon.rssiFiltrado = -100.0;
    }

    int beaconsDetectados = 0;
    for (var res in resultados) {
      try {
        String mac = res.device.remoteId.str;
        double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
        if (rssiSuave != null && _beaconsEnElMapa.containsKey(mac)) {
          _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave;
          beaconsDetectados++;
        }
      } catch (e) {
        // Ignorar
      }
    }

    if (_contadorLecturas % 10 == 0 && mounted) {
      final activos = _beaconsEnElMapa.values.where((b) => b.rssiFiltrado > _umbralRSSI).length;
      setState(() => _estadoScan = 'Beacons detectados: $activos / ${_beaconsEnElMapa.length}');
    }

    _calcularPosicionRobusta();
  }

  void _calcularPosicionRobusta() {
    if (!mounted) return;

    try {
      var candidatos = _beaconsEnElMapa.values
          .where((b) => b.rssiFiltrado > _umbralRSSI)
          .toList();

      if (candidatos.length < _minBeaconsActivos) {
        if (mounted) {
          setState(() => _estadoScan = 'Beacons cercanos: ${candidatos.length} (necesitamos $_minBeaconsActivos)');
        }
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

      final nuevaPosicionEMA = _posicionEMA == null
          ? nuevaPosicionRaw
          : Offset(
              _alphaEMA * nuevaPosicionRaw.dx + (1 - _alphaEMA) * _posicionEMA!.dx,
              _alphaEMA * nuevaPosicionRaw.dy + (1 - _alphaEMA) * _posicionEMA!.dy,
            );
      _posicionEMA = nuevaPosicionEMA;

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

        // NUEVO: Actualizar orientacion por movimiento (modo bolsillo)
        _orientacion.actualizarPosicion(nuevaPosicionFinal);

        if (mounted) {
          setState(() {
            _posicionFinal = nuevaPosicionFinal;
            _estadoScan = 'Ubicacion estable (${activos.length} beacons)';
          });
        }
      }

      if (_destinoSeleccionado != null && _posicionFinal != null) {
        final debeRecalcular = _ultimaPosicionRuta == null ||
            (_posicionFinal! - _ultimaPosicionRuta!).distance > _umbralRecalcularRuta;

        if (debeRecalcular) {
          _calcularRuta();
          _ultimaPosicionRuta = _posicionFinal;
        }
      }
    } catch (e) {
      // Ignorar
    }
  }

  void _calcularRuta() {
    if (_posicionFinal == null || _destinoSeleccionado == null) return;

    try {
      final camino = _resolvedor.encontrarCamino(
        _posicionFinal!,
        _destinoSeleccionado!.posicion,
      );

      if (mounted) {
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
    } catch (e) {
      // Ignorar
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay lugares de interes configurados')),
        );
      }
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

    if (seleccion != null && mounted) {
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
    if (mounted) {
      setState(() {
        _destinoSeleccionado = null;
        _rutaActual = null;
        _estadoRuta = '';
        _ultimaPosicionRuta = null;
      });
    }
  }

  // Widget de brujula / orientacion
  Widget _buildOrientacion() {
    final heading = _orientacion.heading;
    if (heading == null) {
      return const SizedBox.shrink();
    }

    final direccion = OrientacionService.direccionCardinal(heading);
    final icono = OrientacionService.iconoDireccion(heading);
    final modo = _orientacion.usandoMovimiento;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: modo ? Colors.orange[100] : Colors.indigo[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: modo ? Colors.orange[300]! : Colors.indigo[300]!,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            turns: -heading / 360,
            duration: const Duration(milliseconds: 250),
            child: Icon(icono, color: modo ? Colors.orange[800] : Colors.indigo[800], size: 20),
          ),
          const SizedBox(width: 6),
          Text(
            direccion,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: modo ? Colors.orange[800] : Colors.indigo[800],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${heading.toStringAsFixed(0)} grados',
            style: TextStyle(fontSize: 12, color: modo ? Colors.orange[600] : Colors.indigo[600]),
          ),
          if (modo)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.directions_walk, size: 14, color: Colors.orange[600]),
            ),
        ],
      ),
    );
  }

  // Widget de indicacion de giro
  Widget _buildIndicacionGiro() {
    final heading = _orientacion.heading;
    if (heading == null || _posicionFinal == null || _destinoSeleccionado == null) {
      return const SizedBox.shrink();
    }

    final indicacion = OrientacionService.calcularIndicacion(
      headingUsuario: heading,
      posicionUsuario: _posicionFinal!,
      posicionDestino: _destinoSeleccionado!.posicion,
    );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            indicacion.giroNecesario > 0 ? Icons.turn_right : Icons.turn_left,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              indicacion.instruccion,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
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
          // Barra de destino + orientacion
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.indigo[50],
            child: Column(
              children: [
                Row(
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
                const SizedBox(height: 8),
                // Orientacion (brujula o movimiento)
                _buildOrientacion(),
              ],
            ),
          ),

          // Indicacion de giro
          if (_destinoSeleccionado != null) _buildIndicacionGiro(),

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

          // Estado inferior
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
                    Flexible(
                      child: Text(
                        _estadoScan,
                        style: TextStyle(color: Colors.indigo[700], fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
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