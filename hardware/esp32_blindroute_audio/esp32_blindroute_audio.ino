// ═══════════════════════════════════════════════════════════════════════════
//  BlindRoute — Firmware ESP32  (bidireccional)
//
//  INMP441 (I2S RX) ──μ-law──> SPP ──> app        [capturar voz del usuario]
//  app ──> SPP ──μ-law──> MAX98357A (I2S TX)      [reproducir voz de la app]
//
//  ── POR QUÉ ES HALF-DUPLEX (una cosa a la vez) ────────────────────────────
//  El firmware NUNCA captura y reproduce al mismo tiempo. Es una decisión
//  deliberada, por tres motivos independientes:
//
//   1. ANCHO DE BANDA. Medimos que el enlace SPP se satura: a 16 kHz el ESP32
//      descartaba paquetes y el caudal caía en rampa (33→24→15→8 bloques/s).
//      Las dos direcciones comparten la misma radio. Sumarlas garantiza cortes.
//
//   2. REALIMENTACIÓN ACÚSTICA. El micrófono y el parlante están en el mismo
//      auricular, a centímetros. Si capturás mientras reproducís, el micrófono
//      graba al parlante. Eso se manda al STT y arruina el reconocimiento.
//      Evitarlo de raíz es gratis; cancelar el eco por software no lo es.
//
//   3. CPU y DMA. Los dos puertos I2S activos más la pila Bluetooth en un solo
//      núcleo dejan poco margen. Uno de los dos DMA se desborda.
//
//  Para navegación no es una limitación real: o el usuario habla, o la app le
//  responde. Nunca las dos cosas a la vez.
//
//  ── PROTOCOLO ─────────────────────────────────────────────────────────────
//  ESP32 → app (audio del micrófono, sin cambios):
//    [0xAA][len_hi][len_lo][...μ-law 8-bit mono...]
//
//  app → ESP32 (audio para reproducir, NUEVO):
//    [0xBB][len_hi][len_lo][...μ-law 8-bit mono...]   bloque de audio
//    [0xBE]                                            fin de stream
//
//  app → ESP32 (comandos de un byte, sin cambios):
//    'D'/'d' → reproduce /derecha.wav desde LittleFS
//    'I'/'i' → reproduce /izquierda.wav desde LittleFS
//    'M'/'m' → empieza a capturar y enviar audio
//    'S'/'s' → deja de capturar
//    'P'/'p' → corta la reproducción en curso y vacía el buffer
//    'T'/'t' → telemetría en texto ASCII (ver comando 'T' abajo)
//    'V'/'v' → versión del firmware, para que la app compruebe el dispositivo
//
//  0xBB y 0xBE están fuera del rango ASCII (0x00–0x7F), así que no pueden
//  confundirse con un comando por más que el audio contenga esos valores:
//  el parser sabe en qué estado está.
// ═══════════════════════════════════════════════════════════════════════════

#include "BluetoothSerial.h"
#include <driver/i2s.h>
#include <LittleFS.h>
#include <math.h>

// Perfiles de audio Bluetooth clásico (A2DP y HFP). Están en el núcleo del
// ESP32 y se usan a través de su API nativa.
#include "esp_bt.h"
#include "esp_bt_device.h"
#include "esp_bt_main.h"
#include "esp_gap_bt_api.h"
#include "esp_a2dp_api.h"
#include "esp_a2dp_legacy_api.h"  // esp_a2d_sink_register_data_callback(): audio PCM decodificado
#include "esp_hf_client_api.h"
#include "esp_hf_client_legacy_api.h"
#include "freertos/FreeRTOS.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"

BluetoothSerial SerialBT;

// Filtro biquad (una etapa de ecualizador). Va acá arriba y no junto al
// ecualizador porque Arduino genera los prototipos de las funciones antes de la
// primera función del archivo, y varias reciben un Biquad.
struct Biquad {
  float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  float z1 = 0, z2 = 0;
  inline float proceso(float x) {
    const float y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }
};

// Versión del firmware. La app la pide con el comando 'V' para comprobar que el
// dispositivo es el correcto antes de usarlo.
#define FW_VERSION  "2.0"

// El callback de Bluetooth corre en otra tarea del sistema. Solo marca el
// cambio: el loop lo atiende y es el único que toca el buffer de audio.
// Sin esto, el audio de una sesión cortada a la mitad queda en el anillo y
// suena al principio de la siguiente.
volatile bool clienteCambio = false;

void alCambiarConexion(esp_spp_cb_event_t event, esp_spp_cb_param_t* param) {
  if (event == ESP_SPP_SRV_OPEN_EVT || event == ESP_SPP_CLOSE_EVT) {
    clienteCambio = true;
  }
}

// ─── PINES ───────────────────────────────────────────────────────────────────
// Micrófono INMP441, según el cableado de la placa nueva:
//   VDD → 3V3    GND y L/R → GND    SCK → GPIO25    WS → GPIO33    SD → GPIO34
// GPIO34 es solo entrada: sirve para SD, que solo se lee. Si cambiás el
// cableado, cambiá estos defines y nada más.
#define MIC_I2S_PORT   I2S_NUM_0
#define MIC_SCK_IO     25
#define MIC_SD_IO      34
#define MIC_WS_IO      33

#define AMP_I2S_PORT   I2S_NUM_1
#define AMP_BCLK_IO    26
#define AMP_LRC_IO     27
#define AMP_DIN_IO     14

// 8000 Hz. El enlace SPP no sostiene 16 kHz: medido dio 41 de los 62 bloques/s
// necesarios, o sea que se perdía un tercio del audio. A 8 kHz con μ-law son
// 8 KB/s por dirección. Google STT lo acepta (es calidad telefónica).
// SI LO CAMBIÁS, cambiá TAMBIÉN Esp32AudioService.sampleRate en el Dart
// y SAMPLE_RATE en los scripts de Python.
#define SAMPLE_RATE    8000

// ─── PROTOCOLO ───────────────────────────────────────────────────────────────
#define AUDIO_MARKER   0xAA   // ESP32 → app : bloque de audio del micrófono
#define PLAY_MARKER    0xBB   // app → ESP32 : bloque de audio para reproducir
#define PLAY_EOS       0xBE   // app → ESP32 : fin de stream

#define MUESTRAS_POR_BLOQUE  256

#define RAW_BUF_BYTES  (MUESTRAS_POR_BLOQUE * 4)   // 32 bits por muestra

// ─── COMPRESIÓN μ-LAW ────────────────────────────────────────────────────────
// USAR_ULAW = 1 → cada muestra viaja en 1 byte en vez de 2. La mitad de datos
// por el aire, en las DOS direcciones.
//
// μ-law (G.711) es el códec de la telefonía fija. Cuantización logarítmica:
// más resolución en las amplitudes bajas, que es donde está la voz. Error
// medido en ida y vuelta: 1,1% promedio. Inaudible para habla.
//
// Google STT lo acepta nativamente (encoding "MULAW"), así que el audio del
// micrófono va tal cual, sin descomprimir del lado de la app.
#define USAR_ULAW      1

#if USAR_ULAW
  #define OUT_BUF_BYTES  (MUESTRAS_POR_BLOQUE)
#else
  #define OUT_BUF_BYTES  (MUESTRAS_POR_BLOQUE * 2)
#endif

// ─── GANANCIA DEL MICRÓFONO ──────────────────────────────────────────────────
// El INMP441 entrega 24 bits alineados a la izquierda en una trama de 32.
// Cada unidad de MIC_SHIFT es un factor de 2.
//
// HISTORIAL MEDIDO EN ESTE EQUIPO:
//   shift 14, SIN filtro DC → pico 100% (saturado), RMS 19448
//   shift 17, CON filtro DC → pico 4.6%,            RMS 254
//   shift 15, CON filtro DC → pico 42.6%,           RMS 2378   ← elegido
//
//   MIC_SHIFT = 16 → si 15 satura
//   MIC_SHIFT = 15 → valor actual, verificado escuchando el WAV
//   MIC_SHIFT = 14 → si queda corto
#define MIC_SHIFT      15

// ─── VOLUMEN DE REPRODUCCIÓN ─────────────────────────────────────────────────
// Escala aplicada al audio que llega de la app, en porcentaje.
// El MAX98357A tiene su ganancia fija por hardware (pin Gain), así que esto es
// el único control de volumen por software que hay.
//   100 = sin cambios (recomendado: que la app mande el nivel que quiere)
//   200 = el doble, con recorte si el audio ya venía fuerte
#define PLAY_VOLUMEN   100

// ─── BUFFER DE REPRODUCCIÓN ──────────────────────────────────────────────────
// Anillo donde se acumula el audio que llega de la app antes de mandarlo al
// parlante. Existe porque el Bluetooth entrega a los tirones y el I2S consume
// a ritmo constante y exacto (8000 muestras/s). Sin buffer, cada bache del
// enlace sería un corte audible.
//
// 16 KB = 2 segundos de audio a 8 kHz μ-law.
#define RING_BYTES     16384

// Cuánto hay que acumular antes de empezar a sonar. Es el colchón contra los
// baches: con 0,4 s el enlace puede quedarse mudo 400 ms sin que se escuche.
// Más prebuffer = más robusto pero más demora hasta el primer sonido.
// A 8 KB/s, 3200 bytes = 400 ms.
#define PREBUFFER_BYTES  3200

