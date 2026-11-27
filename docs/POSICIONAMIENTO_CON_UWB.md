# Posicionamiento con UWB: análisis y plan de trabajo

BlindRoute calcula la posición de la persona a partir de la potencia con la que llega la señal de los beacons Bluetooth (RSSI), y aunque el cálculo pasa por varias etapas de filtrado, en las pruebas la posición resultó demasiado imprecisa para guiar a alguien hasta dejarlo de frente a una puerta, que es lo que pide el radio de llegada de 0,5 m que usa la app. Por esto se analizó cambiar la tecnología con la que se mide la posición, comparando el BLE actual con UWB (banda ultraancha) y con Bluetooth Channel Sounding, y se llegó a una arquitectura en la que los teléfonos con UWB miden directamente contra antenas fijas, mientras que los que no lo tienen siguen usando el BLE que emiten esas mismas antenas.

En este documento se explica por qué el BLE no alcanza, qué tecnologías se evaluaron, cómo queda la arquitectura, qué hardware se va a usar, qué incógnitas quedan abiertas y cómo se van a separar los filtros según la tecnología, y en la sección 7 se detalla el plan de trabajo por etapas, pensado para probar cada parte antes de pasar a la siguiente. La información sobre teléfonos, bibliotecas y precios corresponde al 26 de noviembre de 2026 y puede cambiar.

## 1. Por qué el BLE no alcanza

### 1.1 El límite del RSSI

Con BLE la distancia a cada beacon se estima con el modelo log-distancia, `rssi = tx − 10 · n · log10(d)`, de modo que todo lo que cambia la potencia recibida sin cambiar la distancia termina convertido en un error de distancia. Dentro de un edificio la potencia que llega desde un mismo punto varía por los rebotes en las paredes, por el cuerpo de la persona, que a 2,4 GHz absorbe buena parte de la señal, y por la orientación del teléfono, y en la bibliografía esa variación suele tener un desvío de 4 a 6 dB, valor típico que no se midió en el edificio. Un desvío de σ dB multiplica o divide la distancia estimada por un factor que se calcula como:

```
factor = 10^(σ / (10 · n))
```

Con el n = 2,7 que usa la app por defecto queda:

```
σ = 4 dB  →  factor = 10^(4 / 27) = 10^0,148 = 1,41
σ = 6 dB  →  factor = 10^(6 / 27) = 10^0,222 = 1,67
```

Aplicado a una persona parada a 5 m de un beacon, con 4 dB la distancia estimada puede quedar entre 5 / 1,41 = 3,6 m y 5 × 1,41 = 7,0 m, y con 6 dB entre 3,0 y 8,3 m. Ese error depende del camino que recorre la señal y del teléfono que la recibe, mientras que el beacon que la emite influye poco, por lo que comprar beacons de mejor calidad casi no cambia el resultado, ya que una antena más pareja o una potencia más estable pueden ganar uno o dos dB (estimación propia, sin medir), muy por debajo de la variación que agrega el ambiente.

A esto se suma la diferencia de ganancia entre teléfonos, que sigue sin resolver y que está explicada en la sección 10 de `AJUSTES_EN_EL_EDIFICIO.md`: cada modelo mide el RSSI con algunos dB de diferencia y, como las calibraciones se toman con el teléfono del administrador, otro modelo estira o achica todas las distancias, y en una simulación una diferencia de 3 a 5 dB llevó el error medio a entre 2,7 y 5 m. Cabe aclarar que ese número sale de una simulación y que el error de la cadena actual nunca se midió en un recorrido real, por lo que la primera etapa del plan incluye esa medición.

### 1.2 Hasta dónde llega el BLE bien usado

Como referencia de lo máximo que se puede esperar del BLE se tomó NavCog, el sistema de navegación para personas ciegas de la Universidad Carnegie Mellon, que combina beacons BLE con el conteo de pasos del teléfono y un filtro de partículas. En un estudio de campo con recorridos reales llegó a 1,6 m de error promedio, con el 93,8 % de 260 giros bien hechos, usando como mínimo un beacon cada 6 m y un relevamiento de la señal en toda el área. Ese error alcanza para anunciar los giros a tiempo, pero no para dejar a la persona de frente a un lugar con un radio de llegada de 0,5 m, y por eso se decidió cambiar la tecnología que mide la posición, conservando el BLE como respaldo para los teléfonos que no tienen UWB (sección 3).

## 2. Tecnologías evaluadas

En la Tabla 1 se resumen las opciones que se compararon, cuyas características se explican por separado a continuación.

Tabla 1. Tecnologías evaluadas para medir la posición.

| Tecnología | Precisión esperable | Teléfonos compatibles | Resultado |
|---|---|---|---|
| BLE por RSSI (actual) | Sin medir en el edificio; 1,6 m en el mejor sistema publicado | Todos | Queda como respaldo |
| BLE con beacons de mejor calidad | Casi igual a la actual | Todos | Descartado |
| Bluetooth Channel Sounding | 16 a 28 cm al aire libre, peor dentro de un edificio | Pixel 10 y pocos más | Se revisa más adelante |
| UWB en el teléfono | 10 a 30 cm con línea de vista | Sólo gama alta | Elegido para los teléfonos que lo tienen |
| UWB con un dispositivo prestado por el local | 10 a 30 cm con línea de vista | Todos | Opción futura con las mismas antenas |

