# Auricular BlindRoute: cómo funciona (firmware 2.1)

El ESP32 se muestra al teléfono como **ESP32_BlindRoute**, con clase de dispositivo de **auricular inalámbrico**. Tiene un micrófono (INMP441) y un parlante (MAX98357A). Con el firmware 2.0 funciona como auricular de verdad: la música y los sonidos de cualquier app salen por el parlante, y las llamadas y el asistente de voz del teléfono usan el micrófono y el parlante del auricular.

Este documento explica qué hace cada parte del firmware, qué esperar en cada app y cómo probarlo.

## 1. Los tres canales Bluetooth

| Canal | Perfil | Para qué | Qué apps lo usan |
|---|---|---|---|
| Música y sonidos | **A2DP** (receptor de audio) | El teléfono manda audio estéreo y el ESP32 lo reproduce en mono por el parlante | Cualquier app que reproduce audio: música, videos, notificaciones, TTS |
| Llamadas y voz | **HFP** (manos libres) | El teléfono abre un canal de voz bidireccional: el parlante reproduce la voz del otro lado y el micrófono manda la voz de este lado | Llamadas del teléfono, asistente de voz del sistema, apps que piden el micrófono Bluetooth |
| Protocolo BlindRoute | **SPP** (puerto serie) | Comandos y audio propio de la app (sin cambios desde la versión 1.1) | La app de BlindRoute, cuando se conecte |

Los tres conviven: el teléfono puede tener música por A2DP y, al entrar una llamada, pasar la voz a HFP.

## 2. Cómo lo ve el teléfono

- **Nombre:** ESP32_BlindRoute.
- **Clase de dispositivo:** auricular inalámbrico (audio y telefonía). Por eso el teléfono lo muestra como auricular y no como un dispositivo genérico.
- **Emparejamiento:** el auricular no tiene pantalla ni teclado, así que empareja en modo "Just Works": el teléfono pregunta "¿Vincular?" y el ESP32 acepta sin código. Si un teléfono viejo pide PIN, el PIN es `0000`.
- **Reconexión:** el ESP32 guarda en su memoria no volátil el **último teléfono usado** (el último que se emparejó o se conectó). Lo busca durante **60 segundos** al arrancar y cuando se pierde el enlace por distancia, turnando un intento de HFP y uno de A2DP cada 6 segundos. Pasado ese tiempo deja de buscar y queda visible y conectable: el teléfono se conecta él, desde Ajustes → Bluetooth.

### 2.1 Por qué un teléfono podía no conectarse (corregido en la 2.1)

Hasta la versión 2.0 el auricular buscaba al teléfono **para siempre**: un intento de HFP cada 5 segundos y uno de A2DP cada 10. Cada intento ocupa la radio hasta 5 segundos si el teléfono no contesta, así que la radio pasaba casi todo el tiempo llamando al teléfono recordado y casi no escuchaba a otros. Además, el teléfono recordado era el **primero** de la lista de vinculados, no el último usado.

Con el Samsung vinculado primero, al probar con otro teléfono (el Pixel) pasaba una de dos cosas:

- con el Samsung cerca y con Bluetooth, el ESP32 se reconectaba al Samsung y ocupaba A2DP y HFP, que admiten un solo teléfono a la vez: el Pixel podía emparejar pero no conectar;
- con el Samsung lejos, la radio estaba ocupada llamándolo y el Pixel no lo encontraba o se cansaba de esperar.

Si después de cargar la 2.1 un teléfono sigue sin conectar, puede haber una clave vieja (uno de los dos lados olvidó el vínculo y el otro no). El puerto serie lo muestra como `Emparejamiento fallido (estado N)`. Se arregla olvidando en los dos lados: en el teléfono, Ajustes → Bluetooth → ESP32_BlindRoute → Olvidar; en el ESP32, el comando `o` por USB.

## 3. Qué pasa dentro del ESP32

```
Música (A2DP) ──► pcmSalida ──► tareaSalidaAmp ──► I2S ──► MAX98357A (parlante)
Voz (HFP RX) ──► pcmSalida ──► tareaSalidaAmp ──► I2S ──► MAX98357A (parlante)

INMP441 ──► I2S ──► tareaMicroSco ──► pcmMicro ──► HFP TX ──► teléfono
```