// Cuántas muestras se mandan al I2S por vuelta de loop. Chico a propósito:
// ver alimentarAltavoz().
#define FEED_MUESTRAS  128

// ─── ESTADO: CAPTURA ─────────────────────────────────────────────────────────
enum Modo { MODO_ESPERA, MODO_AUDIO };
Modo modoActual = MODO_ESPERA;

int32_t rawBuf[MUESTRAS_POR_BLOQUE];

// Buffer único de transmisión: [0xAA][hi][lo][...audio...] en una sola
// escritura. Cada SerialBT.write() tiene overhead de la pila Bluetooth, así
// que juntarlos baja a la mitad las operaciones sobre el enlace.
uint8_t txBuf[3 + OUT_BUF_BYTES];
uint8_t* const outBuf = txBuf + 3;

#define BLOQUES_A_DESCARTAR  6
int bloquesDescartados = 0;

uint32_t bloquesEnviados = 0;
uint32_t bloquesDescartadosTx = 0;

// ─── ESTADO: REPRODUCCIÓN ────────────────────────────────────────────────────
enum EstadoPlay {
  PLAY_IDLE,        // nada que reproducir
  PLAY_BUFFERING,   // llegando audio, esperando llenar el prebuffer
  PLAY_SONANDO,     // alimentando el I2S
  PLAY_DRENANDO     // llegó el fin de stream, terminando lo que queda
};
EstadoPlay estadoPlay = PLAY_IDLE;

uint8_t  ring[RING_BYTES];
size_t   ringHead = 0;      // donde escribe el Bluetooth
size_t   ringTail = 0;      // donde lee el I2S
int16_t  feedBuf[FEED_MUESTRAS];

bool     enUnderrun    = false;
uint32_t underrunDesde = 0;

// Máquina de estados del parser de entrada (ver servicioBluetooth).
enum RxEstado { RX_CMD, RX_LEN_HI, RX_LEN_LO, RX_PAYLOAD };
RxEstado rxEstado    = RX_CMD;
uint16_t rxLen       = 0;
uint16_t rxRecibidos = 0;

// ─── TELEMETRÍA DE SESIÓN ────────────────────────────────────────────────────
// No se resetean cada segundo: acumulan toda la sesión y se mandan por SPP con
// el comando 'T'. Permiten diagnosticar sin Monitor Serie, que es lo que hace
// falta cuando la PC que prueba no es la que flashea — y más adelante, cuando
// el que está del otro lado es el celular.
uint32_t sesLeidos      = 0;   // bloques que salieron del micrófono
uint32_t sesEnviados    = 0;   // bloques que el Bluetooth aceptó
uint32_t sesDescartados = 0;   // bloques que el Bluetooth rechazó (cola llena)

uint32_t sesRxBytes     = 0;   // bytes de audio recibidos para reproducir
uint32_t sesReproducidas = 0;  // muestras efectivamente mandadas al parlante
uint32_t sesUnderruns   = 0;   // veces que el buffer se quedó vacío sonando
uint32_t sesMsUnderrun  = 0;   // milisegundos totales de hambre de datos
uint32_t sesRingMax     = 0;   // ocupación máxima del anillo (marca de agua)

uint32_t ultimoReporte  = 0;

// ─── Estado de los perfiles de audio Bluetooth (A2DP y HFP) ──────────────────
// Detalle y flujo completo en la sección PERFILES DE AUDIO BLUETOOTH, más abajo.
volatile bool btSlcConectado  = false;  // HFP: canal de control abierto con el teléfono
volatile bool btScoActivo     = false;  // HFP: audio de llamada o de voz abierto
volatile bool btScoMsbc       = false;  // HFP: mSBC (16 kHz) en vez de CVSD (8 kHz)
volatile bool btA2dpConectado = false;  // A2DP: el teléfono está enlazado como fuente
volatile bool btA2dpActivo    = false;  // A2DP: el teléfono manda música o sonidos
volatile bool btLlamada       = false;  // HFP: hay una llamada en curso
volatile bool btVoz           = false;  // HFP: el asistente de voz del teléfono está activo
volatile uint32_t ampRateA2dp = SAMPLE_RATE;  // tasa de la música que llega por A2DP

// Contadores de diagnóstico del audio Bluetooth. Se imprimen cada 2 s mientras
// hay música o llamada: sirven para ver dónde se corta el audio.
volatile uint32_t diagA2dpEntrada = 0;  // bytes que llegaron por A2DP
volatile uint32_t diagA2dpPerdida = 0;  // bytes que no entraron en el buffer de salida
volatile uint32_t diagAmpSalida   = 0;  // bytes escritos al I2S del parlante
volatile uint32_t diagAmpError    = 0;  // errores de i2s_write
volatile uint16_t diagPicoA2dp    = 0;  // mayor amplitud recibida por A2DP desde el último informe
volatile uint32_t diagMicLeido    = 0;  // bytes de audio que salieron del micrófono (HFP)
volatile uint16_t diagMicPico     = 0;  // mayor amplitud del micrófono desde el último informe
volatile uint32_t diagMicEntregado = 0; // bytes que el teléfono pidió y se le entregaron
volatile uint32_t diagMicPedidos  = 0;  // veces que el Bluetooth pidió audio del micrófono
volatile uint32_t diagMicVacios   = 0;  // pedidos que no se pudieron atender (todavía no había audio)

// Mientras hay audio de un perfil Bluetooth, el parlante y el micrófono son de
// ese perfil: el protocolo SPP de BlindRoute no los toca.
static inline bool audioBtActivo() { return btScoActivo || btA2dpActivo; }

// ═══════════════════════════════════════════════════════════════════════════
//  μ-LAW
// ═══════════════════════════════════════════════════════════════════════════

#if USAR_ULAW
// Tabla de exponentes del estándar G.711. Evita un bucle de búsqueda por
// muestra en el codificador.
static const uint8_t ULAW_EXP[256] = {
  0,0,1,1,2,2,2,2,3,3,3,3,3,3,3,3,
  4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
  5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
  5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
  6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
  6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
  6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
  6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
};

static inline uint8_t linearAUlaw(int16_t pcm) {
  const int32_t BIAS = 0x84;
  const int32_t CLIP = 32635;

  // Se amplía a int32 ANTES de negar. Con int16_t, -(-32768) desborda y se
  // queda en -32768: el recorte a CLIP no actúa, el resto del cálculo trabaja
  // sobre un negativo y el pico a fondo de escala termina codificado como
  // SILENCIO (0x7F). Suena como un chasquido en los picos negativos fuertes.
  // Es el único valor de los 65536 que fallaba, pero es justo el que produce
  // convertirA16Bit al recortar, así que es alcanzable.
  int32_t s = pcm;
  int32_t sign = (s < 0) ? 0x80 : 0;
  if (sign) s = -s;
  if (s > CLIP) s = CLIP;
  s += BIAS;

  uint8_t exponent = ULAW_EXP[(s >> 7) & 0xFF];
  uint8_t mantissa = (s >> (exponent + 3)) & 0x0F;
  return ~(sign | (exponent << 4) | mantissa);
}
#endif

// Decodificador μ-law → lineal de 16 bits. Se usa para el audio que llega de
// la app antes de mandarlo al I2S (el MAX98357A solo entiende PCM).
static inline int16_t ulawALinear(uint8_t b) {
  uint8_t u = ~b;
  int32_t t = (((u & 0x0F) << 3) + 0x84) << ((u & 0x70) >> 4);
  t -= 0x84;
  return (u & 0x80) ? (int16_t)(-t) : (int16_t)t;
}

// ═══════════════════════════════════════════════════════════════════════════
//  BUFFER ANILLO
// ═══════════════════════════════════════════════════════════════════════════
// Se desperdicia una posición a propósito: es lo que permite distinguir
// "lleno" de "vacío" sin un contador aparte (head == tail solo si está vacío).

static inline size_t ringDisponible() {
  return (ringHead + RING_BYTES - ringTail) % RING_BYTES;
}

static inline size_t ringLibre() {
  return RING_BYTES - 1 - ringDisponible();
}

static inline void ringPush(uint8_t b) {
  size_t siguiente = (ringHead + 1) % RING_BYTES;
  if (siguiente == ringTail) return;   // lleno: descartar (no debería pasar,
                                       // servicioBluetooth frena antes)
  ring[ringHead] = b;
  ringHead = siguiente;
}

static inline void ringVaciar() {
  ringHead = 0;
  ringTail = 0;
}

// ═══════════════════════════════════════════════════════════════════════════
//  I2S
// ═══════════════════════════════════════════════════════════════════════════