### 2.1 UWB

UWB mide cuánto tarda la señal en ir y volver entre dos equipos, en lugar de la potencia con la que llega. La luz recorre 30 cm en un nanosegundo, y como la señal ocupa 500 MHz de ancho de banda, cada pulso dura unos 2 ns, lo que le permite al receptor separar el camino directo de los rebotes, que llegan después porque recorren más distancia. Como el tiempo de vuelo no depende de la ganancia del teléfono, con UWB desaparece el problema de la diferencia entre modelos y dejan de hacer falta la recta (n, tx) de cada beacon y la mayoría de los puntos clave.

El error que queda aparece cuando el cuerpo tapa el camino directo, ya que a 6,5 y 8 GHz el cuerpo bloquea mucho la señal y el receptor puede engancharse en un rebote, dando una distancia más larga que la real. Ese error siempre alarga la distancia, por lo que se comporta como un sesgo, y es el tipo de lectura que descartan los pesos de Huber del `Posicionador`.

Según la lista de Google de enero de 2025, tienen UWB los Pixel Pro desde el 6 Pro, el Pixel Fold y la Pixel Tablet, los Samsung Galaxy S Plus y Ultra desde el S21, el Note 20 y los Z Fold desde el Fold2, y el Motorola Edge 50 Ultra, mientras que los modelos base (como el Pixel 9 o el Galaxy S24 común) y la línea Galaxy A no lo tienen. En Android se usa con la biblioteca Jetpack `androidx.core.uwb`, estable desde mayo de 2026, que funciona desde Android 12 y pide el permiso `UWB_RANGING`, o con el módulo Ranging de Android 16 en adelante, que pide el permiso `RANGING`. En los dos casos, antes de medir, los equipos tienen que intercambiar por otro medio (por ejemplo BLE) la dirección UWB, el canal y la clave de la sesión, y esos valores pueden cambiar en cada sesión.

### 2.2 Bluetooth Channel Sounding

Channel Sounding es una función de Bluetooth 6.0 en la que dos equipos conectados, uno que inicia y otro que refleja, intercambian tonos en hasta 72 canales de 1 MHz entre 2402 y 2480 MHz y calculan la distancia a partir de cómo cambia la fase de la señal con la frecuencia, comprobándola con el tiempo de ida y vuelta. Se evaluó porque todos los teléfonos tienen Bluetooth y, a largo plazo, podría llegar a la gama media sin necesidad de un dispositivo extra, pero en este momento tiene varios problemas para BlindRoute.

Primero que todo, la medición ocurre entre dos equipos conectados, de uno a uno, y aunque un teléfono puede abrir varias conexiones y medir con cada una por turno (los chips aguantan del orden de 20 conexiones), Nordic indica que medir en varias conexiones a la vez es posible pero todavía no está optimizado, y en su foro hay casos en los que sólo respondía el primer equipo. Del lado de Android, quien responde atiende a un solo iniciador a la vez, por lo que cada antena del edificio atendería a un teléfono por vez, y al caminar aparecen antenas nuevas todo el tiempo, cada una con una búsqueda y una conexión que pueden tardar segundos.

Por otro lado, la mejor precisión medida que se encontró fue de 16 a 28 cm en el 90 % de las mediciones, entre 0,5 y 5,5 m, en un campo abierto elegido para que no hubiera rebotes, mientras que dentro de un edificio y sin línea de vista una tesis de la Universidad de Lund encontró claras dificultades. Esto se debe en parte al ancho de banda, ya que con unos 80 MHz dos caminos cuya diferencia de recorrido es menor que la resolución se confunden:

```
resolución = c / B
Channel Sounding:  3 × 10^8 m/s / 80 × 10^6 Hz  = 3,75 m
UWB:               3 × 10^8 m/s / 500 × 10^6 Hz = 0,6 m
```

Finalmente, el único teléfono confirmado es el Pixel 10, los Galaxy S26+ y S26 Ultra aparecen como probables sin confirmación oficial, el módulo Ranging pide Android 16 y Android sólo deja medir en segundo plano con UWB. También existe una propuesta de 2026 para hacer Channel Sounding sin conexión y con miles de equipos, que por ahora es un prototipo sobre placas nRF54L15 con firmware propio que ningún teléfono puede usar.

### 2.3 Dispositivo prestado por el local

Otra opción que se analizó fue que el local preste un dispositivo con UWB, colgado del pecho, que mida las distancias a las antenas y se las mande al teléfono por BLE, de forma que cualquier teléfono, aun sin UWB, tenga la misma precisión. Esta opción resuelve el problema de la compatibilidad, pero obliga al local a entregar, cargar, limpiar y recuperar los dispositivos, y por eso se dejó para más adelante. Cabe aclarar que, si las antenas usan FiRa, un dispositivo FiRa se comporta frente a ellas igual que un teléfono con UWB, por lo que esta opción se puede agregar después sin cambiar nada del edificio (sección 3.4).