- `pcmSalida` y `pcmMicro` son buffers circulares (stream buffers de FreeRTOS). Desacoplan la radio Bluetooth del I2S: la radio nunca espera al audio.
- `tareaSalidaAmp` es una tarea propia que se queda bloqueada en el I2S. Así el loop principal sigue atendiendo el SPP y la conexión.
- La **librería Bluetooth del núcleo ESP32 codifica y decodifica el audio de llamada**: el firmware recibe y entrega PCM de 16 bits. El códec de la llamada (CVSD a 8 kHz o mSBC a 16 kHz) lo negocia el teléfono solo.
- La tasa del amplificador se reconfigura en el momento: 8 kHz para CVSD, 16 kHz para mSBC, y la del codec A2DP (16, 32, 44,1 o 48 kHz) para la música. Cuando no hay audio Bluetooth, vuelve a 8 kHz para el SPP.

## 4. Prioridad entre canales

Mientras hay audio A2DP o HFP, el SPP **no** toca el parlante ni el micrófono:

- Una captura SPP (comando `M`) se ignora y lo avisa por serie.
- Una reproducción SPP se descarta sin trabar el enlace.
- Una llamada corta cualquier captura o reproducción SPP que esté en curso.

En la práctica: si estás escuchando música y entra una llamada, la voz de la llamada tiene prioridad. Al terminar la llamada, la música puede volver sola si el teléfono la reanuda.

### 4.1 Sonido de la música (ecualizador y limitador)

El parlante es chico: no mueve los graves y exagera los medios agudos. Eso suena metálico, chato y enlatado. Para compensarlo, la música (solo la música, no la voz de las llamadas) pasa por un procesamiento antes del amplificador.

**Salida en estéreo (2.1).** Hasta la 2.0 el amplificador se configuraba en modo mono de 16 bits. En el ESP32 clásico ese modo lee las muestras de a pares, y si salen en el orden invertido aparece una copia espejada del sonido: en las llamadas (8 o 16 kHz) cae en plena voz y suena metálico o robótico; en la música (44,1 kHz) agrega un brillo áspero arriba de 14 kHz. Desde la 2.1 el firmware manda tramas estéreo con la misma muestra en las dos ranuras (como el firmware viejo de solo A2DP): así el orden no importa y las dos ranuras van llenas.

**Colchón de la música (2.1).** Antes de empezar a sonar, y después de un corte, se juntan 80 ms de música (`PREBUFFER_A2DP_MS`). Sin colchón, cualquier ráfaga atrasada del Bluetooth dejaba al amplificador sin datos y metía un hueco de silencio; muchos huecos seguidos suenan ásperos. El informe `[bt-audio]` cuenta esos huecos en `cortes`.

El resto del procesamiento:

- **Ecualizador de 4 etapas** (filtros biquad). Con el preset 1 (el de arranque): corta lo que está por debajo de 140 Hz, que el parlante no puede reproducir y solo lo hace distorsionar; baja 3 dB la zona áspera alrededor de 3,5 kHz; y suaviza 2 dB por encima de 7 kHz.
- **Ganancia y limitador.** La ganancia de arranque es +3 dB. Un limitador (techo cerca de −1 dBFS, ataque inmediato y suelta en unos 80 ms) evita que los picos hagan distorsionar el parlante, así sube el volumen que se percibe sin romper el sonido.
- **Las dos ranuras del I2S.** El audio sale repetido en la ranura izquierda y la derecha. El MAX98357A con el pin SD sin forzar mezcla las dos ranuras; con una sola ranura llena sale la mitad del volumen (6 dB menos).

Presets, que se cambian en caliente por el puerto USB (115200 baudios, un comando por línea, terminado en enter):

| Comando | Efecto |
|---|---|
| `p0` | Sin proceso (como sonaba antes de esta mejora, sirve para comparar) |
| `p1` | Claro (el de arranque): graves cortados y zona áspera suavizada |
| `p2` | Cálido: además da un poco de cuerpo a 300 Hz |
| `p3` | Voz: realza la zona de la voz y quita lo que molesta |
| `g` y un número de 0 a 12 (por ejemplo, `g5`) | Ganancia en dB antes del limitador |
| `q` | Muestra el preset, la ganancia y el volumen de llamada actuales |
| `m` y un número de segundos (por ejemplo, `m8`) | Prueba del micrófono sin llamada: imprime el nivel (`[mic] pico=... rms=...`) cada 250 ms. Sirve para verificar el cableado del micrófono |
| `o` | Olvida todos los teléfonos vinculados (y el último usado). Hay que olvidar el auricular también en el teléfono y emparejarlo de nuevo |