void initMicrophoneI2S() {
  i2s_config_t cfg = {
    .mode                 = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate          = SAMPLE_RATE,

    // El INMP441 es un micrófono de 24 bits que transmite cada muestra dentro
    // de una trama I2S de 32 bits. El periférico I2S del ESP32 no recorta solo:
    // si le pedís 16 bits, lee 16 bits de una trama de 32 y lo que obtenés no
    // es la muestra sino bits de posición equivocada. El síntoma es ruido
    // constante. Se lee SIEMPRE a 32 bits y se convierte por software.
    .bits_per_sample      = I2S_BITS_PER_SAMPLE_32BIT,

    // ONLY_LEFT asume el pin L/R del INMP441 a GND (confirmado en tu
    // esquemático). Con L/R a VDD hay que usar ONLY_RIGHT o se lee silencio.
    .channel_format       = I2S_CHANNEL_FMT_ONLY_LEFT,

    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count        = 8,
    .dma_buf_len          = MUESTRAS_POR_BLOQUE,
    .use_apll             = false,
    .tx_desc_auto_clear   = false,
    .fixed_mclk           = 0
  };
  i2s_pin_config_t pins = {
    .mck_io_num   = I2S_PIN_NO_CHANGE,
    .bck_io_num   = MIC_SCK_IO,
    .ws_io_num    = MIC_WS_IO,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num  = MIC_SD_IO
  };
  i2s_driver_install(MIC_I2S_PORT, &cfg, 0, NULL);
  i2s_set_pin(MIC_I2S_PORT, &pins);
  i2s_zero_dma_buffer(MIC_I2S_PORT);
}