## 3. Arquitectura elegida

### 3.1 Funcionamiento general

Las antenas fijas son módulos Qorvo DWM3001C con firmware FiRa, que es el protocolo que usa Android para medir con UWB, y cada una emite también un aviso iBeacon por BLE con el mismo formato que leen hoy los Holy-IOT. Al abrir la navegación la app elige la fuente de las distancias según el teléfono:

1. Si el teléfono tiene UWB, está activado y Android deja usarlo, mide contra las antenas por UWB.
2. Si no, usa el RSSI de los avisos BLE de las mismas antenas, como hace hoy con los beacons.
3. Si un teléfono con UWB ve menos de 3 antenas por UWB (por ejemplo en un rincón), pasa al BLE hasta volver a verlas.

En los dos casos la posición se calcula en el teléfono con el `Posicionador`, que ya recibe distancias en 3D junto con la altura de cada antena (`ObservacionRango`), así que la posición sigue sin salir del teléfono. Los avisos BLE de las antenas también sirven para detectar el edificio y el piso, que es lo que hace `ModoAutomatico`, y para configurar las sesiones UWB, por lo que los Holy-IOT dejan de ser necesarios, aunque mientras haya menos antenas que beacons actuales conviene dejarlos como refuerzo del BLE.

### 3.2 Quién emite y quién calcula

En UWB los dos equipos emiten y reciben, por lo que la elección pasa por quién inicia la medición y quién calcula la posición. En la Tabla 2 se comparan los tres esquemas posibles.

Tabla 2. Esquemas de medición con UWB.

| Esquema | Quién emite | Quién calcula | Teléfonos | A favor | En contra |
|---|---|---|---|---|---|
| Ida y vuelta (TWR), el teléfono inicia | Los dos | El teléfono | Android 12 o superior con UWB | Funciona hoy y las antenas no necesitan estar sincronizadas | Configuración por BLE con cada antena y pocas personas a la vez por antena |
| DL-TDoA, las antenas emiten y el teléfono escucha | Las antenas | El teléfono | Android 17 o superior con UWB | Sin límite de personas y el teléfono no emite | Antenas sincronizadas al nanosegundo, firmware más complejo y pocos teléfonos |
| UL-TDoA, el teléfono emite y las antenas escuchan | El teléfono | Un servidor | No aparece en la API pública | Usado en fábricas | La posición sale del teléfono y hacen falta red y servidor |

Se eligió la medición de ida y vuelta, con el teléfono como el que inicia (controller en FiRa) y las antenas como las que responden (controlee), debido a que es lo único que funciona hoy en los teléfonos de prueba y mantiene el cálculo en el teléfono. DL-TDoA queda como opción a largo plazo, teniendo en cuenta que devuelve diferencias de tiempo en lugar de distancias, por lo que el `Posicionador` necesitaría otro tipo de residuo.

### 3.3 Qué cambia en la app

Gran parte de la app queda igual, debido a que la arquitectura actual ya trabaja con distancias. En la Tabla 3 se resume qué pasa con cada pieza.

Tabla 3. Cambios en la app según la fuente de las distancias.

| Pieza | Con UWB | Con BLE |
|---|---|---|
| `BluetoothHelper` | Busca las antenas y configura las sesiones | Igual que hoy |
| `ProcesadorSenal` y modelo log-distancia | No se usan, la distancia viene medida | Igual que hoy |
| `ajustarModelosRango` (n, tx) | Se reemplaza por un desfase fijo por antena, si hace falta | Igual que hoy |
| `Posicionador` | Igual | Igual, o reemplazado por el filtro de partículas (sección 6.2) |
| `PuertaRumbo`, `FiltroUnEuroPosicion`, `HisteresisCelda` | Más suaves o apagados (perfil UWB) | Igual que hoy (perfil BLE) |
| `RestriccionZonas` | Igual | Igual |
| Puntos clave | No hacen falta | Igual que hoy |
| A*, `SeguidorRuta`, voz, `OrientadorLlegada` | Sin cambios | Sin cambios |
| `MainActivity.kt` | Medición UWB con la biblioteca Jetpack | Sin cambios |
| App del admin | Antenas con su identificador UWB y su altura | Igual que hoy |

### 3.4 El dispositivo prestado como opción futura

Si más adelante se quiere que los teléfonos sin UWB tengan la misma precisión, se puede agregar el dispositivo de la sección 2.3 usando el mismo módulo DWM3001C con una batería, ya que trae el BLE para hablar con el teléfono, un acelerómetro para dormir cuando la persona está quieta y NFC, que podría servir para vincularlo apoyando el teléfono. Conviene llevarlo colgado del pecho o en un clip en el hombro antes que en la muñeca, porque con el brazo al costado el torso tapa la mitad de las antenas y la otra mano lleva el bastón, y que mida las distancias y se las mande al teléfono, que calcula con el `Posicionador` como en los otros casos.

## 4. Hardware

### 4.1 Módulo DWM3001C

Según su hoja de datos (revisión F, octubre de 2025), el DWM3001C junta en un solo módulo el transceptor UWB DW3110, el microcontrolador Nordic nRF52833 con BLE, el acelerómetro LIS2DH12, un convertidor DCDC y la antena UWB, con las características de la Tabla 4.