Los cambios por USB valen hasta que se reinicia la placa. Para dejar otro valor de arranque se cambian `eqPreset` y `gananciaDb` en el firmware.

Mientras suena música, el firmware imprime cada 2 segundos una línea `[bt-audio]` con el audio recibido, el pico, lo que se escribió al parlante, los cortes, el preset, la ganancia y cuánto está bajando el limitador. Si el limitador baja con frecuencia más de 6 dB, la ganancia es demasiada para esa música.

#### Qué probar si suena metálico

En orden, de lo más probable a lo menos:

1. **Ver si es en las llamadas o en la música.** Si el puerto serie dice `Llamada: audio CVSD 8 kHz`, la llamada usa el códec de telefonía de banda angosta: suena a teléfono fijo por naturaleza. La banda ancha (mSBC, 16 kHz) depende de cómo está compilada la librería Bluetooth del núcleo, no de este firmware.
2. **Comparar `p0` con `p1`.** Si con `p0` (sin proceso) suena mejor, el ecualizador no le sienta a ese parlante: probar `p2` o `p3`.
3. **Bajar la ganancia: `g0`.** El limitador sube el volumen a costa de deformar los picos (corta en el acto, sin anticipar). Si el informe muestra `limitador` más allá de −3 dB todo el tiempo, sobra ganancia.
4. **Mirar `cortes`.** Si crece mientras suena, subir `PREBUFFER_A2DP_MS` a 100-150.
5. **Mirar el `bitpool`** en la línea `A2DP SBC`: con un máximo menor que 53, el teléfono está mandando la música con menos calidad.

Otros parámetros que se pueden tocar en el código, con su efecto:

| Parámetro | Valor | Qué cambia |
|---|---|---|
| `eqPreset` | 1 | Preset del ecualizador al arrancar (0 a 3) |
| `gananciaDb` | 3 | Ganancia antes del limitador, en dB. Más volumen, más deformación |
| `LIM_UMBRAL` | 29500 | Techo del limitador (~−1 dBFS) |
| `PREBUFFER_A2DP_MS` | 80 | Colchón de la música. Más: menos cortes y más retardo |
| `PCM_SALIDA_BYTES` | 16384 | Buffer entre el Bluetooth y el parlante (~186 ms a 44,1 kHz) |
| `use_apll` en `initAmplifierI2S` | false | Con `true`, el reloj del I2S sale del APLL y la frecuencia es exacta. El efecto audible con el MAX98357A es mínimo |
| Pin GAIN del MAX98357A | (hardware) | La ganancia del amplificador: 9 dB sin conectar. Si satura con volumen alto, bajarla con el pin es mejor que bajar el volumen digital |

## 5. Pines

| Señal | Pin del ESP32 | Conexión |
|---|---|---|
| Micrófono SCK (BCLK) | GPIO25 | INMP441 SCK |
| Micrófono WS (LRCLK) | GPIO33 | INMP441 WS |
| Micrófono SD (DOUT) | GPIO34 | INMP441 SD (GPIO34 es solo entrada: sirve para SD) |
| Micrófono L/R | GND | Canal izquierdo |
| Micrófono VDD | 3V3 | INMP441 VDD |
| Amplificador BCLK | GPIO26 | MAX98357A BCLK |
| Amplificador LRC | GPIO27 | MAX98357A LRC |
| Amplificador DIN | GPIO14 | MAX98357A DIN |

Las constantes están en el firmware como `MIC_SCK_IO`, `MIC_WS_IO`, `MIC_SD_IO`, `AMP_BCLK_IO`, `AMP_LRC_IO` y `AMP_DIN_IO`. Si cambia el cableado, se cambian ahí y nada más.

## 6. Cómo emparejarlo y probarlo (paso a paso)

