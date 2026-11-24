// ═══════════════════════════════════════════════════════════════════════════
//  BlindRoute — Firmware ESP32, auricular A2DP (sólo parlante)
//
//  Celular ──A2DP (SBC)──> ESP32 ──buffer──> I2S ──> MAX98357A ──> parlante
//
//  Para Android es un auricular: clase de dispositivo "Audio/Video, Headphones"
//  y perfil A2DP sink. Todo lo que el celular reproduce (la voz de la app,
//  música, lo que sea) sale por el parlante en tiempo real, sin que la app
//  tenga que hacer nada. El micrófono es el del celular: este firmware NO usa
//  el INMP441 (lo usa esp32_blindroute_audio, que además tiene HFP y SPP).
//
//  ── CÓMO FLUYE EL AUDIO ───────────────────────────────────────────────────
//  1. El celular manda SBC por A2DP. La pila Bluetooth del ESP32 lo decodifica
//     y llama a alRecibirAudio() con PCM de 16 bits estéreo (la frecuencia la
//     elige el celular: casi siempre 44,1 kHz, a veces 48 kHz).
//  2. alRecibirAudio() sólo copia al buffer (un StreamBuffer de FreeRTOS). No
//     hace nada lento: corre en la tarea Bluetooth y no puede demorarse.
//  3. tareaAltavoz() saca del buffer, mezcla L y R en mono y lo escribe por
//     I2S. El MAX98357A es mono: toca un solo canal por trama, así que se
//     manda el mismo valor en los dos para que no importe cuál elija.
//
//  ── BUFFER Y CORTES ────────────────────────────────────────────────────────
//  El enlace Bluetooth entrega el audio a ráfagas y el parlante lo consume a
//  ritmo fijo. El buffer absorbe la diferencia. No empieza a sonar hasta tener
//  PREBUFFER_MS de audio guardado; si se vacía (el celular pausó o hay
//  interferencia) vuelve a esperar ese colchón en vez de sonar entrecortado.
//  Costo: el audio llega con ~100 ms más de retardo. Con la voz de una app de
//  navegación no se nota.
//
//  ── COMANDOS (por el puerto serie Bluetooth, SPP) ─────────────────────────
//    'V'/'v' → versión del firmware (#VERSION ...)
//    'T'/'t' → estado y contadores (#STATS ...)
//  Los mismos comandos funcionan por USB. El audio NO viaja por SPP.
// ═══════════════════════════════════════════════════════════════════════════

#include "BluetoothSerial.h"
#include <driver/i2s.h>
#include "esp_gap_bt_api.h"
#include "esp_a2dp_api.h"
#include "freertos/FreeRTOS.h"
#include "freertos/stream_buffer.h"

#define FW_VERSION  "2.0-a2dp"
#define NOMBRE_BT   "ESP32_BlindRoute"

// ─── PINES (amplificador MAX98357A) ──────────────────────────────────────────
#define AMP_I2S_PORT   I2S_NUM_1
#define AMP_BCLK_IO    26
#define AMP_LRC_IO     27
#define AMP_DIN_IO     14

// ─── AUDIO ───────────────────────────────────────────────────────────────────
#define FRECUENCIA_INICIAL  44100
#define BYTES_POR_TRAMA     4        // 2 canales × 16 bits
#define TRAMAS_POR_BLOQUE   256      // 5,8 ms a 44,1 kHz

// 32 KB de PCM estéreo a 44,1 kHz son ~180 ms. Más grande no ayuda: sólo suma
// retardo cuando el celular se adelanta.
#define TAM_BUFFER_BYTES    32768

// Colchón de audio antes de empezar a sonar. Si hay cortes, subilo (150-200).
// Si el retardo molesta y no hay cortes, bajalo (60-80).
#define PREBUFFER_MS        100

// Volumen por software, en porcentaje. 100 = sin cambios. El volumen de uso
// se regula con el volumen del celular; esto es un tope por si el parlante
// distorsiona.
#define VOLUMEN_PCT         100

BluetoothSerial SerialBT;
StreamBufferHandle_t bufferAudio = NULL;

// Contadores y estado. Los escriben las tareas Bluetooth y del parlante, y los
// lee loop(): por eso son volatile.
volatile uint32_t bytesRecibidos   = 0;
volatile uint32_t bytesDescartados = 0;   // el buffer estaba lleno
volatile uint32_t underruns        = 0;   // el buffer se vació sonando
volatile uint32_t frecuencia       = FRECUENCIA_INICIAL;   // la del I2S
volatile uint32_t frecuenciaPedida = FRECUENCIA_INICIAL;   // la que pidió el celular
volatile bool a2dpConectado      = false;
volatile bool a2dpTransmitiendo  = false;
volatile bool sonando            = false;
volatile bool pedirVaciar        = false;