Tabla 4. Características del DWM3001C que importan para BlindRoute.

| Característica | Valor | Para qué sirve |
|---|---|---|
| Normas | IEEE 802.15.4z, FiRa en capa física y MAC | Medir contra los teléfonos Android |
| Canales | 5 (6,5 GHz) y 9 (8 GHz), 500 MHz de ancho | Los mismos que usan los teléfonos |
| Esquemas | Ida y vuelta y TDoA | Los dos primeros de la Tabla 2 |
| Microcontrolador | nRF52833, Cortex-M4 a 64 MHz, con BLE, USB y NFC | Avisos iBeacon, configuración de sesiones y actualizaciones |
| Calibración de fábrica | Cristal (menos de 2 ppm), potencia y retardo de la antena, guardados en la OTP | No hace falta calibrar para empezar |
| Antena | Monopolo impreso con polarización vertical, 2,5 dBi en el canal 5 y 2,0 dBi en el 9 | Condiciona el montaje (sección 4.3) |
| Alimentación | 2,5 a 3,6 V | No se conecta directo a 5 V |
| Consumo | 850 nA dormido, unos 40 a 45 mA transmitiendo | Las antenas van enchufadas |
| Encapsulado | 48 contactos laterales para soldar, 27,1 × 19,13 mm | Necesita una placa portadora |
| Certificaciones | FCC, ISED y ETSI, sólo para ciertas configuraciones de radio | No menciona a ENACOM |

En las muestras de ingeniería, que llevan "E1.0" en el código (como DWM3001CDKE1.0), la hoja indica no usar el retardo de antena del canal 5 guardado en la OTP y usar en su lugar el valor fijo 16390, cosa que se resuelve en el firmware si llega una de esas placas.

### 4.2 Por qué se compra el kit

El módulo suelto necesita una placa con un regulador de 3,3 V, los contactos soldados y un programador SWD aparte, por lo que para las pruebas se va a comprar el kit DWM3001CDK, que trae el módulo montado, un J-Link incorporado para programarlo y leer el puerto serie por USB, y dos puertos micro USB. La hoja de datos indica para el kit un mínimo de 20 unidades, pero esa condición corresponde a la compra directa a Qorvo, mientras que distribuidores como RFMW lo venden por unidad (US$ 29,50 de 1 a 24 unidades al momento de la consulta). Por la aduana se pueden traer 3 kits por envío, cantidad que alcanza para las etapas 1 a 3 del plan, y los siguientes se compran en otra tanda.

### 4.3 Montaje de las antenas

La antena del módulo tiene polarización vertical y está pensada para ir parada, y si dos antenas quedan perpendiculares aparecen ángulos en los que casi no se reciben, provocando errores en la distancia. Por esto mismo las antenas fijas tienen que ir todas paradas y con la misma orientación, ya sea arriba en la pared o colgando verticales del techo, mientras que la orientación del teléfono no se puede controlar y se mide su efecto en la etapa 1. La hoja de datos pide además 10 mm sin metal alrededor de la antena, lo que descarta montarlas sobre perfiles metálicos o dentro de cajas de metal, y advierte que en lugares con muchos rebotes, como los pasillos angostos, la medición puede variar más, por lo que las primeras pruebas incluyen un pasillo, que es donde más guía BlindRoute.

### 4.4 Lista de compras

En la Tabla 5 se detalla lo necesario para las etapas 1 a 3.

Tabla 5. Lista de compras para las primeras pruebas.

| Elemento | Cantidad | Para qué |
|---|---|---|
| Kit Qorvo DWM3001CDK | 3 | Antenas |
| Cables micro USB que pasen datos | 3 | Programar y leer el puerto serie (los cables que sólo cargan no sirven) |
| Cargadores USB de pared de 5 V, con alargues | 3 | Alimentar las antenas lejos de la computadora, ya que muchos power banks se apagan solos cuando el consumo es bajo |
| Trípodes de cámara o cinta doble faz | 3 | Subir las antenas a unos 2,5 m |
| Cinta métrica de 20 m o medidor láser | 1 | Distancia real en cada prueba y posición de cada antena |

Antes de pagar conviene revisar el stock, que se venda por unidad, el costo del envío a Argentina y que no sea una muestra de ingeniería E1.0. Las baterías, la caja y una placa propia no hacen falta hasta que el sistema funcione.

## 5. Incógnitas

Varias partes de la arquitectura todavía no están confirmadas y dependen de pruebas, la mayoría con las placas. En la Tabla 6 se resume cada una, cómo se confirma y qué se hace si sale mal.

Tabla 6. Incógnitas abiertas.

