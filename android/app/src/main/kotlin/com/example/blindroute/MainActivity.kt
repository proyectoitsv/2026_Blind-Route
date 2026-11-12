package com.example.blindroute

import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
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
// cuando sin el idioma descargado no se puede entender la voz.
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
                else -> resultado.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        reconocedorDescarga?.destroy()
        reconocedorDescarga = null
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

    companion object {
        private const val CANAL = "blindroute/reconocimiento"
    }
}