// ─── A2DP ────────────────────────────────────────────────────────────────────
// Corre en la tarea A2DP de la pila Bluetooth. Sólo copia, nada más.
void alRecibirAudio(const uint8_t* datos, uint32_t largo) {
  bytesRecibidos = bytesRecibidos + largo;
  largo &= ~3u;   // sólo tramas enteras: si se desfasa, L y R se invierten
  if (largo == 0 || bufferAudio == NULL) return;

  // Si no entra completo se descarta completo. Un envío parcial dejaría el
  // buffer con media trama.
  if (xStreamBufferSpacesAvailable(bufferAudio) < largo) {
    bytesDescartados = bytesDescartados + largo;
    return;
  }
  xStreamBufferSend(bufferAudio, datos, largo, 0);
}

void alEventoA2dp(esp_a2d_cb_event_t evento, esp_a2d_cb_param_t* param) {
  switch (evento) {
    case ESP_A2D_CONNECTION_STATE_EVT:
      a2dpConectado = (param->conn_stat.state == ESP_A2D_CONNECTION_STATE_CONNECTED);
      if (!a2dpConectado) {
        a2dpTransmitiendo = false;
        pedirVaciar = true;   // lo atiende la tarea del parlante
      }
      Serial.printf("[A2DP] %s\n", a2dpConectado ? "celular conectado" : "celular desconectado");
      break;

    case ESP_A2D_AUDIO_STATE_EVT:
      a2dpTransmitiendo = (param->audio_stat.state == ESP_A2D_AUDIO_STATE_STARTED);
      Serial.printf("[A2DP] audio %s\n", a2dpTransmitiendo ? "empezó" : "en pausa");
      break;

    case ESP_A2D_AUDIO_CFG_EVT:
      // El celular dice con qué frecuencia va a mandar. El I2S se reconfigura
      // en la tarea del parlante, no acá.
      if (param->audio_cfg.mcc.type == ESP_A2D_MCT_SBC) {
        switch (param->audio_cfg.mcc.cie.sbc_info.samp_freq) {
          case ESP_A2D_SBC_CIE_SF_16K: frecuenciaPedida = 16000; break;
          case ESP_A2D_SBC_CIE_SF_32K: frecuenciaPedida = 32000; break;
          case ESP_A2D_SBC_CIE_SF_44K: frecuenciaPedida = 44100; break;
          case ESP_A2D_SBC_CIE_SF_48K: frecuenciaPedida = 48000; break;
          default: break;
        }
        Serial.printf("[A2DP] SBC a %u Hz\n", (unsigned)frecuenciaPedida);
      }
      break;

    default:
      break;
  }
}

// ─── AMPLIFICADOR ────────────────────────────────────────────────────────────
void initAmplifierI2S() {
  i2s_config_t cfg = {
    .mode                 = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
    .sample_rate          = FRECUENCIA_INICIAL,
    .bits_per_sample      = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format       = I2S_CHANNEL_FMT_RIGHT_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count        = 8,
    .dma_buf_len          = TRAMAS_POR_BLOQUE,
    .use_apll             = false,
    // Si el DMA se queda sin datos manda ceros, no repite el último bloque.
    .tx_desc_auto_clear   = true,
    .fixed_mclk           = 0
  };
  i2s_pin_config_t pins = {
    .mck_io_num   = I2S_PIN_NO_CHANGE,
    .bck_io_num   = AMP_BCLK_IO,
    .ws_io_num    = AMP_LRC_IO,
    .data_out_num = AMP_DIN_IO,
    .data_in_num  = I2S_PIN_NO_CHANGE
  };
  i2s_driver_install(AMP_I2S_PORT, &cfg, 0, NULL);
  i2s_set_pin(AMP_I2S_PORT, &pins);
  i2s_zero_dma_buffer(AMP_I2S_PORT);
}

// Saca audio del buffer y lo manda al parlante. Es la única tarea que escribe
// en el I2S y que vacía el buffer.
void tareaAltavoz(void* arg) {
  static int16_t entrada[TRAMAS_POR_BLOQUE * 2];
  static int16_t salida[TRAMAS_POR_BLOQUE * 2];
  static int16_t silencio[TRAMAS_POR_BLOQUE * 2];   // en ceros
  size_t escritos = 0;

  for (;;) {
    if (pedirVaciar) {
      pedirVaciar = false;
      xStreamBufferReset(bufferAudio);
      sonando = false;
    }

    if (frecuenciaPedida != frecuencia) {
      frecuencia = frecuenciaPedida;
      i2s_set_clk(AMP_I2S_PORT, frecuencia, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_STEREO);
      xStreamBufferReset(bufferAudio);
      sonando = false;
    }

    if (!sonando) {
      size_t prebuffer = (size_t)frecuencia * BYTES_POR_TRAMA * PREBUFFER_MS / 1000;
      if (xStreamBufferBytesAvailable(bufferAudio) >= prebuffer) {
        sonando = true;
      } else {
        // Mientras espera se manda silencio: el I2S sigue con reloj y el
        // amplificador no hace ruido. i2s_write bloquea hasta que el DMA tiene
        // lugar, así que esto también marca el ritmo del bucle.
        i2s_write(AMP_I2S_PORT, silencio, sizeof(silencio), &escritos, portMAX_DELAY);
        continue;
      }
    }

    size_t n = xStreamBufferReceive(bufferAudio, entrada, sizeof(entrada), pdMS_TO_TICKS(30));
    if (n < BYTES_POR_TRAMA) {
      underruns = underruns + 1;
      sonando = false;   // vuelve a juntar el colchón
      continue;
    }

    size_t tramas = n / BYTES_POR_TRAMA;
    for (size_t i = 0; i < tramas; i++) {
      int32_t m = ((int32_t)entrada[2 * i] + (int32_t)entrada[2 * i + 1]) / 2;
      m = m * VOLUMEN_PCT / 100;
      if (m > 32767) m = 32767;
      if (m < -32768) m = -32768;
      salida[2 * i] = salida[2 * i + 1] = (int16_t)m;
    }
    i2s_write(AMP_I2S_PORT, salida, tramas * BYTES_POR_TRAMA, &escritos, portMAX_DELAY);
  }
}