| Incógnita | Estado | Cómo se confirma | Si sale mal |
|---|---|---|---|
| ¿Android permite UWB en Argentina? | En principio sí, el Pixel muestra el ajuste habilitado | Diagnóstico de la etapa 0 | Queda sólo el dispositivo prestado |
| ¿Una app puede usar UWB en el Pixel? | Muy probable, el Pixel 9 Pro XL está en la lista de Google | Diagnóstico de la etapa 0 | Se pasa al dispositivo prestado |
| ¿Y en el S24 Ultra? | Sin confirmar, figura en la lista pero en el foro de Samsung nadie respondió si las apps de terceros pueden usarlo | Ajuste del teléfono y diagnóstico de la etapa 0 | Los Samsung usan BLE |
| ¿El Pixel mide contra una placa de Qorvo? | Probable, un proyecto de la comunidad lo hizo con un Pixel 8 Pro y un 9 Pro, aunque Qorvo no publica un ejemplo oficial para Android | Paso 1.1 | Se pasa al dispositivo prestado |
| ¿Una antena atiende a dos teléfonos a la vez? | Sin confirmar, en el foro de Qorvo hay respuestas contradictorias | Paso 1.4 | Protocolo propio y dispositivo prestado para todos |
| ¿Las sesiones FiRa son estables? | Hay reportes de sesiones que dejan de medir sin avisar con el SDK 1.1.1 | Pasos 1.2 y 3.2, dejando la medición varios minutos | Otra versión del SDK o un reinicio automático de la sesión |
| ¿Cuánto empeora en un pasillo? | Sin medir | Paso 1.2 | Se cambia la ubicación de las antenas y se ajusta el perfil UWB |
| ¿Se puede instalar en un local? | Sin datos de ENACOM | Consulta antes de instalar fuera del colegio | Queda como prototipo |

## 6. Filtros

### 6.1 Perfiles para BLE y para UWB

La cadena de filtros actual existe en gran parte para compensar el ruido del RSSI, por lo que con UWB varias etapas sobran o pueden ser mucho más suaves. Como cada parámetro del panel es un `ParametroAjuste` con su propia clave, alcanza con duplicar los que cambian con una clave aparte (por ejemplo `nav_filtro_caminando_hz_uwb`) y tomar en cada ciclo el valor del perfil que corresponda a la fuente, sin cambiar el panel, el guardado en el teléfono ni la subida a la nube. En la Tabla 7 se resume cómo queda cada etapa en los dos perfiles.

Tabla 7. Etapas del cálculo de la posición en cada perfil.

| Etapa | Perfil BLE | Perfil UWB |
|---|---|---|
| Distancias | RSSI y modelo log-distancia | Medidas por UWB |
| `Posicionador` (Huber) | Igual | Igual |
| Ancla a la posición anterior | Como hoy | Más débil |
| `PuertaRumbo` | Como hoy | Apagada o muy suave, porque el ruido lateral que la motivó no aparece con UWB |
| Puntos clave | Sí | No |
| One Euro | Como hoy | Suave |
| Tope de velocidad, zonas y paredes | Sí | Sí |
| Histéresis de celda | Como hoy | Menos ciclos |

Cuando la fuente cambia en medio de una caminata, por ejemplo al pasar al BLE en un rincón con pocas antenas a la vista, hay que reiniciar el estado de los filtros, igual que se hace hoy con `_puertaRumbo.resetear()`, para que la posición no dé un salto. Los valores del perfil UWB todavía no se conocen, así que se arranca con filtros suaves y se ajustan con los registros de la etapa 4.

### 6.2 Filtro de partículas para BLE

Para mejorar la precisión con BLE se va a probar un filtro de partículas como el de NavCog, que reparte varios cientos de partículas sobre el plano (se arranca con unas 500), cada una con una posible posición de la persona, y en cada paso las mueve según el largo del paso y el rumbo de la brújula, con algo de ruido para cubrir los errores de los dos. Las partículas que atraviesan una pared o entran en una zona no transitable se descartan, y cada lectura BLE les da más peso a las que están en lugares donde se esperaría oír lo que se oye, según el modelo de cada beacon y las calibraciones; después se vuelven a repartir, concentrándolas donde más pesan, y la posición es el promedio ponderado de todas.

Hoy esas tareas están repartidas entre el ancla, la puerta por rumbo, el One Euro, el tope de velocidad, la restricción de zonas y la histéresis, y el filtro las haría todas juntas, con las diferencias que se resumen en la Tabla 8.

Tabla 8. Comparación entre la cadena actual y el filtro de partículas.

| Aspecto | Cadena actual | Filtro de partículas |
|---|---|---|
| Pasos | Sólo deciden cuánto suavizar | Mueven la posición, que sigue avanzando si la señal se corta unos segundos |
| Paredes | Se aplican después del cálculo, sacando la posición de la zona | Forman parte del cálculo, descartando las hipótesis que las atraviesan |
| Ambigüedad | Elige un solo punto | Sostiene dos hipótesis (por ejemplo, dos pasillos paralelos) hasta que la señal desempate |
| Retraso | El One Euro suaviza a costa de atrasar la posición | Los pasos adelantan la posición sin esperar a la señal |

Se espera que la mejora se note sobre todo en los pasillos, en los giros y cuando la señal se corta, donde el plano y los pasos aportan mucha información, y bastante menos en una sala grande y abierta, donde no hay paredes que descarten hipótesis y todo depende de los pasos y de la señal. El error del RSSI sigue estando, ya que el filtro lo aprovecha mejor pero no lo corrige, y el 1,6 m de NavCog se logró con un beacon cada 6 m y un relevamiento de la señal en toda el área, por lo que en BlindRoute el resultado va a depender de la densidad de las antenas y del trabajo de calibración de cada edificio.