void initAmplifierI2S() {
  i2s_config_t cfg = {
    .mode                 = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
    .sample_rate          = SAMPLE_RATE,
    .bits_per_sample      = I2S_BITS_PER_SAMPLE_16BIT,

    // ALL_LEFT repite la misma muestra en las dos ranuras (izquierda y derecha).
    // Con ONLY_LEFT la ranura derecha queda vacía, y el MAX98357A en modo mezcla
    // (pin SD sin forzar) promedia las dos: sale la mitad del volumen, 6 dB menos.
    .channel_format       = I2S_CHANNEL_FMT_ALL_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count        = 8,
    .dma_buf_len          = MUESTRAS_POR_BLOQUE,
    .use_apll             = false,
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
}

// ═══════════════════════════════════════════════════════════════════════════
//  CAPTURA DEL MICRÓFONO
// ═══════════════════════════════════════════════════════════════════════════

float dcX1 = 0, dcY1 = 0;

size_t convertirA16Bit(size_t bytesCrudos) {
  size_t muestras = bytesCrudos / 4;
  if (muestras > MUESTRAS_POR_BLOQUE) muestras = MUESTRAS_POR_BLOQUE;

  for (size_t i = 0; i < muestras; i++) {
    int32_t muestra = rawBuf[i] >> MIC_SHIFT;

    // Filtro pasa-altos de un polo (DC blocker). El INMP441 tiene un offset de
    // continua y capta retumbe de baja frecuencia (pasos, roce del cable).
    // Nada de eso es voz, pero ocupa amplitud y te acerca al clipping sin
    // aportar información. R = 0.995 → corte en ~6 Hz, muy por debajo de la voz.
    float x = (float)muestra;
    float y = x - dcX1 + 0.995f * dcY1;
    dcX1 = x;
    dcY1 = y;
    muestra = (int32_t)y;

    if (muestra >  32767) muestra =  32767;
    if (muestra < -32768) muestra = -32768;

    int16_t s = (int16_t)muestra;

#if USAR_ULAW
    outBuf[i] = linearAUlaw(s);
#else
    outBuf[i * 2]     = (uint8_t)(s & 0xFF);
    outBuf[i * 2 + 1] = (uint8_t)((s >> 8) & 0xFF);
#endif
  }

#if USAR_ULAW
  return muestras;
#else
  return muestras * 2;
#endif
}

void capturarYEnviarAudio() {
  size_t bytesLeidos = 0;

  // Timeout de 100 ms en vez de portMAX_DELAY: si el micrófono se desconecta o
  // el I2S se cuelga, el loop sigue girando y el comando 'S' se atiende igual.
  esp_err_t err = i2s_read(MIC_I2S_PORT, (void*)rawBuf, RAW_BUF_BYTES,
                           &bytesLeidos, pdMS_TO_TICKS(100));
  if (err != ESP_OK || bytesLeidos == 0) return;

  // Los primeros bloques traen el transitorio de arranque del micrófono.
  if (bloquesDescartados < BLOQUES_A_DESCARTAR) {
    bloquesDescartados++;
    return;
  }

  sesLeidos++;

  size_t bytesSalida = convertirA16Bit(bytesLeidos);
  if (bytesSalida == 0) return;

  if (!SerialBT.hasClient()) {
    Serial.println("Cliente SPP desconectado; volviendo a MODO_ESPERA.");
    modoActual = MODO_ESPERA;
    return;
  }

  txBuf[0] = AUDIO_MARKER;
  txBuf[1] = (bytesSalida >> 8) & 0xFF;
  txBuf[2] = bytesSalida & 0xFF;

  const size_t aEnviar  = 3 + bytesSalida;
  const size_t escritos = SerialBT.write(txBuf, aEnviar);

  // Cuando la cola de transmisión del Bluetooth se llena, write() descarta lo
  // que no entra y devuelve menos de lo pedido. Sin este control el firmware
  // perdería paquetes enteros en silencio.
  if (escritos < aEnviar) {
    bloquesDescartadosTx++;
    sesDescartados++;
    return;
  }

  bloquesEnviados++;
  sesEnviados++;
}

void iniciarCaptura() {
  if (audioBtActivo()) {
    Serial.println("Captura SPP ignorada: el micrófono está en uso por Bluetooth (llamada o música).");
    return;
  }
  i2s_zero_dma_buffer(MIC_I2S_PORT);
  dcX1 = 0; dcY1 = 0;
  bloquesDescartados = 0;
  bloquesEnviados = 0;
  bloquesDescartadosTx = 0;
  sesLeidos = 0;
  sesEnviados = 0;
  sesDescartados = 0;
  ultimoReporte = millis();
  modoActual = MODO_AUDIO;
}

void detenerCaptura() {
  modoActual = MODO_ESPERA;
  i2s_zero_dma_buffer(MIC_I2S_PORT);
}

// ═══════════════════════════════════════════════════════════════════════════
//  REPRODUCCIÓN EN STREAMING
// ═══════════════════════════════════════════════════════════════════════════

void iniciarReproduccion() {
  // Si el parlante lo usa un perfil Bluetooth, el audio SPP se descarta (ver
  // servicioBluetooth): no hay que cortar nada del perfil.
  if (audioBtActivo()) return;

  // Cortar la captura: half-duplex (ver cabecera del archivo).
  if (modoActual == MODO_AUDIO) detenerCaptura();

  ringVaciar();
  // reproducirAudioLocal() cambia el reloj del I2S al sample rate del WAV.
  // Hay que devolverlo al nuestro o el audio de la app sale acelerado o lento.
  i2s_set_clk(AMP_I2S_PORT, SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT,
              I2S_CHANNEL_MONO);
  i2s_zero_dma_buffer(AMP_I2S_PORT);

  enUnderrun      = false;
  sesRxBytes      = 0;
  sesReproducidas = 0;
  sesUnderruns    = 0;
  sesMsUnderrun   = 0;
  sesRingMax      = 0;
  estadoPlay      = PLAY_BUFFERING;
}

void terminarReproduccion(const char* motivo) {
  i2s_zero_dma_buffer(AMP_I2S_PORT);
  ringVaciar();
  estadoPlay = PLAY_IDLE;
  rxEstado   = RX_CMD;
  Serial.printf("Reproduccion terminada (%s): %lu muestras, %lu underruns\n",
                motivo, sesReproducidas, sesUnderruns);
}

// Manda al parlante lo que haya en el anillo. Se llama una vez por vuelta de
// loop y NO BLOQUEA: ese es el punto entero de esta función.
//
// Si usáramos i2s_write con portMAX_DELAY, el loop quedaría frenado hasta que
// el DMA tenga lugar — es decir, hasta que el audio termine de sonar. Durante
// todo ese tiempo no leeríamos el Bluetooth, el buffer de recepción se
// desbordaría, y el audio llegaría cortado. Con timeout 0 escribimos lo que
// entra ahora, avanzamos solo esa cantidad, y volvemos enseguida a atender la
// radio.
void alimentarAltavoz() {
  if (estadoPlay == PLAY_IDLE) return;
  if (audioBtActivo()) return;  // el parlante es del perfil Bluetooth en uso

  size_t disp = ringDisponible();
  if (disp > sesRingMax) sesRingMax = disp;

  // Esperando llenar el colchón inicial.
  if (estadoPlay == PLAY_BUFFERING) {
    if (disp < PREBUFFER_BYTES) return;
    estadoPlay = PLAY_SONANDO;
    Serial.printf("Prebuffer listo (%u bytes), arranca el audio\n",
                  (unsigned)disp);
  }

  if (disp == 0) {
    if (estadoPlay == PLAY_DRENANDO) {
      terminarReproduccion("fin de stream");
      return;
    }
    // Buffer vacío con el stream todavía abierto: el enlace no llegó a tiempo.
    // Se cuenta como UN evento, no una vez por vuelta de loop, y se mide
    // cuánto duró. Así el número significa algo.
    if (!enUnderrun) {
      enUnderrun    = true;
      underrunDesde = millis();
      sesUnderruns++;
    }
    return;
  }

  if (enUnderrun) {
    enUnderrun = false;
    sesMsUnderrun += millis() - underrunDesde;
  }

  size_t n = (disp < FEED_MUESTRAS) ? disp : FEED_MUESTRAS;
  for (size_t i = 0; i < n; i++) {
    int32_t v = ulawALinear(ring[(ringTail + i) % RING_BYTES]);
#if PLAY_VOLUMEN != 100
    v = (v * PLAY_VOLUMEN) / 100;
    if (v >  32767) v =  32767;
    if (v < -32768) v = -32768;
#endif
    feedBuf[i] = (int16_t)v;
  }

  size_t escritos = 0;
  esp_err_t err = i2s_write(AMP_I2S_PORT, feedBuf, n * 2, &escritos, 0);

  // Avanzar SOLO lo que el DMA aceptó. Si aceptó menos de lo que preparamos,
  // el resto sigue en el anillo y se manda en la próxima vuelta.
  if (err == ESP_OK && escritos > 0) {
    ringTail = (ringTail + escritos / 2) % RING_BYTES;
    sesReproducidas += escritos / 2;
  }
}

// ─── REPRODUCIR WAV LOCAL (LittleFS) ─────────────────────────────────────────
// Se mantiene por compatibilidad con los comandos 'D' e 'I' que la app ya usa.
// Esta sí bloquea el loop, pero son archivos cortos y no hay nada más que
// atender mientras suenan.
void reproducirAudioLocal(const char* path) {
  File file = LittleFS.open(path, "r");
  if (!file) {
    Serial.printf("Error: no se encontro %s\n", path);
    return;
  }
  uint8_t header[44];
  if (file.read(header, 44) < 44) { file.close(); return; }

  uint32_t sampleRate = header[24] | (header[25] << 8) |
                        (header[26] << 16) | (header[27] << 24);
  i2s_set_clk(AMP_I2S_PORT, sampleRate, I2S_BITS_PER_SAMPLE_16BIT,
              I2S_CHANNEL_MONO);

  size_t bytes_written = 0;
  uint8_t buffer[512];
  while (file.available()) {
    int bytes_read = file.read(buffer, sizeof(buffer));
    i2s_write(AMP_I2S_PORT, buffer, bytes_read, &bytes_written, portMAX_DELAY);
  }
  file.close();

  uint8_t silencio[512] = {0};
  i2s_write(AMP_I2S_PORT, silencio, sizeof(silencio), &bytes_written,
            portMAX_DELAY);
  i2s_zero_dma_buffer(AMP_I2S_PORT);

  // Dejar el reloj como lo espera el streaming.
  i2s_set_clk(AMP_I2S_PORT, SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT,
              I2S_CHANNEL_MONO);
}

// ═══════════════════════════════════════════════════════════════════════════
//  COMANDOS
// ═══════════════════════════════════════════════════════════════════════════

void procesarComando(char comando) {
  switch (comando) {

    case 'D': case 'd':
      if (estadoPlay != PLAY_IDLE) terminarReproduccion("comando D");
      if (modoActual == MODO_AUDIO) detenerCaptura();
      Serial.println("Comando D: reproduciendo derecha.wav");
      reproducirAudioLocal("/derecha.wav");
      break;

    case 'I': case 'i':
      if (estadoPlay != PLAY_IDLE) terminarReproduccion("comando I");
      if (modoActual == MODO_AUDIO) detenerCaptura();
      Serial.println("Comando I: reproduciendo izquierda.wav");
      reproducirAudioLocal("/izquierda.wav");
      break;

    case 'M': case 'm':
      // Half-duplex: si estaba sonando algo, se corta.
      if (estadoPlay != PLAY_IDLE) terminarReproduccion("comando M");
      Serial.println("Comando M: iniciando captura de microfono");
      iniciarCaptura();
      break;

    case 'S': case 's':
      Serial.printf("Comando S: deteniendo captura (%lu bloques enviados)\n",
                    bloquesEnviados);
      detenerCaptura();
      break;

    case 'P': case 'p':
      if (estadoPlay != PLAY_IDLE) terminarReproduccion("comando P");
      else Serial.println("Comando P: no habia nada sonando");
      break;

    case 'T': case 't': {
      // Telemetría en texto ASCII. El marcador de audio es 0xAA y el de
      // reproducción 0xBB, ambos fuera del rango ASCII (0x00–0x7F), así que
      // esta línea nunca puede confundirse con audio ni al revés.
      char linea[192];
      int n = snprintf(linea, sizeof(linea),
        "#STATS leidos=%lu enviados=%lu descartados=%lu "
        "rx=%lu repro=%lu underruns=%lu msunder=%lu ringmax=%lu\n",
        sesLeidos, sesEnviados, sesDescartados,
        sesRxBytes, sesReproducidas, sesUnderruns, sesMsUnderrun, sesRingMax);
      if (SerialBT.hasClient()) SerialBT.write((const uint8_t*)linea, n);
      Serial.printf("Comando T: %s", linea);
      break;
    }

    case 'V': case 'v': {
      char linea[48];
      int n = snprintf(linea, sizeof(linea), "#VERSION %s\n", FW_VERSION);
      if (SerialBT.hasClient()) SerialBT.write((const uint8_t*)linea, n);
      Serial.printf("Comando V: %s", linea);
      break;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SERVICIO DEL BLUETOOTH (entrada)
// ═══════════════════════════════════════════════════════════════════════════
// Lee lo que llegó y lo enruta: comandos de un byte, o bloques de audio que
// van al anillo. Tiene un presupuesto de bytes por vuelta para que el loop
// siempre vuelva a alimentar el parlante.

void servicioBluetooth() {
  int presupuesto = 1024;
  uint8_t tmp[256];

  while (presupuesto > 0 && SerialBT.available()) {

    if (rxEstado == RX_PAYLOAD) {
      // Si el anillo está casi lleno, DEJAMOS DE LEER. No descartamos: el
      // buffer de RFCOMM se llena, el control de flujo frena al emisor, y
      // nadie pierde audio. Volvemos en la próxima vuelta, cuando el parlante
      // haya consumido algo.
      // Con un perfil Bluetooth de audio en uso, el audio SPP se descarta para que
      // el enlace no se trabe esperando un parlante que no es suyo.
      if (audioBtActivo()) {
        size_t falta = rxLen - rxRecibidos;
        size_t n = SerialBT.available();
        if (n > falta) n = falta;
        if (n > sizeof(tmp)) n = sizeof(tmp);
        if (n == 0) break;
        rxRecibidos += SerialBT.readBytes(tmp, n);
        if (rxRecibidos >= rxLen) rxEstado = RX_CMD;
        continue;
      }

      size_t libre = ringLibre();
      if (libre < 64) break;

      size_t falta = rxLen - rxRecibidos;
      size_t hay   = SerialBT.available();
      size_t n     = falta;
      if (n > hay)             n = hay;
      if (n > libre)           n = libre;
      if (n > sizeof(tmp))     n = sizeof(tmp);
      if (n > (size_t)presupuesto) n = presupuesto;
      if (n == 0) break;

      size_t leidos = SerialBT.readBytes(tmp, n);
      for (size_t i = 0; i < leidos; i++) ringPush(tmp[i]);

      rxRecibidos += leidos;
      sesRxBytes  += leidos;
      presupuesto -= leidos;

      if (rxRecibidos >= rxLen) rxEstado = RX_CMD;
      continue;
    }

    int b = SerialBT.read();
    if (b < 0) break;
    presupuesto--;

    switch (rxEstado) {

      case RX_CMD:
        if (b == PLAY_MARKER) {
          if (estadoPlay == PLAY_IDLE) iniciarReproduccion();
          rxEstado = RX_LEN_HI;
        } else if (b == PLAY_EOS) {
          if (estadoPlay == PLAY_BUFFERING || estadoPlay == PLAY_SONANDO) {
            // Si el stream era más corto que el prebuffer, hay que arrancar
            // igual o nunca sonaría nada.
            estadoPlay = PLAY_DRENANDO;
            Serial.println("Fin de stream recibido, drenando buffer");
          }
        } else {
          procesarComando((char)b);
        }
        break;

      case RX_LEN_HI:
        rxLen    = (uint16_t)b << 8;
        rxEstado = RX_LEN_LO;
        break;

      case RX_LEN_LO:
        rxLen      |= (uint16_t)b;
        rxRecibidos = 0;
        rxEstado    = (rxLen > 0) ? RX_PAYLOAD : RX_CMD;
        break;

      default:
        rxEstado = RX_CMD;
        break;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SETUP / LOOP
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
//  PERFILES DE AUDIO BLUETOOTH: A2DP (música) y HFP (llamadas y voz)
// ═══════════════════════════════════════════════════════════════════════════
//
//  El teléfono ve el auricular como "ESP32_BlindRoute", con clase de dispositivo
//  de auricular inalámbrico. Ofrece tres cosas, y cada una la usa un tipo de app:
//
//   - A2DP (receptor de audio): la música y los sonidos de cualquier app llegan
//     por acá y salen por el parlante (MAX98357A). El teléfono elige la tasa
//     (16, 32, 44,1 o 48 kHz); el amplificador se reconfigura a esa tasa.
//
//   - HFP (manos libres): llamadas y asistente de voz. El teléfono abre el canal
//     de audio (SCO) y negocia el códec: CVSD (8 kHz) o mSBC (16 kHz). La
//     librería del núcleo codifica y decodifica; acá sólo llegan y salen muestras
//     PCM de 16 bits. El parlante reproduce la voz del otro lado; el micrófono
//     (INMP441) manda la voz de este lado al teléfono.
//
//   - SPP: el protocolo propio de BlindRoute (comandos y audio por el canal serie
//     Bluetooth), sin cambios. Mientras A2DP o HFP usan el micrófono o el parlante,
//     el SPP no reproduce ni captura (ver audioBtActivo).
//
//  Flujo de datos:
//    música (A2DP)  → pcmSalida → tareaSalidaAmp → I2S amplificador
//    voz (HFP RX)   → pcmSalida → tareaSalidaAmp → I2S amplificador
//    micrófono I2S  → tareaMicroSco → pcmMicro → HFP TX (el teléfono lo pide)

#define PCM_SALIDA_BYTES   16384   // ~186 ms de música estéreo a 44,1 kHz, en mono
#define PCM_SALIDA_DISPARO 512     // lo que tiene que juntarse antes de que la tarea lo lea
#define PCM_MICRO_BYTES    1024
#define PCM_MICRO_DISPARO  128

static StreamBufferHandle_t pcmSalida = nullptr;  // PCM mono 16 bits hacia el parlante
static StreamBufferHandle_t pcmMicro  = nullptr;  // PCM mono 16 bits del micrófono (HFP)
static TaskHandle_t tareaSalida = nullptr;
static TaskHandle_t tareaMicro  = nullptr;
static volatile bool microCorriendo = false;

// Dirección del último teléfono enlazado. Se usa para reconectar sola.
static esp_bd_addr_t bdaRecordado;
static bool bdaValido = false;
static bool hfpListo = false;
static uint32_t ultimoIntentoHfp  = 0;
static uint32_t ultimoIntentoSco  = 0;
static uint32_t ultimoIntentoA2dp = 0;

static const uint32_t SCO_TASA_CVSD = 8000;
static const uint32_t SCO_TASA_MSBC = 16000;

static void recordarBda(const esp_bd_addr_t bda) {
  memcpy(bdaRecordado, bda, sizeof(esp_bd_addr_t));
  bdaValido = true;
}

static void imprimirBda(const esp_bd_addr_t bda) {
  for (int i = 0; i < 6; i++) {
    Serial.printf("%02X%s", bda[i], i < 5 ? ":" : "");
  }
}

// Tasa que necesita el parlante en este momento: la de la llamada si la hay,
// si no la de la música (A2DP), y si no, la del SPP.
static uint32_t tasaAmpBt() {
  if (btScoActivo) return btScoMsbc ? SCO_TASA_MSBC : SCO_TASA_CVSD;
  if (btA2dpActivo) return ampRateA2dp;
  return SAMPLE_RATE;
}

// Emparejamiento. El auricular no tiene pantalla ni teclado, así que acepta sin
// pedir confirmación (SSP) y responde "0000" a los teléfonos viejos (PIN).
static void gapEventoBt(esp_bt_gap_cb_event_t event, esp_bt_gap_cb_param_t *param) {
  switch (event) {
    case ESP_BT_GAP_AUTH_CMPL_EVT:
      if (param->auth_cmpl.stat == ESP_BT_STATUS_SUCCESS) {
        recordarBda(param->auth_cmpl.bda);
        Serial.print("Emparejado con ");
        imprimirBda(param->auth_cmpl.bda);
        Serial.println();
      } else {
        Serial.printf("Emparejamiento fallido (estado %d)\n", param->auth_cmpl.stat);
      }
      break;

    case ESP_BT_GAP_PIN_REQ_EVT: {
      esp_bt_pin_code_t pin = {'0', '0', '0', '0'};
      esp_bt_gap_pin_reply(param->pin_req.bda, true, 4, pin);
      break;
    }

    case ESP_BT_GAP_CFM_REQ_EVT:
      esp_bt_gap_ssp_confirm_reply(param->cfm_req.bda, true);
      break;

    default:
      break;
  }
}

// ─── A2DP: música ────────────────────────────────────────────────────────────

static void a2dpEventoBt(esp_a2d_cb_event_t event, esp_a2d_cb_param_t *param) {
  switch (event) {
    case ESP_A2D_CONNECTION_STATE_EVT:
      btA2dpConectado = (param->conn_stat.state == ESP_A2D_CONNECTION_STATE_CONNECTED);
      if (btA2dpConectado) {
        recordarBda(param->conn_stat.remote_bda);
        Serial.print("A2DP conectado con ");
        imprimirBda(param->conn_stat.remote_bda);
        Serial.println();
      } else {
        btA2dpActivo = false;
        Serial.println("A2DP desconectado");
      }
      break;

    case ESP_A2D_AUDIO_STATE_EVT:
      btA2dpActivo = (param->audio_stat.state == ESP_A2D_AUDIO_STATE_STARTED);
      Serial.printf("A2DP audio: %s\n", btA2dpActivo ? "sonando" : "parado");
      if (!btA2dpActivo && !btScoActivo && pcmSalida) {
        xStreamBufferReset(pcmSalida);  // no quedan restos de la música anterior
      }
      break;

    case ESP_A2D_AUDIO_CFG_EVT:
      if (param->audio_cfg.mcc.type == ESP_A2D_MCT_SBC) {
        const uint8_t f = param->audio_cfg.mcc.cie.sbc_info.samp_freq;
        uint32_t tasa = 48000;
        if (f & ESP_A2D_SBC_CIE_SF_16K)      tasa = 16000;
        else if (f & ESP_A2D_SBC_CIE_SF_32K) tasa = 32000;
        else if (f & ESP_A2D_SBC_CIE_SF_44K) tasa = 44100;
        ampRateA2dp = tasa;
        Serial.printf("A2DP codec SBC a %lu Hz\n", (unsigned long)tasa);
        const esp_a2d_cie_sbc_t &sbc = param->audio_cfg.mcc.cie.sbc_info;
        Serial.printf("A2DP SBC: canales=0x%X bloques=0x%X subbandas=0x%X asignacion=0x%X bitpool=%u..%u\n",
                      sbc.ch_mode, sbc.block_len, sbc.num_subbands, sbc.alloc_mthd,
                      (unsigned)sbc.min_bitpool, (unsigned)sbc.max_bitpool);
      }
      break;

    default:
      break;
  }
}

// La librería entrega la música ya decodificada: PCM estéreo de 16 bits
// intercalado (izquierda, derecha). El parlante es mono, así que se promedian.
static void a2dpDatosPcm(const uint8_t *datos, uint32_t len) {
  if (!datos || len < 4 || btScoActivo || !pcmSalida) return;
  diagA2dpEntrada += len;

  static int16_t mono[256];
  const uint8_t *p = datos;
  size_t frames = len / 4;
  while (frames > 0) {
    const size_t n = frames > 256 ? 256 : frames;
    for (size_t i = 0; i < n; i++) {
      const int16_t izq = (int16_t)(p[0] | (p[1] << 8));
      const int16_t der = (int16_t)(p[2] | (p[3] << 8));
      mono[i] = (int16_t)(((int32_t)izq + der) / 2);
      const uint16_t a = (uint16_t)(mono[i] < 0 ? -(int32_t)mono[i] : mono[i]);
      if (a > diagPicoA2dp) diagPicoA2dp = a;
      p += 4;
    }
    // Si no entra, se pierde el trozo: en música es mejor un corte que un atraso.
    const size_t pedidos = n * sizeof(int16_t);
    const size_t enviados = xStreamBufferSend(pcmSalida, mono, pedidos, 0);
    if (enviados < pedidos) diagA2dpPerdida += pedidos - enviados;
    frames -= n;
  }
}

// ─── HFP: llamadas y voz ─────────────────────────────────────────────────────

// Audio que llega del teléfono (voz del otro lado) → parlante.
static void hfDatosEntrada(const uint8_t *buf, uint32_t len) {
  if (!buf || len == 0 || !pcmSalida || !btScoActivo) return;
  xStreamBufferSend(pcmSalida, buf, len, 0);
}

// El teléfono pide el siguiente trozo de micrófono para mandarlo. Si todavía no
// hay un trozo completo, devuelve 0 y lo vuelve a pedir enseguida.
static uint32_t hfDatosSalida(uint8_t *buf, uint32_t len) {
  diagMicPedidos++;
  if (!buf || len == 0 || !pcmMicro) return 0;
  if (xStreamBufferBytesAvailable(pcmMicro) < len) {
    diagMicVacios++;
    return 0;
  }
  if (xStreamBufferReceive(pcmMicro, buf, len, 0) != len) return 0;
  diagMicEntregado += len;
  return len;
}

static void conectarHfp(const char *motivo) {
  if (!hfpListo || !bdaValido || btSlcConectado) return;
  if (millis() - ultimoIntentoHfp < 5000) return;
  ultimoIntentoHfp = millis();
  Serial.printf("HFP: conectando (%s) con ", motivo);
  imprimirBda(bdaRecordado);
  Serial.println();
  const esp_err_t e = esp_hf_client_connect(bdaRecordado);
  if (e != ESP_OK) Serial.printf("  esp_hf_client_connect error %d\n", (int)e);
}

static void abrirSco(const char *motivo) {
  if (!btSlcConectado || btScoActivo || !bdaValido) return;
  if (millis() - ultimoIntentoSco < 3000) return;
  ultimoIntentoSco = millis();
  Serial.printf("HFP: abriendo audio (%s)\n", motivo);
  const esp_err_t e = esp_hf_client_connect_audio(bdaRecordado);
  if (e != ESP_OK) Serial.printf("  esp_hf_client_connect_audio error %d\n", (int)e);
}

// Tarea del micrófono durante una llamada: lee el I2S, convierte a 16 bits con el
// mismo filtro de DC que el SPP y deja las muestras para el teléfono.
static void tareaMicroSco(void *) {
  static int32_t crudo[64];
  static int16_t pcm[64];
  while (microCorriendo) {
    size_t leidos = 0;
    if (i2s_read(MIC_I2S_PORT, crudo, sizeof(crudo), &leidos, pdMS_TO_TICKS(50)) != ESP_OK || leidos == 0) {
      continue;
    }
    const size_t n = leidos / sizeof(int32_t);
    for (size_t i = 0; i < n; i++) {
      int32_t m = crudo[i] >> MIC_SHIFT;
      const float x = (float)m;
      const float y = x - dcX1 + 0.995f * dcY1;
      dcX1 = x;
      dcY1 = y;
      m = (int32_t)y;
      if (m >  32767) m =  32767;
      if (m < -32768) m = -32768;
      pcm[i] = (int16_t)m;
      const uint16_t a = (uint16_t)(m < 0 ? -m : m);
      if (a > diagMicPico) diagMicPico = a;
    }
    diagMicLeido += n * sizeof(int16_t);
    if (pcmMicro) {
      xStreamBufferSend(pcmMicro, pcm, n * sizeof(int16_t), 0);
      // Sin este aviso el Bluetooth no sabe que hay audio del micrófono listo y no
      // lo pide: el teléfono se queda con silencio (o con su propio micrófono).
      esp_hf_client_outgoing_data_ready();
    }
  }
  tareaMicro = nullptr;
  vTaskDelete(nullptr);
}

// ─── Ecualizador y limitador de la música (A2DP) ─────────────────────────────
// El parlante es chico: no mueve los graves y exagera los medios agudos, que es
// lo que suena metálico, chato y enlatado. Se cortan los graves que el parlante
// no puede reproducir, se suaviza la zona áspera y un limitador deja subir el
// volumen sin que el parlante distorsione. Se elige por el puerto USB (ver
// interpretarComandoUsb): p0..p3 elige el preset, g<dB> la ganancia, q muestra.
// La voz de las llamadas (HFP) no pasa por acá.

// (struct Biquad está definida al principio del archivo: el preprocesador de
// Arduino genera los prototipos de las funciones antes de este punto.)

static void biquadFijar(Biquad &q, float b0, float b1, float b2, float a0, float a1, float a2) {
  q.b0 = b0 / a0; q.b1 = b1 / a0; q.b2 = b2 / a0;
  q.a1 = a1 / a0; q.a2 = a2 / a0;
}

// Fórmulas del "Audio EQ Cookbook" de Robert Bristow-Johnson.
static void biquadPasaAltos(Biquad &q, float fs, float f0, float Q) {
  const float w0 = 2.0f * (float)M_PI * f0 / fs, c = cosf(w0), alfa = sinf(w0) / (2.0f * Q);
  biquadFijar(q, (1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alfa, -2 * c, 1 - alfa);
}

static void biquadPico(Biquad &q, float fs, float f0, float Q, float dB) {
  const float A = powf(10.0f, dB / 40.0f);
  const float w0 = 2.0f * (float)M_PI * f0 / fs, c = cosf(w0), alfa = sinf(w0) / (2.0f * Q);
  biquadFijar(q, 1 + alfa * A, -2 * c, 1 - alfa * A, 1 + alfa / A, -2 * c, 1 - alfa / A);
}

static void biquadEstanteBajo(Biquad &q, float fs, float f0, float dB) {
  const float A = powf(10.0f, dB / 40.0f);
  const float w0 = 2.0f * (float)M_PI * f0 / fs, c = cosf(w0), s = sinf(w0);
  const float beta = 2.0f * sqrtf(A) * (s / 2.0f) * sqrtf(2.0f);
  biquadFijar(q,
              A * ((A + 1) - (A - 1) * c + beta), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - beta),
              (A + 1) + (A - 1) * c + beta, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - beta);
}

static void biquadEstanteAlto(Biquad &q, float fs, float f0, float dB) {
  const float A = powf(10.0f, dB / 40.0f);
  const float w0 = 2.0f * (float)M_PI * f0 / fs, c = cosf(w0), s = sinf(w0);
  const float beta = 2.0f * sqrtf(A) * (s / 2.0f) * sqrtf(2.0f);
  biquadFijar(q,
              A * ((A + 1) + (A - 1) * c + beta), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - beta),
              (A + 1) - (A - 1) * c + beta, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - beta);
}

#define EQ_ETAPAS 4
static Biquad eqEtapa[EQ_ETAPAS];
static volatile uint8_t eqPreset = 1;            // 0 = sin proceso, 1 claro, 2 cálido, 3 voz
static volatile float gananciaDb = 3.0f;         // ganancia antes del limitador
static uint8_t eqPresetAplicado = 255;
static float eqFs = 0;
static float limGanancia = 1.0f;
static float limLiberacion = 0.0003f;
static volatile float diagLimMinimo = 1.0f;       // la reducción más fuerte del limitador en el período
static const float LIM_UMBRAL = 29500.0f;         // ~ -1 dBFS

static void configurarEq(float fs, uint8_t preset) {
  for (int i = 0; i < EQ_ETAPAS; i++) eqEtapa[i] = Biquad();
  switch (preset) {
    case 1:  // claro: corta graves que el parlante no mueve y suaviza lo áspero
      biquadPasaAltos(eqEtapa[0], fs, 140.0f, 0.707f);
      biquadPico(eqEtapa[1], fs, 3500.0f, 1.0f, -3.0f);
      biquadEstanteAlto(eqEtapa[2], fs, 7000.0f, -2.0f);
      break;
    case 2:  // cálido: además da algo de cuerpo (300 Hz)
      biquadPasaAltos(eqEtapa[0], fs, 110.0f, 0.707f);
      biquadEstanteBajo(eqEtapa[1], fs, 300.0f, 3.0f);
      biquadPico(eqEtapa[2], fs, 3500.0f, 1.0f, -3.0f);
      biquadEstanteAlto(eqEtapa[3], fs, 6000.0f, -3.0f);
      break;
    case 3:  // voz: realza la zona de la voz y quita lo que molesta
      biquadPasaAltos(eqEtapa[0], fs, 180.0f, 0.707f);
      biquadPico(eqEtapa[1], fs, 1800.0f, 0.9f, 3.0f);
      biquadPico(eqEtapa[2], fs, 4500.0f, 1.0f, -2.0f);
      break;
    default:
      break;
  }
  limLiberacion = 1.0f - expf(-1.0f / (0.08f * fs));  // el limitador suelta en ~80 ms
}

static inline int16_t procesarMusica(int16_t m, float pre) {
  float x = (float)m;
  for (int i = 0; i < EQ_ETAPAS; i++) x = eqEtapa[i].proceso(x);
  x *= pre;
  const float a = fabsf(x);
  const float necesaria = (a > LIM_UMBRAL) ? (LIM_UMBRAL / a) : 1.0f;
  if (necesaria < limGanancia) limGanancia = necesaria;                      // ataque inmediato
  else limGanancia += (1.0f - limGanancia) * limLiberacion;                  // suelta lenta
  if (limGanancia < diagLimMinimo) diagLimMinimo = limGanancia;
  x *= limGanancia;
  if (x >  32767.0f) x =  32767.0f;
  if (x < -32768.0f) x = -32768.0f;
  return (int16_t)x;
}

// Volumen de la voz de llamada que pide el teléfono (0 a 15). Cuando el usuario
// sube o baja el volumen de la llamada en el celular, el teléfono manda +VGS y el
// auricular tiene que bajar él mismo lo que reproduce.
static volatile uint8_t scoVolumen = 15;

// Prueba del micrófono sin llamada: lee el I2S durante unos segundos e imprime el
// nivel cada 250 ms. Sirve para verificar el cableado del micrófono (SCK, WS, SD).
static void probarMicrofono(int segundos) {
  if (audioBtActivo() || modoActual == MODO_AUDIO) {
    Serial.println("Prueba de micrófono: el micrófono está en uso, probá cuando no haya llamada ni captura.");
    return;
  }
  if (segundos < 1) segundos = 1;
  if (segundos > 20) segundos = 20;
  Serial.printf("Prueba de micrófono: hablá cerca durante %d s\n", segundos);

  static int32_t crudo[256];
  i2s_zero_dma_buffer(MIC_I2S_PORT);
  float x1 = 0, y1 = 0;
  int32_t pico = 0;
  double suma = 0;
  uint32_t cuenta = 0;
  uint32_t ultimo = millis();
  const uint32_t fin = millis() + (uint32_t)segundos * 1000UL;
  while ((int32_t)(fin - millis()) > 0) {
    size_t leidos = 0;
    if (i2s_read(MIC_I2S_PORT, crudo, sizeof(crudo), &leidos, pdMS_TO_TICKS(100)) != ESP_OK || leidos == 0) continue;
    const size_t n = leidos / sizeof(int32_t);
    for (size_t i = 0; i < n; i++) {
      const float x = (float)(crudo[i] >> MIC_SHIFT);
      const float y = x - x1 + 0.995f * y1;
      x1 = x;
      y1 = y;
      int32_t m = (int32_t)y;
      if (m < 0) m = -m;
      if (m > 32767) m = 32767;
      if (m > pico) pico = m;
      suma += (double)m * (double)m;
      cuenta++;
    }
    if (millis() - ultimo >= 250 && cuenta > 0) {
      Serial.printf("[mic] pico=%ld rms=%ld\n", (long)pico, (long)sqrt(suma / cuenta));
      pico = 0;
      suma = 0;
      cuenta = 0;
      ultimo = millis();
    }
  }
  Serial.println("Prueba de micrófono: fin");
}

// Comandos por el puerto USB (115200, terminados en enter): p0..p3, g<dB>, q, m<s>.
static void interpretarComandoUsb(const char *l) {
  switch (l[0]) {
    case 'p': case 'P': {
      const int v = atoi(l + 1);
      if (v >= 0 && v <= 3) {
        eqPreset = (uint8_t)v;
        Serial.printf("Sonido: preset %d\n", v);
      }
      break;
    }
    case 'g': case 'G': {
      const float v = atof(l + 1);
      if (v >= 0.0f && v <= 12.0f) {
        gananciaDb = v;
        Serial.printf("Sonido: ganancia +%.1f dB\n", v);
      }
      break;
    }
    case 'q': case 'Q':
      Serial.printf("Sonido: preset %d, ganancia +%.1f dB, volumen de llamada %d/15\n",
                    (int)eqPreset, (double)gananciaDb, (int)scoVolumen);
      break;
    case 'm': case 'M': {
      const int s = atoi(l + 1);
      probarMicrofono(s > 0 ? s : 5);
      break;
    }
    default:
      break;
  }
}

static void atenderComandosUsb() {
  static char linea[16];
  static uint8_t n = 0;
  while (Serial.available()) {
    const char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (n > 0) {
        linea[n] = 0;
        interpretarComandoUsb(linea);
        n = 0;
      }
    } else if (n < sizeof(linea) - 1) {
      linea[n++] = c;
    }
  }
}

// Tarea del parlante: saca el PCM de pcmSalida y lo manda al amplificador. Se
// queda bloqueada en el I2S (no en el loop), así la radio nunca espera al audio.
static void tareaSalidaAmp(void *) {
  static int16_t buf[PCM_SALIDA_DISPARO];
  uint32_t tasaActual = SAMPLE_RATE;
  for (;;) {
    if (!audioBtActivo()) {
      if (tasaActual != SAMPLE_RATE) {
        i2s_set_clk(AMP_I2S_PORT, SAMPLE_RATE, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_MONO);
        tasaActual = SAMPLE_RATE;
      }
      vTaskDelay(pdMS_TO_TICKS(20));
      continue;
    }

    const uint32_t pedida = tasaAmpBt();
    if (pedida != tasaActual) {
      i2s_set_clk(AMP_I2S_PORT, pedida, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_MONO);
      tasaActual = pedida;
    }

    const size_t n = xStreamBufferReceive(pcmSalida, buf, sizeof(buf), pdMS_TO_TICKS(50));
    if (n == 0) continue;

    // Música: ecualizador y limitador. La voz de llamada pasa sin tocar.
    if (btA2dpActivo && !btScoActivo && eqPreset != 0) {
      const uint8_t preset = eqPreset;
      if (preset != eqPresetAplicado || eqFs != (float)tasaActual) {
        configurarEq((float)tasaActual, preset);
        eqPresetAplicado = preset;
        eqFs = (float)tasaActual;
      }
      const float pre = powf(10.0f, gananciaDb / 20.0f);
      const size_t muestras = n / sizeof(int16_t);
      for (size_t i = 0; i < muestras; i++) buf[i] = procesarMusica(buf[i], pre);
    } else if (btScoActivo) {
      // Voz de llamada: sigue el volumen que pide el teléfono, 3 dB por paso.
      const uint8_t v = scoVolumen;
      if (v < 15) {
        const float g = (v == 0) ? 0.0f : powf(10.0f, (float)(v - 15) * 3.0f / 20.0f);
        const size_t muestras = n / sizeof(int16_t);
        for (size_t i = 0; i < muestras; i++) buf[i] = (int16_t)((float)buf[i] * g);
      }
    }

    size_t escritos = 0;
    const esp_err_t e = i2s_write(AMP_I2S_PORT, buf, n, &escritos, portMAX_DELAY);
    if (e != ESP_OK) diagAmpError++;
    diagAmpSalida += escritos;
  }
}

// Una línea por segundo con los contadores (ver la sección de diagnóstico del loop).
static void imprimirDiagnosticoBt() {
  static uint32_t ultimo = 0;
  if (!audioBtActivo()) return;
  if (millis() - ultimo < 2000) return;
  ultimo = millis();
  const float reduccionDb = 20.0f * log10f(diagLimMinimo > 0.001f ? diagLimMinimo : 0.001f);
  Serial.printf("[bt-audio] A2DP in=%lu perdido=%lu pico=%u | parlante out=%lu err=%lu | buffer=%u bytes | tasa=%lu | preset=%d g=+%.1f limitador=%.1f dB\n",
                (unsigned long)diagA2dpEntrada, (unsigned long)diagA2dpPerdida,
                (unsigned)diagPicoA2dp,
                (unsigned long)diagAmpSalida, (unsigned long)diagAmpError,
                (unsigned)(pcmSalida ? xStreamBufferBytesAvailable(pcmSalida) : 0),
                (unsigned long)tasaAmpBt(),
                (int)eqPreset, (double)gananciaDb, (double)reduccionDb);
  diagPicoA2dp = 0;
  diagLimMinimo = 1.0f;

  if (btScoActivo) {
    Serial.printf("[sco-mic] leido=%lu pico=%u | pedido por el Bluetooth=%lu veces, entregado=%lu bytes, sin audio=%lu veces\n",
                  (unsigned long)diagMicLeido, (unsigned)diagMicPico,
                  (unsigned long)diagMicPedidos, (unsigned long)diagMicEntregado,
                  (unsigned long)diagMicVacios);
    diagMicPico = 0;
  }
}

static void iniciarAudioSco(bool msbc) {
  // La llamada toma el micrófono y el parlante: cualquier captura o reproducción
  // SPP en curso se corta antes.
  if (modoActual == MODO_AUDIO) detenerCaptura();
  if (estadoPlay != PLAY_IDLE) terminarReproduccion("llamada");

  btScoMsbc = msbc;
  if (pcmSalida) xStreamBufferReset(pcmSalida);
  if (pcmMicro)  xStreamBufferReset(pcmMicro);
  dcX1 = 0;
  dcY1 = 0;

  const uint32_t tasa = msbc ? SCO_TASA_MSBC : SCO_TASA_CVSD;
  i2s_set_clk(MIC_I2S_PORT, tasa, I2S_BITS_PER_SAMPLE_32BIT, I2S_CHANNEL_MONO);

  microCorriendo = true;
  if (!tareaMicro) {
    xTaskCreate(tareaMicroSco, "sco_mic", 4096, nullptr, 5, &tareaMicro);
  }
  Serial.printf("Llamada: audio %s\n", msbc ? "mSBC 16 kHz" : "CVSD 8 kHz");
}

static void detenerAudioSco() {
  microCorriendo = false;  // la tarea sale sola en su próxima vuelta
  if (pcmMicro) xStreamBufferReset(pcmMicro);
  if (pcmSalida && !btA2dpActivo) xStreamBufferReset(pcmSalida);
  i2s_set_clk(MIC_I2S_PORT, SAMPLE_RATE, I2S_BITS_PER_SAMPLE_32BIT, I2S_CHANNEL_MONO);
  Serial.println("Llamada: audio cerrado");
}

static void hfEventoBt(esp_hf_client_cb_event_t event, esp_hf_client_cb_param_t *param) {
  switch (event) {

    case ESP_HF_CLIENT_PROF_STATE_EVT:
      hfpListo = (param->prof_stat.state == ESP_HF_INIT_SUCCESS ||
                  param->prof_stat.state == ESP_HF_INIT_ALREADY);
      Serial.printf("HFP listo: %s\n", hfpListo ? "si" : "no");
      if (hfpListo) conectarHfp("arranque");
      break;

    case ESP_HF_CLIENT_CONNECTION_STATE_EVT:
      recordarBda(param->conn_stat.remote_bda);
      btSlcConectado = (param->conn_stat.state == ESP_HF_CLIENT_CONNECTION_STATE_SLC_CONNECTED);
      if (param->conn_stat.state == ESP_HF_CLIENT_CONNECTION_STATE_DISCONNECTED) {
        btLlamada = false;
        btVoz = false;
        if (btScoActivo) {
          btScoActivo = false;
          detenerAudioSco();
        }
      }
      Serial.printf("HFP: %s\n", btSlcConectado ? "conectado" : "sin conexion de control");
      if (btSlcConectado) {
        // La ganancia del micrófono al máximo. El volumen del parlante NO se manda:
        // lo manda el teléfono (ver ESP_HF_CLIENT_VOLUME_CONTROL_EVT) y no hay que pisarlo.
        esp_hf_client_volume_update(ESP_HF_VOLUME_CONTROL_TARGET_MIC, 15);
      }
      break;

    case ESP_HF_CLIENT_VOLUME_CONTROL_EVT:
      if (param->volume_control.type == ESP_HF_VOLUME_CONTROL_TARGET_SPK) {
        int v = param->volume_control.volume;
        if (v < 0) v = 0;
        if (v > 15) v = 15;
        scoVolumen = (uint8_t)v;
        Serial.printf("HFP volumen de la voz: %d/15\n", v);
      }
      break;

    case ESP_HF_CLIENT_AUDIO_STATE_EVT: {
      const auto st = param->audio_stat.state;
      const bool abierto = (st == ESP_HF_CLIENT_AUDIO_STATE_CONNECTED ||
                            st == ESP_HF_CLIENT_AUDIO_STATE_CONNECTED_MSBC);
      if (abierto) {
        btScoActivo = true;
        iniciarAudioSco(st == ESP_HF_CLIENT_AUDIO_STATE_CONNECTED_MSBC);
      } else if (st == ESP_HF_CLIENT_AUDIO_STATE_DISCONNECTED) {
        if (btScoActivo) {
          btScoActivo = false;
          detenerAudioSco();
        }
      }
      break;
    }

    case ESP_HF_CLIENT_CIND_CALL_EVT:
      btLlamada = (param->call.status == ESP_HF_CALL_STATUS_CALL_IN_PROGRESS);
      Serial.printf("HFP llamada: %s\n", btLlamada ? "en curso" : "terminada");
      if (btLlamada) abrirSco("llamada");
      break;

    case ESP_HF_CLIENT_BVRA_EVT:
      btVoz = (param->bvra.value == ESP_HF_VR_STATE_ENABLED);
      Serial.printf("HFP asistente de voz: %s\n", btVoz ? "activo" : "apagado");
      if (btVoz) abrirSco("asistente de voz");
      break;

    default:
      break;
  }
}

// ─── Arranque y reconexión ───────────────────────────────────────────────────

// Al arrancar, toma el teléfono enlazado más reciente como destino de reconexión.
static void recordarVinculadoAlArrancar() {
  int cantidad = esp_bt_gap_get_bond_device_num();
  if (cantidad <= 0) {
    Serial.println("Sin teléfono enlazado: emparejar desde el teléfono.");
    return;
  }
  if (cantidad > 4) cantidad = 4;
  esp_bd_addr_t lista[4];
  int n = cantidad;
  if (esp_bt_gap_get_bond_device_list(&n, lista) == ESP_OK && n > 0) {
    recordarBda(lista[0]);
    Serial.print("Teléfono enlazado: ");
    imprimirBda(lista[0]);
    Serial.println();
  }
}

static void conectarA2dp() {
  if (!bdaValido || btA2dpConectado) return;
  if (millis() - ultimoIntentoA2dp < 10000) return;
  ultimoIntentoA2dp = millis();
  esp_a2d_sink_connect(bdaRecordado);  // si el teléfono no responde, se reintenta
}

// Se llama en cada vuelta del loop. Todo está limitado por tiempo.
static void atenderPerfilesBt() {
  conectarHfp("reintento");
  if (btSlcConectado && (btLlamada || btVoz) && !btScoActivo) {
    abrirSco("reintento");
  }
  conectarA2dp();
}

// Configura los perfiles después de SerialBT.begin(), que ya dejó Bluedroid andando.
static void iniciarPerfilesBt() {
  pcmSalida = xStreamBufferCreate(PCM_SALIDA_BYTES, PCM_SALIDA_DISPARO);
  pcmMicro  = xStreamBufferCreate(PCM_MICRO_BYTES, PCM_MICRO_DISPARO);
  if (!pcmSalida || !pcmMicro) {
    Serial.println("ERROR: sin memoria para los buffers de audio Bluetooth");
  }
  xTaskCreate(tareaSalidaAmp, "amp_bt", 4096, nullptr, 5, &tareaSalida);

  esp_bt_gap_register_callback(gapEventoBt);

  // Clase de dispositivo: auricular inalámbrico con audio y telefonía. Es lo que
  // hace que el teléfono lo muestre como auricular y no como un dispositivo cualquiera.
  esp_bt_cod_t cod = {};
  cod.major = ESP_BT_COD_MAJOR_DEV_AV;
  cod.minor = 0x01;  // auricular inalámbrico
  cod.service = ESP_BT_COD_SRVC_AUDIO | ESP_BT_COD_SRVC_TELEPHONY;
  esp_bt_gap_set_cod(cod, ESP_BT_SET_COD_ALL);

  // El audio de llamada tiene que llegar por HCI (como PCM), no por el códec
  // interno del chip, para poder usar el micrófono y el parlante propios. Va
  // antes de inicializar HFP.
  esp_bredr_sco_datapath_set(ESP_SCO_DATA_PATH_HCI);

  esp_hf_client_register_data_callback(hfDatosEntrada, hfDatosSalida);
  esp_hf_client_register_callback(hfEventoBt);
  esp_hf_client_init();

  esp_a2d_register_callback(a2dpEventoBt);
  esp_a2d_sink_register_data_callback(a2dpDatosPcm);
  esp_a2d_sink_init();

  recordarVinculadoAlArrancar();
}

void setup() {
  Serial.begin(115200);

  if (!LittleFS.begin(true)) {
    Serial.println("Error al montar LittleFS");
    // No se corta: la reproducción en streaming no necesita LittleFS, solo
    // los comandos 'D' e 'I'. Antes un fallo acá dejaba el firmware muerto.
  }

  initMicrophoneI2S();
  initAmplifierI2S();

  SerialBT.begin("ESP32_BlindRoute");
  SerialBT.register_callback(alCambiarConexion);
  iniciarPerfilesBt();  // A2DP (música) y HFP (llamadas y voz), además del SPP
  Serial.printf("Firmware %s\n", FW_VERSION);
  Serial.println("Listo. Esperando conexion Bluetooth...");
  Serial.printf("Mic : 32-bit I2S, shift=%d, %d Hz, %s, esperado %d bloques/s\n",
                MIC_SHIFT, SAMPLE_RATE,
                USAR_ULAW ? "u-law 8bit" : "PCM 16bit",
                SAMPLE_RATE / MUESTRAS_POR_BLOQUE);
  Serial.printf("Play: buffer %d bytes (%d ms), prebuffer %d bytes (%d ms), vol %d%%\n",
                RING_BYTES, (RING_BYTES * 1000) / SAMPLE_RATE,
                PREBUFFER_BYTES, (PREBUFFER_BYTES * 1000) / SAMPLE_RATE,
                PLAY_VOLUMEN);
}

void loop() {

  // 0. Si cambió la conexión, la sesión de audio anterior ya no vale: se corta
  //    lo que suena y se vacía el anillo antes de atender lo nuevo.
  if (clienteCambio) {
    clienteCambio = false;
    if (modoActual == MODO_AUDIO) detenerCaptura();
    if (estadoPlay != PLAY_IDLE) terminarReproduccion("cambio de conexion");
    rxEstado = RX_CMD;
    ringVaciar();
    Serial.println("Conexion Bluetooth cambio: sesion de audio reiniciada");
  }

  // 0b. Reconectar con el teléfono y abrir la llamada si hace falta.
  atenderPerfilesBt();
  atenderComandosUsb();
  imprimirDiagnosticoBt();

  // 1. Atender la radio siempre, pase lo que pase.
  servicioBluetooth();

  // 2. Alimentar el parlante si hay algo sonando.
  alimentarAltavoz();

  // 3. Capturar del micrófono si está en ese modo.
  if (modoActual == MODO_AUDIO) {
    capturarYEnviarAudio();
  }

  // 4. Reporte por serie una vez por segundo.
  uint32_t ahora = millis();
  if (ahora - ultimoReporte >= 1000) {
    if (modoActual == MODO_AUDIO) {
      if (bloquesDescartadosTx > 0) {
        Serial.printf("[mic] %lu bloques/s  (%lu DESCARTADOS: enlace saturado)\n",
                      bloquesEnviados, bloquesDescartadosTx);
      } else {
        Serial.printf("[mic] %lu bloques/s\n", bloquesEnviados);
      }
      bloquesEnviados = 0;
      bloquesDescartadosTx = 0;
    }
    if (estadoPlay != PLAY_IDLE) {
      Serial.printf("[play] buffer %u/%d bytes, %lu underruns\n",
                    (unsigned)ringDisponible(), RING_BYTES, sesUnderruns);
    }
    ultimoReporte = ahora;
  }
}
