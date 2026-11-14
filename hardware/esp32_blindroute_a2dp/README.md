# Firmware del ESP32: auricular Bluetooth

Firmware del auricular de BlindRoute. El ESP32 se presenta ante Android como unos auriculares (perfil A2DP) y reproduce por el parlante el audio que envía el celular, en tiempo real. No depende de la aplicación: Android envía al auricular conectado el audio multimedia del teléfono.

## Qué hace

- Se empareja como `ESP32_BlindRoute`, con la clase de dispositivo Audio/Video, Headphones.
- Recibe el audio por A2DP, lo guarda en un buffer de 32 KB, lo convierte a mono y lo envía por I2S al amplificador MAX98357A.
- Espera 100 ms de audio antes de sonar, para evitar cortes. Esa espera suma unos 100 ms de retardo.
- El puerto serie Bluetooth (SPP) solo sirve para comandos: `V` devuelve la versión y `T`, el estado y los contadores (conexión, frecuencia, bytes en el buffer, recibidos, descartados, cortes y memoria libre). Los mismos comandos funcionan por USB.

## Hardware

Placa ESP32 DevKit V1, amplificador MAX98357A y un parlante.

| Señal del amplificador | GPIO |
|---|---|
| BCLK | 26 |
| LRC | 27 |
| DIN | 14 |

## Compilar y cargar

Con `arduino-cli` y el núcleo `esp32` de Espressif (probado con la versión 3.3.11):

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 hardware/esp32_blindroute_a2dp
arduino-cli upload -p <puerto> --fqbn esp32:esp32:esp32 hardware/esp32_blindroute_a2dp
```

También se puede abrir el archivo `.ino` en Arduino IDE, con la placa "ESP32 Dev Module".

## Uso

1. Alimentar la placa y buscar `ESP32_BlindRoute` en los ajustes de Bluetooth del celular.
2. Emparejar el dispositivo y activar "Audio multimedia".
3. Reproducir cualquier audio en el celular.

## Ajustes en el código

- `PREBUFFER_MS`: audio que se junta antes de sonar. Si hay cortes, conviene subirlo (150 a 200); si el retardo molesta y no hay cortes, bajarlo.
- `VOLUMEN_PCT`: tope de volumen por software. El volumen de uso se regula desde el celular.
- `TAM_BUFFER_BYTES`: tamaño del buffer de audio.

## Estado

El parlante está probado en la placa con un celular Android. El micrófono (INMP441) no forma parte de este firmware: se agregará cuando funcione, con el perfil de manos libres (HFP). Mientras tanto se usa el micrófono del celular.