La app ya tiene buena parte de lo que necesita el filtro, como las calibraciones, que funcionan como relevamiento de la señal, la brújula con su medida de calidad y las zonas y paredes de `GrillaNav`, pero falta un detector de pasos, debido a que `DetectorMovimiento` entrega un factor continuo entre quieto y caminando y no cuenta los pasos ni estima su largo. El conteo de pasos funciona mejor con el teléfono en la mano que en el bolsillo, y el filtro agrega sus propios parámetros (cantidad de partículas, largo del paso y ruido del rumbo), por lo que se desarrolla por partes y la cadena actual queda disponible con un interruptor en la sección Pruebas del panel, para comparar las dos en el mismo recorrido. Calcular 500 partículas a 5,5 ciclos por segundo es poco trabajo para el teléfono, y como el filtro no depende de las placas, se puede desarrollar en paralelo con las etapas de UWB.

## 7. Plan de trabajo

### 7.1 Forma de trabajar

Todo el trabajo se hace en una rama nueva, `uwb`, creada desde `estética`, de forma que el sistema BLE actual siga funcionando en `estética` y en `main` y cualquier demostración quede a salvo hasta que el UWB ande mejor. Cada paso del plan tiene un objetivo, que es la pregunta que responde, una forma de probarlo, lo que se anota y lo que se decide según el resultado, y el paso siguiente arranca recién cuando el anterior dio una respuesta. El firmware de las placas se compila en la computadora y se carga con el J-Link del kit, y los mensajes del puerto serie se pueden leer desde PowerShell igual que con el auricular, aunque todo lo que pasa entre las placas y el teléfono sólo se puede comprobar con el hardware, por lo que en cada paso se distingue lo que está probado de lo que no.

Los resultados y las decisiones de cada paso se anotan en la sección 8, para que la arquitectura quede escrita a medida que se define.

### 7.2 Etapa 0: preparación, sin placas

Esta etapa se hace mientras llegan los kits y responde lo que se puede saber sin ellos.

En el paso 0.1 se revisa el ajuste de UWB en el S24 Ultra (Ajustes, Conexiones, Banda ultraancha), como ya se hizo con el Pixel, que lo muestra habilitado. En el paso 0.2 se agrega a la app del admin un diagnóstico de UWB que le pregunta a Android si el teléfono tiene UWB (`android.hardware.uwb`), si está activado y si la biblioteca Jetpack deja usarlo, y se prueba en el Pixel y en el S24, de forma que si alguno de los dos no puede usarlo se sepa antes de medir.

En el paso 0.3 se mide el error de la cadena actual en un recorrido conocido, que sirve como línea de base para comparar todo lo que viene después. Para esto se marcan en el piso entre 8 y 10 puntos de control sobre un recorrido que incluya un pasillo, un giro y una sala, se ubican esos mismos puntos en el plano y se recorre el camino deteniéndose 10 s en cada uno. Para no anotar a mano conviene agregar a la sección Pruebas del panel un botón que, al tocarlo parado sobre un punto, guarde la posición estimada junto con la real, y con esos datos se calculan el error medio y el error que no se supera en el 90 % de los casos, completando la Tabla 9. El mismo recorrido se repite después con UWB y con el filtro de partículas.

Tabla 9. Registro de la medición en los puntos de control.

| Punto | Lugar (sala, pasillo, giro) | Posición real (m) | Posición estimada (m) | Error (m) | Fuente y filtros |
|---|---|---|---|---|---|
| 1 | | | | | |

En el paso 0.4 se separa en la app la fuente de las distancias, de forma que el `Posicionador` las reciba sin saber si vienen del RSSI o de UWB, y se agrega una fuente simulada con sus tests, sin cambiar cómo funciona hoy con BLE. En el paso 0.5 se baja el SDK de Qorvo (DW3_QM33 SDK) desde su página, aceptando su licencia, se instala el software de SEGGER para el J-Link y se crea la rama `uwb`, y en el paso 0.6 se compran los kits según la Tabla 5.

### 7.3 Etapa 1: una antena, confirmar que UWB funciona

En el paso 1.1 se carga en una placa el firmware FiRa de Qorvo y se prueba la medición desde el Pixel, partiendo del proyecto de la comunidad que lo logró con un Pixel 8 Pro y un 9 Pro. Si después de revisar la configuración (canal, direcciones y clave de la sesión) el teléfono no logra medir contra la placa, la variante con los teléfonos se cae y se pasa al dispositivo prestado.

En el paso 1.2 se mide la precisión de la distancia con la placa a la altura del teléfono (1,1 m), para que la distancia real sea la que marca la cinta, parándose a 1, 2, 4, 8 y 12 m durante 30 s en cada distancia, con el cuerpo de frente, de costado y de espaldas a la placa y con el teléfono en la mano y en el bolsillo, primero en una sala y después en un pasillo, y completando la Tabla 10. Como referencia propia, no medida, se espera un error menor a 30 cm con línea de vista y menor a 1 m con el cuerpo en el medio, y si los valores quedan muy por encima se revisa el retardo de la antena antes de seguir.

