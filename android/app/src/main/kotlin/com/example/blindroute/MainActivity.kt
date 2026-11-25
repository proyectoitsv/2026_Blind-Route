package com.example.blindroute

import android.Manifest
import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ═══════════════════════════════════════════════════════════════════════════
// Reconocer la voz sin internet (ver lib/reconocimiento_telefono.dart)
// ═══════════════════════════════════════════════════════════════════════════
//
// El plugin de voz (speech_to_text) puede reconocer en el teléfono, pero no
// sabe si el idioma está descargado: lo averigua abriendo el micrófono y
// esperando el error. Acá se consulta sin abrirlo y se pide la descarga
// (Android 13 o más: SpeechRecognizer.checkRecognitionSupport y
// triggerModelDownload). También se mira si hay conexión, para avisar
// cuando sin el idioma descargado no se puede entender la voz, si el
// micrófono está desactivado en el teléfono (ver "MICRÓFONO DESACTIVADO") y,
// con un auricular Bluetooth, se le pide su micrófono mientras se escucha
// (ver "MICRÓFONO DEL AURICULAR").
class MainActivity : FlutterActivity() {
    private var canal: MethodChannel? = null

    /// El reconocedor con el que se pidió la descarga: vive hasta que termina.
    private var reconocedorDescarga: SpeechRecognizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val nuevo = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL)
        canal = nuevo
        nuevo.setMethodCallHandler { llamada, resultado ->
            val idioma = llamada.argument<String>("idioma") ?: "es-AR"
            when (llamada.method) {
                "consultarIdiomas" -> consultarIdiomas(idioma, resultado)
                "pedirDescarga" -> resultado.success(pedirDescarga(idioma))
                "hayConexion" -> resultado.success(hayConexion())
                "microfonoBloqueado" -> resultado.success(microfonoBloqueado())
                "pedirDesbloquearMicrofono" -> {
                    pedirDesbloquearMicrofono()
                    resultado.success(null)
                }
                "usarMicrofonoAuricular" -> usarMicrofonoAuricular(resultado)
                "soltarMicrofonoAuricular" -> {
                    soltarMicrofonoAuricular()
                    resultado.success(null)
                }
                else -> resultado.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        reconocedorDescarga?.destroy()
        reconocedorDescarga = null
        soltarMicrofonoAuricular()
        super.onDestroy()
    }

    private fun intentDe(idioma: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, idioma)
        }

    /// Qué idiomas reconoce el teléfono sin internet: los descargados, los
    /// que se están descargando y los que se pueden descargar. Con Android
    /// 12 o menos no se puede saber: "disponible" en false.
    private fun consultarIdiomas(idioma: String, resultado: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        ) {
            resultado.success(mapOf("disponible" to false))
            return
        }
        val reconocedor = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        var respondido = false
        fun responder(datos: Map<String, Any?>) {
            if (respondido) return
            respondido = true
            reconocedor.destroy()
            resultado.success(datos)
        }
        reconocedor.checkRecognitionSupport(
            intentDe(idioma),
            mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(soporte: RecognitionSupport) {
                    responder(
                        mapOf(
                            "disponible" to true,
                            "descargados" to soporte.installedOnDeviceLanguages,
                            "descargando" to soporte.pendingOnDeviceLanguages,
                            "soportados" to soporte.supportedOnDeviceLanguages,
                        )
                    )
                }

                override fun onError(error: Int) {
                    responder(mapOf("disponible" to false, "error" to error))
                }
            },
        )
    }

    /// Pide descargar [idioma] para reconocer sin internet. El sistema puede
    /// pedirle confirmación a la persona. Con Android 14 o más avisa a Dart
    /// el avance y el final ("descargaAvance", "descargaLista",
    /// "descargaFallida"); con 13, Dart lo vuelve a consultar.
    private fun pedirDescarga(idioma: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        ) {
            return false
        }
        reconocedorDescarga?.destroy()
        val reconocedor = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        reconocedorDescarga = reconocedor
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            var ultimoAvance = -10
            reconocedor.triggerModelDownload(
                intentDe(idioma),
                mainExecutor,
                object : ModelDownloadListener {
                    override fun onProgress(completado: Int) {
                        // De a 10 %: no hace falta cada punto.
                        if (completado - ultimoAvance < 10) return
                        ultimoAvance = completado
                        canal?.invokeMethod("descargaAvance", completado)
                    }

                    override fun onSuccess() {
                        canal?.invokeMethod("descargaLista", idioma)
                        soltar(reconocedor)
                    }

                    override fun onScheduled() {
                        canal?.invokeMethod("descargaProgramada", idioma)
                    }

                    override fun onError(error: Int) {
                        canal?.invokeMethod("descargaFallida", error)
                        soltar(reconocedor)
                    }
                },
            )
        } else {
            reconocedor.triggerModelDownload(intentDe(idioma))
        }
        return true
    }

    private fun soltar(reconocedor: SpeechRecognizer) {
        if (reconocedorDescarga === reconocedor) reconocedorDescarga = null
        reconocedor.destroy()
    }

    /// Si hay una conexión a internet que anda (validada por el sistema).
    private fun hayConexion(): Boolean {
        val conexiones = getSystemService(ConnectivityManager::class.java) ?: return true
        val red = conexiones.activeNetwork ?: return false
        val capacidades = conexiones.getNetworkCapabilities(red) ?: return false
        return capacidades.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capacidades.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    // ═══ MICRÓFONO DESACTIVADO ═══
    // Desde Android 12 el micrófono se puede desactivar para todas las apps
    // (el botón "Acceso al micrófono" del panel rápido). El permiso de la app
    // sigue dado: el reconocedor arranca, pero recibe silencio, y la app
    // decía "No te escuché". El aviso del sistema para volver a activarlo
    // sale sólo cuando la app que está en pantalla usa el micrófono, y acá
    // lo usa el reconocedor de voz (otra app), así que nunca salía.

    private fun permisoMicrofono() =
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /// Si el micrófono está desactivado en el teléfono. Desactivado, Android
    /// les restringe a todas las apps la operación de grabar audio, aunque
    /// tengan el permiso: se mira eso, sin abrir el micrófono. Con el permiso
    /// negado responde false (eso lo atiende Dart por su lado).
    private fun microfonoBloqueado(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || !permisoMicrofono()) return false
        val operaciones = getSystemService(AppOpsManager::class.java) ?: return false
        // "Raw": el modo tal cual, sin evaluar si la app está en primer plano
        // (en segundo plano daría "ignorado" aunque el micrófono esté activo).
        val modo = operaciones.unsafeCheckOpRawNoThrow(
            AppOpsManager.OPSTR_RECORD_AUDIO,
            Process.myUid(),
            packageName,
        )
        Log.d(ETIQUETA, "Operación de grabar audio: modo $modo")
        return modo == AppOpsManager.MODE_IGNORED
    }

    /// Abre el micrófono un instante desde la app, que está en pantalla: con
    /// el micrófono desactivado, Android muestra su aviso para activarlo.
    /// Lo grabado es silencio y se descarta.
    @SuppressLint("MissingPermission") // permisoMicrofono() lo comprueba
    private fun pedirDesbloquearMicrofono() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || !permisoMicrofono()) return
        Thread {
            try {
                val muestreo = 16000
                val canalAudio = AudioFormat.CHANNEL_IN_MONO
                val formato = AudioFormat.ENCODING_PCM_16BIT
                val tam = AudioRecord.getMinBufferSize(muestreo, canalAudio, formato)
                if (tam <= 0) return@Thread
                val grabador =
                    AudioRecord(MediaRecorder.AudioSource.MIC, muestreo, canalAudio, formato, tam)
                try {
                    if (grabador.state != AudioRecord.STATE_INITIALIZED) return@Thread
                    grabador.startRecording()
                    grabador.read(ByteArray(tam), 0, tam)
                    grabador.stop()
                } finally {
                    grabador.release()
                }
            } catch (e: Exception) {
                Log.w(ETIQUETA, "No se pudo abrir el micrófono para pedir activarlo: $e")
            }
        }.start()
    }

    // ═══ MICRÓFONO DEL AURICULAR ═══
    // Android le pasa a una app el micrófono de un auricular Bluetooth sólo
    // si la app lo pide: si no, se graba con el del teléfono aunque el
    // auricular esté conectado. El micrófono del auricular viaja por el canal
    // de voz de manos libres (HFP), que se abre aparte del de la música
    // (A2DP), igual que en una llamada. Mientras está abierto, todo lo que se
    // graba en el teléfono, también lo que graba el reconocedor de voz (que
    // es otra app), sale del auricular.
    //
    // Se pide al empezar cada escucha y se suelta al terminarla. Con Android
    // 12 o más, con setCommunicationDevice; con uno anterior, con
    // startBluetoothSco, que es lo que la reemplazó. El canal tarda en abrirse
    // (medio segundo a un par de segundos según el teléfono y el auricular),
    // así que se espera el aviso de que quedó abierto antes de responder:
    // si el reconocedor arrancara antes, lo primero que dice la persona se
    // grabaría con el micrófono del teléfono o se perdería. Si no se abre en
    // [ESPERA_CANAL_MS], se suelta y se escucha con el del teléfono.
    //
    // El modo de comunicación (el de las apps de llamadas) se pone sólo
    // mientras dura la escucha: algunos teléfonos no mandan la grabación al
    // auricular fuera de ese modo. Hace falta el permiso MODIFY_AUDIO_SETTINGS
    // (normal: Android lo da al instalar, sin preguntar).
    //
    // El plugin de voz tiene su propia forma de usar el auricular (pide el
    // "reconocimiento de voz" de manos libres), pero sólo con Android 12 o
    // más, con el permiso de dispositivos cercanos dado y sin esperar a que el
    // canal se abra. Se la apaga desde Dart (androidNoBluetooth) para que haya
    // un solo camino.

    private val audio by lazy { getSystemService(AudioManager::class.java) }
    private val hiloPrincipal = Handler(Looper.getMainLooper())

    /// Si el canal del auricular está pedido (abierto o abriéndose).
    private var auricularPedido = false
    private var modoAnterior = AudioManager.MODE_NORMAL
    private var receptorCanal: BroadcastReceiver? = null
    private var esperaCanal: Runnable? = null

    /// Quién espera saber si el canal se abrió (Dart).
    private var respuestaCanal: MethodChannel.Result? = null

    /// El auricular Bluetooth con micrófono que está conectado, o null.
    private fun auricularConectado(am: AudioManager): AudioDeviceInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            }
        } else if (am.isBluetoothScoAvailableOffCall) {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            }
        } else {
            null
        }

    /// Si el canal pedido sigue abierto de verdad. La marca auricularPedido no
    /// alcanza: Android puede cerrarlo por su cuenta. En la prueba del
    /// 25/11/2026 le sacó el modo llamada a la app 1,5 s después de que el
    /// reconocedor dejó de grabar (la app no reproducía ni grababa nada
    /// propio) y a los 6 s cortó el canal.
    private fun canalSigueAbierto(am: AudioManager): Boolean {
        if (am.mode != AudioManager.MODE_IN_COMMUNICATION) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.communicationDevice?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        } else {
            @Suppress("DEPRECATION")
            am.isBluetoothScoOn
        }
    }

    /// Pide el micrófono del auricular y responde true cuando el canal quedó
    /// abierto; false si no hay auricular o no se abrió a tiempo.
    private fun usarMicrofonoAuricular(resultado: MethodChannel.Result) {
        val am = audio
        if (am == null) {
            Log.w(ETIQUETA, "Micrófono del auricular: no hay servicio de audio.")
            resultado.success(false)
            return
        }
        if (respuestaCanal != null) {
            Log.w(ETIQUETA, "Micrófono del auricular: ya hay un pedido esperando.")
            resultado.success(false)
            return
        }
        if (auricularPedido) {
            if (canalSigueAbierto(am)) {
                Log.d(ETIQUETA, "Micrófono del auricular: ya estaba abierto.")
                resultado.success(true)
                return
            }
            // Android lo cerró por su cuenta: se suelta lo que quedó y se
            // pide de nuevo.
            Log.w(ETIQUETA, "Micrófono del auricular: Android cerró el canal " +
                "(modo ${am.mode}); se pide de nuevo.")
            soltarMicrofonoAuricular()
        }
        val auricular = auricularConectado(am)
        if (auricular == null) {
            // Los dispositivos que Android ofrece para comunicación: si el
            // auricular no está, no tiene conectado el perfil de llamadas.
            val tipos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.availableCommunicationDevices.joinToString { "${it.type}" }
            } else {
                "(Android ${Build.VERSION.SDK_INT})"
            }
            Log.d(ETIQUETA, "Micrófono del auricular: no hay auricular con micrófono " +
                "(dispositivos de comunicación: $tipos).")
            resultado.success(false)
            return
        }
        Log.d(ETIQUETA, "Micrófono del auricular: se pide el de ${auricular.productName}.")
        auricularPedido = true
        respuestaCanal = resultado
        modoAnterior = am.mode

        // Se escucha el estado del canal ANTES de pedirlo, y sólo cuenta un
        // aviso nuevo. El aviso es "sticky": al registrarse llega enseguida
        // el último que mandó Android, que puede ser viejo. En la prueba del
        // 24/11/2026 llegó "abierto" de un canal que ya se había cerrado: la
        // app creyó escuchar con el auricular y escuchó con el teléfono.
        val receptor = object : BroadcastReceiver() {
            override fun onReceive(contexto: Context?, aviso: Intent?) {
                if (isInitialStickyBroadcast) return
                val estado = aviso?.getIntExtra(
                    AudioManager.EXTRA_SCO_AUDIO_STATE,
                    AudioManager.SCO_AUDIO_STATE_ERROR,
                )
                if (estado == AudioManager.SCO_AUDIO_STATE_CONNECTED) responderCanal(true)
            }
        }
        receptorCanal = receptor
        val filtro = IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receptor, filtro, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receptor, filtro)
        }

        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val pedido = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.setCommunicationDevice(auricular)
        } else {
            @Suppress("DEPRECATION")
            am.startBluetoothSco()
            @Suppress("DEPRECATION")
            am.isBluetoothScoOn = true
            true
        }
        if (!pedido) {
            Log.w(ETIQUETA, "El teléfono no aceptó usar el micrófono del auricular.")
            responderCanal(false)
            return
        }
        val espera = Runnable {
            // Sin el aviso de que se abrió, se escucha con el teléfono. Que
            // Android tenga elegido el auricular como dispositivo de
            // comunicación no alcanza: lo elige aunque el canal no se abra.
            Log.w(ETIQUETA, "El canal del auricular no se abrió en $ESPERA_CANAL_MS ms: " +
                "se escucha con el micrófono del teléfono.")
            responderCanal(false)
        }
        esperaCanal = espera
        hiloPrincipal.postDelayed(espera, ESPERA_CANAL_MS)
    }

    /// Le dice a Dart si el canal se abrió (una sola vez por pedido). Si no
    /// se abrió, lo suelta.
    private fun responderCanal(abierto: Boolean) {
        val respuesta = respuestaCanal ?: return
        respuestaCanal = null
        esperaCanal?.let { hiloPrincipal.removeCallbacks(it) }
        esperaCanal = null
        if (abierto) {
            Log.d(ETIQUETA, "Micrófono del auricular abierto.")
        } else {
            soltarMicrofonoAuricular()
        }
        respuesta.success(abierto)
    }

    /// Suelta el canal del auricular y deja el audio como estaba. Si alguien
    /// esperaba que se abriera, recibe false.
    private fun soltarMicrofonoAuricular() {
        if (!auricularPedido) return
        auricularPedido = false
        receptorCanal?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Ya no estaba registrado.
            }
        }
        receptorCanal = null
        esperaCanal?.let { hiloPrincipal.removeCallbacks(it) }
        esperaCanal = null
        respuestaCanal?.success(false)
        respuestaCanal = null
        val am = audio ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            am.isBluetoothScoOn = false
            @Suppress("DEPRECATION")
            am.stopBluetoothSco()
        }
        am.mode = modoAnterior
    }

    companion object {
        private const val CANAL = "blindroute/reconocimiento"
        private const val ETIQUETA = "BlindRoute"

        /// Lo que se espera a que se abra el canal del auricular.
        private const val ESPERA_CANAL_MS = 3000L
    }
}