1. **Olvidar el auricular si ya estaba emparejado.** Hace falta si se emparejó con una versión anterior (solo SPP): el teléfono guarda los perfiles que tenía y no pide los nuevos. En el celular: Ajustes → Bluetooth → ESP32_BlindRoute → Olvidar.
2. **Dejar el ESP32 con USB o batería** y cerca del teléfono (menos de 2 m al principio).
3. **Emparejar desde el teléfono:** Ajustes → Bluetooth → buscar dispositivos → ESP32_BlindRoute.
4. **Revisar que estén activados los dos interruptores** del dispositivo: *Llamadas* (o "Audio de llamadas") y *Contenido multimedia* (o "Audio"). Si uno falta, activarlo.
5. **Probar música:** poner un video o una canción en cualquier app. El audio tiene que salir por el auricular.
6. **Probar llamada:** llamar desde otro teléfono o hacer una llamada de prueba. Contestar en el celular y hablar: la voz tiene que salir por el auricular y la del micrófono tiene que llegar a la otra persona.
7. **Probar asistente:** activar el asistente de voz del teléfono (por ejemplo, con el botón lateral o "Ok Google") y hablar. El micrófono del auricular tiene que tomar la voz.

El firmware escribe en el puerto serie (115200 baudios) cada evento. Ver la sección 8.

## 7. Qué funciona con qué apps

| Qué hacés | Sale por el auricular | Se usa el micrófono del auricular |
|---|---|---|
| Música, videos, juegos, notificaciones de cualquier app | Sí (A2DP) | No aplica |
| Llamada del teléfono (contestando en el celular) | Sí (HFP) | Sí |
| Asistente de voz del sistema | Sí (HFP) | Sí |
| WhatsApp, Telegram u otra app de llamadas | Sí (HFP, mientras dura la llamada) | Sí (mientras dura la llamada) |
| Nota de voz de WhatsApp o una grabadora normal | Sí (si hay música o voz) | **No**: Android usa el micrófono del teléfono |
| La app de BlindRoute, para escuchar a Blind Route o dictar | Sí | **Todavía no**: hace falta código Android que pida el micrófono Bluetooth (ver sección 9) |

Android solo manda el micrófono Bluetooth a una app en tres casos: una llamada, el asistente de voz del sistema, o una app que lo pide explícitamente con la API de Android. Las grabadoras y las notas de voz comunes no lo piden.

## 8. Mensajes del puerto serie

| Mensaje | Qué significa |
|---|---|
| `Firmware 2.1` | Arrancó la versión con A2DP, HFP y la reconexión por ventana |
| `Último teléfono usado: XX:...` | El teléfono que va a buscar al arrancar (guardado en la memoria) |
| `Buscando al teléfono durante 60 s (...)` | Abrió la ventana de reconexión (al arrancar o porque se perdió el enlace) |
| `Fin de la búsqueda del teléfono (...)` | Se cerró la ventana: ya conectó, se emparejó otro teléfono o no contestó |
| `Teléfono recordado: XX:...` | Cambió el último teléfono usado |
| `Emparejamiento fallido (estado N)` | El emparejamiento no se completó. Si se repite, olvidar el auricular en los dos lados (en el ESP32, comando `o`) |
| `Teléfono enlazado: XX:XX:XX:XX:XX:XX` | Hay un solo teléfono vinculado y es el que va a buscar |
| `HFP listo: si` | El perfil de manos libres está activo |
| `HFP: conectando (...)` | Intenta conectar el canal de control con el teléfono |
| `HFP: conectado` | Canal de control abierto: el teléfono conoce al auricular |
| `HFP: sin conexion de control` | El teléfono no respondió (está lejos, apagado o no tiene el perfil activado) |
| `A2DP: conectando con ...` | Intenta conectar la música con el teléfono (solo dentro de la ventana de reconexión) |
| `HFP llamada: en curso` / `terminada` | Estado de la llamada, según el teléfono |
| `HFP asistente de voz: activo` / `apagado` | Estado del asistente de voz |
| `HFP: abriendo audio (...)` | Pide abrir el canal de voz |
| `Llamada: audio mSBC 16 kHz` / `CVSD 8 kHz` | Códec negociado con el teléfono |
| `Llamada: audio cerrado` | Terminó el canal de voz |
| `A2DP conectado con ...` / `A2DP desconectado` | Conexión de música. `(se perdió el enlace)`: se cortó por distancia y abre la ventana de reconexión |
| `A2DP codec SBC a 44100 Hz` | Tasa de la música que manda el teléfono |
| `A2DP audio: sonando` / `parado` | Hay música o no |
| `A2DP SBC: canales=... bitpool=2..53` | Parámetros del códec que negoció el teléfono (calidad alta: joint stereo, 16 bloques, 8 subbandas, bitpool hasta 53) |
| `[bt-audio] A2DP in=... pico=... \| parlante out=... cortes=... \| preset=... g=... limitador=... dB` | Cada 2 s con música: bytes recibidos, pico de la señal, bytes escritos al parlante, huecos sin datos, preset, ganancia y reducción del limitador |
| `Sonido: preset N` / `Sonido: ganancia +X dB` | Respuesta a un comando de sonido por USB |
| `HFP volumen de la voz: N/15` | El usuario cambió el volumen de la llamada en el celular. El auricular baja o sube él mismo la voz que reproduce (3 dB por paso; 0 es silencio) |
| `[sco-mic] leido=... pico=... \| pedido por el Bluetooth=... veces, entregado=... bytes, sin audio=... veces` | Durante una llamada, cada 2 s: audio que salió del micrófono, su pico, y cuánto de eso pidió y recibió el teléfono. `entregado` tiene que crecer; si queda en 0, el teléfono no está pidiendo el audio del micrófono |
| `[mic] pico=... rms=...` | Nivel del micrófono durante la prueba `m` |
| `Captura SPP ignorada: ...` | Se pidió micrófono SPP mientras una llamada o la música lo usan |