Tabla 10. Registro de la precisión de la distancia.

| Distancia real (m) | Lugar | Cuerpo | Teléfono | Distancia medida, promedio (m) | Desvío (m) | Cortes en 30 s |
|---|---|---|---|---|---|---|
| 1 | Sala | De frente | En la mano | | | |

En el paso 1.3 se repite una parte del paso 1.2 con el S24 (por ejemplo 2 y 8 m, de frente y de espaldas) para saber si los Samsung también sirven, y en el paso 1.4 se comprueba si una antena atiende a dos teléfonos a la vez, con el Pixel y el S24 midiendo contra la misma placa, o con el Pixel y otra placa haciendo de segundo teléfono, dejando las dos sesiones abiertas varios minutos.

Con los pasos 1.1 y 1.4 se toma la primera decisión del plan. Si el teléfono mide contra la placa y la antena atiende a dos a la vez, se sigue con FiRa y con los teléfonos midiendo directo, y si alguna de las dos cosas falla, se pasa a un protocolo propio entre las placas y al dispositivo prestado para todos, en cuyo caso las etapas siguientes se adaptan a esa variante.

### 7.4 Etapa 2: una antena en la app

En el paso 2.1 se escribe en `MainActivity.kt` la medición UWB con la biblioteca Jetpack, que funciona desde Android 12, conectada a la app por un canal como el que ya usa el reconocimiento de voz, y en el firmware de la placa un servicio BLE para intercambiar la configuración de la sesión con el teléfono, además del aviso iBeacon. En esta etapa también conviene dejar preparada la actualización del firmware por BLE, para no tener que bajar las antenas cada vez que cambia. En el paso 2.2 se muestra la distancia medida en la sección Pruebas del panel y se repiten algunos puntos del paso 1.2, para confirmar que la app mide lo mismo que la prueba anterior.

### 7.5 Etapa 3: tres antenas en un aula

En el paso 3.1 se colocan las tres placas paradas, a unos 2,5 m de altura, formando un triángulo alrededor del área de prueba, ya que con las tres en línea la posición queda ambigua a los dos lados de esa línea, y se mide su posición con la cinta o el láser para cargarlas en el admin con su identificador UWB y su altura. En el paso 3.2 se comprueba que el teléfono mida contra las tres a la vez, dejando la medición varios minutos para ver si alguna sesión se corta.

En el paso 3.3 las distancias pasan al `Posicionador` con filtros suaves y se repite la medición de los puntos de control de la etapa 0 que quedan dentro del aula, comparando el error con el de la línea de base. Con tres antenas la posición en 2D queda justa, de modo que si el cuerpo tapa una de ellas la posición queda ambigua, cosa que el ancla del `Posicionador` compensa sólo en parte, por lo que también se anota en qué puntos pasa. En el paso 3.4 se prueba con un teléfono sin UWB que la app detecte los avisos iBeacon de las placas con el código actual, y se mide el error de ese respaldo en los mismos puntos.

Con estos resultados se toma la segunda decisión: si el error con UWB queda claramente por debajo de la línea de base, se compran 3 kits más para la etapa 6.

### 7.6 Etapa 4: división de los filtros

En el paso 4.1 se agregan a `AjustesNavegacion` los parámetros del perfil UWB, la elección del perfil según la fuente y el reinicio de los filtros al cambiar de fuente, y el panel pasa a mostrar qué perfil está activo. En el paso 4.2 se ajusta el perfil UWB con los registros, empezando por los valores más suaves y endureciendo sólo los que hagan falta, de a un parámetro por vez como en `AJUSTES_EN_EL_EDIFICIO.md`.

### 7.7 Etapa 5: filtro de partículas para BLE

Esta etapa no depende de las placas, por lo que se puede hacer en paralelo con las etapas 1 a 4. En el paso 5.1 se agrega un detector de pasos a partir del acelerómetro, con una estimación del largo de cada paso, y se compara en el teléfono con los pasos contados a mano en varios recorridos, con el teléfono en la mano y en el bolsillo. En el paso 5.2 se programa el filtro con el modelo de movimiento, las paredes de `GrillaNav` y el modelo de cada beacon, y se prueba en la computadora con recorridos simulados y sus tests. En el paso 5.3 se agrega el interruptor en la sección Pruebas y se recorre el mismo camino de la etapa 0 con la cadena actual y con el filtro, comparando los errores, y en el paso 5.4 se decide, según ese resultado, cuál de los dos queda por defecto en el perfil BLE.

### 7.8 Etapa 6: recorrido real

Con 3 kits más, del segundo envío, se arma un recorrido con un pasillo y varias salas, con al menos 4 antenas a la vista desde cada punto donde sea posible, y se prueban el efecto de los pasillos, dos personas navegando a la vez, la detección del piso con los avisos BLE de las antenas y el paso del UWB al BLE en los lugares con pocas antenas. Si todo funciona, los Holy-IOT quedan sólo como refuerzo del BLE o se retiran.

