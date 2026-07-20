import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper robusto para manejar el ciclo de vida del escaneo Bluetooth.
///
/// Regla principal: el scan BLE es un recurso GLOBAL y ÚNICO.
/// Android limita a ~5 inicios de scan por 30 segundos por app.
/// Por eso nunca llamamos startScan() si ya hay uno activo —
/// solo reutilizamos el stream existente con una nueva suscripción.
class BluetoothHelper {
  static StreamSubscription<List<ScanResult>>? _scanSubscription;
  static StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  static bool _scanIniciado = false;

  // Guardamos los callbacks para poder relanzar el scan al reconectar.
  static void Function(List<ScanResult>)? _onResultadosActual;
  static void Function(Object)? _onErrorActual;

  /// Si es true, detenerScanSeguro() no frena el scan físico.
  /// Se usa al navegar de ModoAutomatico → PantallaNavegacion.
  static bool mantenerScanActivo = false;

  // ─── PRECONDICIONES ───────────────────────────────────────────────────────

  static Future<bool> verificarPrecondiciones(BuildContext context) async {
    if (!await FlutterBluePlus.isSupported) return false;

    var state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        return false;
      }
    }

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      return false;
    }

    var permisos = await [
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    return permisos.values.every((s) => s.isGranted);
  }

  // ─── INICIAR SCAN ─────────────────────────────────────────────────────────

  /// Inicia el escaneo o reutiliza el scan ya activo.
  /// NUNCA llama startScan() si ya hay un scan corriendo —
  /// solo reemplaza el listener. Esto evita el error status=6 de Android.
  ///
  /// Llama a [escucharEstadoAdaptador] internamente para reconectar
  /// automáticamente si el Bluetooth se apaga y vuelve a encenderse.
  static Future<bool> iniciarScanSeguro({
    required void Function(List<ScanResult>) onResultados,
    void Function(Object)? onError,
    Duration? removeIfGone,
  }) async {
    mantenerScanActivo = false;

    // Guardar callbacks para reutilizar en reconexión automática
    _onResultadosActual = onResultados;
    _onErrorActual = onError;

    // Cancelar suscripción anterior sin tocar el scan físico
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      onResultados,
      onError: (e) => onError?.call(e),
    );

    if (!_scanIniciado && !FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.startScan(
          continuousUpdates: true,
          androidScanMode: AndroidScanMode.balanced,
          removeIfGone: removeIfGone ?? const Duration(seconds: 4),
        );
        _scanIniciado = true;
      } catch (e) {
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        _onResultadosActual = null;
        _onErrorActual = null;
        onError?.call(e);
        return false;
      }
    } else {
      _scanIniciado = true;
    }

    // Activar reconexión automática ante cortes de BT
    escucharEstadoAdaptador();

    return true;
  }

  // ─── RECONEXIÓN AUTOMÁTICA ────────────────────────────────────────────────

  /// Escucha el estado del adaptador BT y relanza el scan automáticamente
  /// si se cortó y volvió. Llamado internamente por iniciarScanSeguro().
  ///
  /// Seguro llamar múltiples veces: cancela el listener anterior antes
  /// de crear uno nuevo, evitando suscripciones duplicadas.
  static void escucharEstadoAdaptador() {
    _adapterSubscription?.cancel();
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on &&
          !FlutterBluePlus.isScanningNow &&
          _onResultadosActual != null) {
        // BT volvió a estar disponible: relanzar scan con los mismos callbacks
        _scanIniciado = false;
        iniciarScanSeguro(
          onResultados: _onResultadosActual!,
          onError: _onErrorActual,
        );
      }
    });
  }

  // ─── DETENER SCAN ─────────────────────────────────────────────────────────

  static Future<void> detenerScanSeguro() async {
    // Siempre cancelar el listener del adaptador al detener
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    _onResultadosActual = null;
    _onErrorActual = null;

    if (mantenerScanActivo) {
      // Solo cancelar el listener; el scan físico sigue para la próxima pantalla
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      mantenerScanActivo = false;
      return;
    }

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {
      // Ignorar errores al detener
    } finally {
      _scanIniciado = false;
    }
  }

  // ─── UTILIDAD ─────────────────────────────────────────────────────────────

  static void setStateSeguro(VoidCallback setStateFn, bool mounted) {
    if (mounted) setStateFn();
  }
}