## 9. Límites conocidos y lo que falta

- **Micrófono para BlindRoute:** el firmware ya entrega el micrófono por HFP. La app de BlindRoute, para usarlo en su propio reconocimiento de voz, tiene que pedir el canal de voz al sistema (Android: AudioManager y el micrófono de comunicación). Eso es código Android nativo y requiere permiso explícito del proyecto.
- **Calidad en llamadas:** mientras hay un canal de voz abierto, el teléfono puede bajar la música a la calidad de llamada. Es el comportamiento normal de Android con cualquier auricular.
- **Un teléfono a la vez:** A2DP y HFP atienden un solo teléfono a la vez. El auricular busca solo al último usado; otro teléfono vinculado se conecta desde sus ajustes de Bluetooth.
- **Emparejamiento sin confirmación:** el auricular acepta el emparejamiento sin PIN ni confirmación, porque no tiene pantalla. Mientras esté en modo emparejamiento, cualquiera en rango lo puede emparejar. Si esto preocupa, se puede pedir un PIN.
- **Sin botones:** contestar y colgar se hace en el teléfono (o con el asistente de voz).
- **Latencia y calidad:** no medidas todavía. Se miden en la prueba de llamada y de música del punto 6.
- **Riesgo del cableado:** el micrófono tiene que estar bien conectado (GND, 3V3 y los pines de la tabla). Con un corto como el anterior, el firmware no lo detecta.

## 10. Protocolo SPP (sin cambios)

La app de BlindRoute se comunica por SPP con estos comandos de un byte:

| Comando | Qué hace |
|---|---|
| `D` | Reproduce `/derecha.wav` desde LittleFS (si existe) |
| `I` | Reproduce `/izquierda.wav` desde LittleFS (si existe) |
| `M` | Empieza a mandar el micrófono al teléfono (μ-law, 8 kHz). Half-duplex: corta la reproducción en curso |
| `S` | Para la captura del micrófono |
| `P` | Para la reproducción en streaming que esté sonando |
| `T` | Devuelve una línea de telemetría en texto (estadísticas del audio) |
| `V` | Devuelve la versión del firmware |

El audio para reproducir llega del teléfono con el marcador `0xBB`, una longitud de 2 bytes y datos μ-law, y termina con `0xBE`. El audio del micrófono sale hacia el teléfono con el marcador `0xAA`, una longitud de 2 bytes y datos μ-law.

Los comandos `M` y la reproducción SPP no funcionan mientras una llamada o la música usa el micrófono o el parlante (ver la sección 4).

## 11. Compilar y cargar

Con `arduino-cli` y el núcleo `esp32` de Espressif (probado con la versión 3.3.11), desde la raíz del repositorio:

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 hardware/esp32_blindroute_audio
arduino-cli upload -p <puerto> --fqbn esp32:esp32:esp32 hardware/esp32_blindroute_audio
```

También se puede abrir el archivo `.ino` en Arduino IDE, con la placa "ESP32 Dev Module".

## 12. Archivos

- `esp32_blindroute_audio.ino`: el firmware (versión 2.1).
- `COMO_FUNCIONA.md`: este documento.

Este firmware reemplaza al de `hardware/esp32_blindroute_a2dp`, que solo tenía música (A2DP): el nuevo suma las llamadas y el micrófono (HFP), el ecualizador y el protocolo SPP de BlindRoute.