// ─── COMANDOS ────────────────────────────────────────────────────────────────
void responder(const char* texto) {
  Serial.print(texto);
  if (SerialBT.hasClient()) SerialBT.print(texto);
}

void imprimirEstado() {
  char linea[220];
  snprintf(linea, sizeof(linea),
           "#STATS a2dp=%d audio=%d sonando=%d fs=%u buf=%u recibido=%u descartado=%u underruns=%u heap=%u\n",
           (int)a2dpConectado, (int)a2dpTransmitiendo, (int)sonando,
           (unsigned)frecuencia,
           (unsigned)(bufferAudio ? xStreamBufferBytesAvailable(bufferAudio) : 0),
           (unsigned)bytesRecibidos, (unsigned)bytesDescartados, (unsigned)underruns,
           (unsigned)ESP.getFreeHeap());
  responder(linea);
}

void procesarComando(char c) {
  switch (c) {
    case 'V': case 'v':
      responder("#VERSION " FW_VERSION "\n");
      break;
    case 'T': case 't':
      imprimirEstado();
      break;
    default:
      break;   // saltos de línea y cualquier otra cosa se ignoran
  }
}

// ─── ARRANQUE ────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.printf("\nBlindRoute auricular A2DP, firmware %s\n", FW_VERSION);

  bufferAudio = xStreamBufferCreate(TAM_BUFFER_BYTES, 1);
  if (bufferAudio == NULL) {
    Serial.println("Sin memoria para el buffer de audio");
    while (true) delay(1000);
  }

  initAmplifierI2S();
  xTaskCreatePinnedToCore(tareaAltavoz, "altavoz", 4096, NULL, 5, NULL, 1);

  // Bluetooth Clásico. begin() levanta la pila y el puerto serie (SPP), que
  // acá sólo sirve para comandos. De paso deja el equipo visible para emparejar.
  if (!SerialBT.begin(NOMBRE_BT)) {
    Serial.println("No arrancó Bluetooth");
    while (true) delay(1000);
  }

  // Clase de dispositivo: Audio/Video → Headphones, servicios Audio y
  // Rendering. begin() puso una de computadora; esto la pisa y es lo que hace
  // que Android muestre el ícono y trate el equipo como auricular.
  esp_bt_cod_t cod;
  memset(&cod, 0, sizeof(cod));
  cod.major   = ESP_BT_COD_MAJOR_DEV_AV;
  cod.minor   = 0x06;   // Headphones
  cod.service = (uint32_t)ESP_BT_COD_SRVC_AUDIO | (uint32_t)ESP_BT_COD_SRVC_RENDERING;
  if (esp_bt_gap_set_cod(cod, ESP_BT_INIT_COD) != ESP_OK) {
    Serial.println("No se pudo fijar la clase de dispositivo");
  }

  // A2DP sink: el celular manda el audio y la pila lo entrega decodificado.
  if (esp_a2d_register_callback(alEventoA2dp) != ESP_OK ||
      esp_a2d_sink_register_data_callback(alRecibirAudio) != ESP_OK ||
      esp_a2d_sink_init() != ESP_OK) {
    Serial.println("No arrancó A2DP");
    while (true) delay(1000);
  }

  Serial.printf("Listo. Buscá \"%s\" en los ajustes de Bluetooth del celular.\n", NOMBRE_BT);
  Serial.printf("Heap libre: %u bytes\n", (unsigned)ESP.getFreeHeap());
}

void loop() {
  while (SerialBT.available()) procesarComando((char)SerialBT.read());
  while (Serial.available())   procesarComando((char)Serial.read());

  // Mientras suena, una línea de estado cada 5 s por USB.
  static uint32_t ultimo = 0;
  if (a2dpTransmitiendo && millis() - ultimo > 5000) {
    ultimo = millis();
    imprimirEstado();
  }
  delay(5);
}
