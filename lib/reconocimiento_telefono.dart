// Reconocimiento de voz en el teléfono, sin internet
// (ReconocimientoEnTelefono).
//
// Pregunta al código de Android si el español está descargado para reconocer
// sin conexión, pide la descarga, dice si hay internet y si el micrófono está
// desactivado en el teléfono, y abre y suelta el micrófono de un auricular
// Bluetooth mientras se escucha.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter/services.dart';

// El reconocedor de Google manda el audio a sus servidores: sin conexión no
// entiende el destino. Si el español está descargado en el teléfono, lo
// reconoce ahí mismo. El plugin de voz no sabe consultarlo sin abrir el
// micrófono, así que la consulta, el pedido de descarga y si hay conexión
// los responde el código de Android (MainActivity.kt). Necesita Android 13
// o más; con uno anterior, [ReconocimientoEnTelefono.consultar] dice
// [EstadoIdioma.noDisponible] y la voz sigue por internet.
//
// El mismo código de Android dice también si el micrófono está desactivado
// en el teléfono (Android 12 o más) y hace que el sistema pregunte si se lo
// activa (ver [ReconocimientoEnTelefono.microfonoBloqueado]). Y, con un
// auricular Bluetooth conectado, abre su micrófono para la escucha y lo
// suelta al terminar (ver [ReconocimientoEnTelefono.usarMicrofonoAuricular]).

/// Cómo está el español para reconocer la voz en el teléfono.
enum EstadoIdioma {
  /// Descargado: se reconoce sin internet.
  descargado,

  /// Se está descargando.
  descargando,

  /// El teléfono lo puede reconocer, pero falta descargarlo.
  sinDescargar,

  /// Este teléfono no reconoce español sin internet, o no se puede saber
  /// (Android 12 o menos).
  noDisponible,
}

/// Lo que se averiguó: el estado y con qué idioma ("es-AR", "es-US").
@immutable
class ConsultaIdioma {
  const ConsultaIdioma(this.estado, [this.idioma]);

  final EstadoIdioma estado;

  /// El idioma con el que se reconoce (o se descarga). Null en
  /// [EstadoIdioma.noDisponible].
  final String? idioma;

  @override
  String toString() => '${estado.name}${idioma == null ? '' : ' ($idioma)'}';
}

/// El código de Android para reconocer la voz sin internet.
class ReconocimientoEnTelefono {
  ReconocimientoEnTelefono._();

  static const MethodChannel _canal = MethodChannel('blindroute/reconocimiento');

  /// Qué idioma usar, de lo que respondió el teléfono. Primero [preferido]
  /// ("es-AR"); si no, cualquier español. Descargado gana sobre descargando,
  /// y descargando sobre sin descargar: un español de otro país ya
  /// descargado sirve más que el preferido por descargar.
  static ConsultaIdioma elegir(
    String preferido, {
    required List<String> descargados,
    required List<String> descargando,
    required List<String> soportados,
  }) {
    String normal(String idioma) => idioma.toLowerCase().replaceAll('_', '-');
    final buscado = normal(preferido);
    String? deLista(List<String> lista) {
      final normales = lista.map(normal).toList();
      if (normales.contains(buscado)) return preferido.replaceAll('_', '-');
      for (final (i, n) in normales.indexed) {
        if (n == 'es' || n.startsWith('es-')) return lista[i];
      }
      return null;
    }

    final descargado = deLista(descargados);
    if (descargado != null) {
      return ConsultaIdioma(EstadoIdioma.descargado, descargado);
    }
    final enCurso = deLista(descargando);
    if (enCurso != null) {
      return ConsultaIdioma(EstadoIdioma.descargando, enCurso);
    }
    final soportado = deLista(soportados);
    if (soportado != null) {
      return ConsultaIdioma(EstadoIdioma.sinDescargar, soportado);
    }
    return const ConsultaIdioma(EstadoIdioma.noDisponible);
  }