### 7.9 Etapa 7: más adelante

Después de las etapas anteriores quedan el dispositivo prestado para los teléfonos sin UWB (sección 3.4), el paso a DL-TDoA si hace falta atender a muchas personas a la vez, que pide Android 17 y antenas sincronizadas, y una nueva revisión de Channel Sounding cuando lo soporten más teléfonos.

### 7.10 Resumen

En la Tabla 11 se resumen las etapas, la pregunta que responde cada una y lo que necesita.

Tabla 11. Resumen del plan de trabajo.

| Etapa | Qué responde | Placas | Depende de |
|---|---|---|---|
| 0. Preparación | Si los teléfonos pueden usar UWB y cuánto erra hoy el BLE | Ninguna | Nada |
| 1. Una antena | Si UWB funciona con los teléfonos, con qué error, y si una antena atiende a dos | 1 a 3 | Etapa 0 |
| 2. Una antena en la app | Si la app mide igual que la prueba | 1 | Etapa 1 |
| 3. Tres antenas | Cuánto mejora la posición comparado con la línea de base | 3 | Etapa 2 |
| 4. División de los filtros | Qué valores lleva el perfil UWB | 3 | Etapa 3 |
| 5. Filtro de partículas | Si mejora el BLE comparado con la cadena actual | Ninguna | Línea de base de la etapa 0 |
| 6. Recorrido real | Si el sistema funciona en un recorrido completo | 6 o más | Etapas 3 y 4 |
| 7. Más adelante | Dispositivo prestado, DL-TDoA y Channel Sounding | Según la opción | Etapa 6 |

## 8. Registro de resultados

En la Tabla 12 se anotan, a medida que se hacen, los resultados de cada paso y lo que se decidió a partir de ellos.

Tabla 12. Resultados y decisiones de cada paso.

| Fecha | Paso | Resultado | Decisión |
|---|---|---|---|
| 26/11/2026 | 0.1, ajuste de UWB en el Pixel 9 Pro XL | Aparece habilitado | Se sigue con la variante de los teléfonos |

## 9. Fuentes

- Hoja de datos del Qorvo DWM3001C, revisión F, octubre de 2025, y páginas del [DWM3001C](https://qorvo.com/products/p/DWM3001C) y del [DWM3001CDK](https://www.qorvo.com/products/p/DWM3001CDK).
- [Precio del DWM3001CDK en RFMW](https://rfmw.com/products/detail/dwm3001cdk-qorvo/692466/).
- Android: [comunicación UWB](https://developer.android.com/develop/connectivity/uwb), [módulo Ranging](https://developer.android.com/develop/connectivity/ranging) y [versiones de androidx.core.uwb](https://developer.android.com/jetpack/androidx/releases/core-uwb).
- [Proyecto sasodoma/uwb-ranging](https://github.com/sasodoma/uwb-ranging), medición entre el DWM3001CDK y teléfonos Pixel.
- Foro de Qorvo: [interacción cercana en Android](https://forum.qorvo.com/t/qorvo-nearby-interactions-for-android/25886), [varias sesiones FiRa](https://forum.qorvo.com/t/does-dw3-qm33-sdks-qani-project-support-multiple-fira-sessions/24451), [FiRa de uno a muchos](https://forum.qorvo.com/t/tutorial-how-to-use-dw3-qm33-sdk-for-one-to-many-fira-ranging/21232), [sesiones que dejan de medir](https://forum.qorvo.com/t/fira-controller-session-stops-producing-ranging-rounds-silently-dw3-qm33-sdk-1-1-1-dwm3001cdk/25999) y [código de TDoA](https://forum.qorvo.com/t/dwm3001cdk-availability-of-tdoa-example-reference-code-qm33-sdk-1-1-1/26096).
- [Foro de Samsung sobre UWB en el Galaxy S24+](https://forum.developer.samsung.com/t/uwb-development-on-galaxy-s24/35798).
- [Resumen de Bluetooth Core 6.0](https://www.bluetooth.com/core-specification-6-feature-overview/).
- Foro de Nordic: [Channel Sounding en varias conexiones](https://devzone.nordicsemi.com/f/nordic-q-a/121934/concurrent-channel-sounding-procedures/539147), [varios reflectores](https://devzone.nordicsemi.com/f/nordic-q-a/118844/nrf54l15-multipoint-channel-sounding-cannot-initiate-more-then-1-reflector) y [teléfonos compatibles](https://devzone.nordicsemi.com/f/nordic-q-a/127111/ble-channel-sounding-with-nrf54l15-which-smartphones-are-actually-supported).
- [Channel Sounding sin conexión con PAwR (arXiv 2605.17094)](https://arxiv.org/abs/2605.17094).
- [Tesis de la Universidad de Lund sobre Bluetooth 6.0](https://lup.lub.lu.se/student-papers/record/9236897/file/9236918.pdf).
- NavCog: [Ahmetovic y otros, 2017](https://www.ri.cmu.edu/publications/achieving-practical-and-accurate-indoor-navigation-for-people-with-visual-impairments) y [estudio de campo de NavCog3](https://par.nsf.gov/servlets/purl/10065143).