  /// Cómo está el español en este teléfono.
  static Future<ConsultaIdioma> consultar(String preferido) async {
    try {
      final datos = await _canal.invokeMapMethod<String, Object?>(
        'consultarIdiomas',
        {'idioma': preferido},
      );
      if (datos == null || datos['disponible'] != true) {
        return const ConsultaIdioma(EstadoIdioma.noDisponible);
      }
      List<String> lista(String clave) =>
          (datos[clave] as List<Object?>? ?? const []).whereType<String>().toList();
      return elegir(
        preferido,
        descargados: lista('descargados'),
        descargando: lista('descargando'),
        soportados: lista('soportados'),
      );
    } on MissingPluginException {
      // Fuera de Android (las pruebas): no hay a quién preguntar.
      return const ConsultaIdioma(EstadoIdioma.noDisponible);
    } on PlatformException catch (e) {
      debugPrint('[Voz] No se pudo consultar el idioma: $e');
      return const ConsultaIdioma(EstadoIdioma.noDisponible);
    }
  }

  /// Pide descargar [idioma]. false si este teléfono no lo permite.
  static Future<bool> pedirDescarga(String idioma) async {
    try {
      return await _canal.invokeMethod<bool>(
            'pedirDescarga',
            {'idioma': idioma},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[Voz] No se pudo pedir la descarga: $e');
      return false;
    }
  }

  /// Si hay una conexión a internet que anda. Si no se puede saber, true:
  /// mejor intentar que avisar de más.
  static Future<bool> hayConexion() async {
    try {
      return await _canal.invokeMethod<bool>('hayConexion') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// Si el micrófono está desactivado en el teléfono (el botón "Acceso al
  /// micrófono" del panel rápido, Android 12 o más). Con el permiso de la
  /// app negado, o si no se puede saber, false.
  static Future<bool> microfonoBloqueado() async {
    try {
      return await _canal.invokeMethod<bool>('microfonoBloqueado') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[Voz] No se pudo saber si el micrófono está activado: $e');
      return false;
    }
  }

  /// Con el micrófono desactivado en el teléfono, hace que Android muestre
  /// su aviso para activarlo (ver MainActivity.kt).
  static Future<void> pedirDesbloquearMicrofono() async {
    try {
      await _canal.invokeMethod<void>('pedirDesbloquearMicrofono');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[Voz] No se pudo pedir activar el micrófono: $e');
    }
  }

  /// Lo que se espera la respuesta de Android al pedir el micrófono del
  /// auricular. Android espera hasta 3 s a que se abra el canal; esto es por
  /// si no contesta nunca.
  static const Duration esperaAuricular = Duration(seconds: 4);

  /// Con un auricular Bluetooth conectado, le pide a Android su micrófono (el
  /// canal de voz de manos libres, como en una llamada) y espera a que quede
  /// abierto. true si quedó abierto: se escucha con el auricular y hay que
  /// soltarlo con [soltarMicrofonoAuricular] al terminar. false si no hay
  /// auricular, si no se abrió a tiempo o fuera de Android: se escucha con el
  /// micrófono del teléfono, como siempre.
  static Future<bool> usarMicrofonoAuricular() async {
    try {
      final abierto = await _canal
          .invokeMethod<bool>('usarMicrofonoAuricular')
          .timeout(esperaAuricular);
      return abierto ?? false;
    } on TimeoutException {
      // Si se abre después, que no quede abierto sin que nadie lo sepa.
      unawaited(soltarMicrofonoAuricular());
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[Voz] No se pudo pedir el micrófono del auricular: $e');
      return false;
    }
  }

  /// Suelta el micrófono del auricular y deja el audio como estaba (la
  /// música vuelve al canal de siempre).
  static Future<void> soltarMicrofonoAuricular() async {
    try {
      await _canal.invokeMethod<void>('soltarMicrofonoAuricular');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[Voz] No se pudo soltar el micrófono del auricular: $e');
    }
  }

  /// Avisos de la descarga (Android 14 o más): [alTerminar] con true si
  /// quedó lista, false si falló.
  static void escucharDescarga({
    required void Function(bool lista) alTerminar,
  }) {
    _canal.setMethodCallHandler((llamada) async {
      switch (llamada.method) {
        case 'descargaAvance':
          debugPrint('[Voz] Descarga del español: ${llamada.arguments} %.');
        case 'descargaProgramada':
          debugPrint('[Voz] Descarga del español programada por el sistema.');
        case 'descargaLista':
          debugPrint('[Voz] Descarga del español: lista.');
          alTerminar(true);
        case 'descargaFallida':
          debugPrint('[Voz] Descarga del español fallida '
              '(error ${llamada.arguments}).');
          alTerminar(false);
      }
    });
  }
}
