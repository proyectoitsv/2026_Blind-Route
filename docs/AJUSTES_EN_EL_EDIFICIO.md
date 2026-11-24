# Ajuste de los parámetros en el edificio

Varios de los valores que usa la navegación para calcular la posición se eligieron con simulaciones en la computadora, con cuentas o tomando valores típicos, ya que hasta ahora no se pudo medir cada uno en un edificio real, por lo que en la práctica pueden necesitar otro valor. En este documento se explica, para cada parámetro que conviene revisar, qué hace, dónde se cambia, qué se tiene que medir y cómo se decide el valor a partir de lo medido.

Algunos datos ya se midieron y quedaron cargados: los beacons emiten cada 160 ms (se puede cambiar desde la app del fabricante), la señal configurada a 1 m es de −55 dBm, que coincide con el valor por defecto de la app, y el teléfono se lleva a unos 1,1 m del piso, que pasó a ser el valor de `alturaTelefonoM` en `lib/procesador_senal.dart`.

## 1. Antes de empezar

### 1.1 Dónde se cambia cada valor

Los parámetros se cambian en dos lugares distintos. Los del panel de ajustes, que se abre desde la navegación en la app del administrador, rigen apenas se suelta el deslizador, se guardan en el teléfono y se suben a la nube, y como viajan con el mapa publicado, la app del usuario navega ese edificio con los mismos valores; cada uno se puede cambiar sólo para el edificio actual o para todos los edificios. Los valores fijos en el código, en cambio, quedan adentro de la app, por lo que después de cambiarlos hay que volver a instalar las dos apps:

```bash
flutter run --flavor admin -t lib/main_admin.dart
flutter run --flavor user -t lib/main_user.dart
```

### 1.2 Cómo ver lo que mide la app

Con el teléfono conectado por USB, el primero de los dos comandos instala la app del administrador y muestra en la terminal el log, que son los mensajes que la app escribe mientras funciona. El log no cambia nada y sólo sirve para mirar los números, por lo que las calibraciones, el panel y la navegación funcionan igual sin el cable. En la Tabla 1 se resumen las líneas del log que se usan en este documento.

Tabla 1. Líneas del log que se usan para ajustar los parámetros.

| Línea | Cuándo aparece | Qué muestra |
|---|---|---|
| `[Rango] MAC: n=… tx=…` | Una vez, al abrir la navegación | El n y el RSSI a 1 m que se ajustaron para cada beacon con las calibraciones |
| `[Rango] MAC: n ajustado fuera de rango` | Una vez, al abrir la navegación | Un beacon cuyo ajuste se descartó y que usa el modelo por defecto |
| `[Rumbo] activo=… calidad=… (R=…) … mov=… puerta(apertura=…)` | Cada 2 s, navegando | Si la brújula está frenando el movimiento de costado, su calidad, el factor de movimiento (0 quieto, 1 caminando) y la apertura de la puerta lateral |
| `[Fingerprint] …` | Cada 2 s, si el piso tiene puntos clave | Los dB de cada punto clave, o por qué quedó afuera |
| `[Señal] … lecturas/s por beacon` | Cada 5 s, navegando | Cuántas lecturas por segundo llegan de cada beacon |

Sin el cable se pueden ver las lecturas por segundo en el panel, el estado "quieto", "en movimiento" o "ajustando" y la cantidad de beacons en la pantalla de navegación, y el RSSI de cada beacon en la configuración del piso.

### 1.3 Forma de trabajar

Primero que todo hay que revisar los datos del edificio, ya que todo lo demás depende de ellos: la altura de cada beacon medida con cinta desde el piso, la posición de cada beacon en el plano (un metro de error en el plano se convierte en un metro de error en la posición), la escala del plano medida sobre dos paredes largas y el norte del plano, tomado con "Usar la dirección actual" lejos de columnas de metal. Una vez cargados, conviene calibrar cada beacon en al menos tres celdas a distancias distintas, porque varios de los ajustes de las secciones siguientes se apoyan en esas calibraciones.

Los parámetros se ajustan de a uno y en el orden de las secciones, debido a que varios se cruzan entre sí (por ejemplo, el ancla y el filtro del panel actúan sobre lo mismo) y cambiando dos a la vez no se sabe cuál produjo el resultado. Para no perder lo probado sirve anotar cada prueba en una tabla con las columnas de la Tabla 2, completando una fila por cada cambio.

Tabla 2. Columnas del registro de pruebas.

| Fecha | Edificio | Parámetro | Valor anterior → nuevo | Prueba | Resultado |
|---|---|---|---|---|---|
| | | | | | |

## 2. Límites de n

Cuando se abre la navegación, la app ajusta para cada beacon una recta entre el RSSI y el logaritmo de la distancia con todas sus calibraciones, y de esa recta salen el n y el RSSI a 1 m. Si el n que sale queda fuera de los límites `_nMin` (1,5) y `_nMax` (4,5), definidos en `lib/procesador_senal.dart`, el ajuste se descarta y ese beacon usa el modelo por defecto (n = 2,7), debido a que un n así suele salir de calibraciones con ruido o de un beacon mal ubicado en el plano. Los límites se eligieron sin medir y quedan en el código, porque funcionan como un control de seguridad que se revisa una vez y no como un ajuste de gusto.

Para revisarlos se siguen estos pasos:

1. Calibrar cada beacon en al menos tres celdas, una a 1 o 2 m, otra a 4 o 5 m y otra a 8 o 10 m, con el teléfono en la mano a 1,1 m del piso.
2. Abrir la navegación con el teléfono conectado y anotar la línea `[Rango]` de cada beacon.

Si todos los n quedan entre 1,5 y 4,5, los límites no se tocan. Si un beacon bien ubicado, con la posición y la altura revisadas, da un n por debajo de 1,5, cosa que puede pasar en pasillos largos que guían la señal, se baja `_nMin` a 1,2, y si da más de 4,5, por ejemplo con paredes gruesas en el medio, se sube `_nMax` a 5. Cuando un solo beacon da un valor raro y los demás no, conviene revisar primero su posición en el plano y volver a calibrarlo, ya que un beacon corrido en el plano también deforma la recta. El `tx` de cada línea muestra el RSSI a 1 m que mide el teléfono, que puede quedar algunos dB por debajo o por encima de los −55 dBm configurados en el beacon, diferencia que el ajuste absorbe sin problema.

## 3. Ancla a la posición anterior

En cada ciclo la posición se calcula a partir de las distancias a los beacons, y además se suma un término que la tira hacia la posición del ciclo anterior, cuyo peso se expresa como un múltiplo del peso de todos los beacons juntos. Con el valor de fábrica de 3 parado, la posición anterior pesa el triple que todos los beacons, mientras que caminando baja a 0,25, y entre los dos se pasa de forma gradual según el factor de movimiento del acelerómetro. Los dos valores se eligieron sin medir y se cambian en el panel, en la sección "Seguimiento de la posición", con los deslizadores "Ancla, parado" y "Ancla, caminando", que se pueden ajustar por edificio porque dependen del ruido de la señal en cada lugar.

Para probarlos se hacen tres pruebas, con el filtro y las ventanas del panel en los valores que ya tengan:

1. Parado en una celda marcada, con el teléfono en la mano y la pantalla diciendo "quieto", contar cuántas veces cambia de celda el punto durante 60 s.
2. Parado en un lugar conocido, abrir la navegación y ver si después de la fase de ajuste (los primeros 6 s, en los que la pantalla dice "ajustando" y el ancla funciona como si se estuviera caminando) el punto queda en la celda correcta, y si queda corrido, cuánto tarda en volver.
3. Caminar 10 m en línea recta a paso normal, de una marca a otra, con otra persona tomando el tiempo que tarda el punto en arrancar después de que se arranca y en frenar después de que se frena.

Como referencia propia, no medida, se busca que parado el punto cambie de celda una vez como mucho y que caminando no vaya más de 2 s atrasado. En la Tabla 3 se resume qué cambiar según lo que se observa en las pruebas.

Tabla 3. Ajuste del ancla según lo observado.

| Lo que se observa | Qué cambiar |
|---|---|
| Parado, el punto tiembla o se desliza solo | Subir el ancla parado (3 → 4 o 5) |
| Parado, una posición corrida tarda mucho en corregirse | Bajar el ancla parado (3 → 2) |
| Caminando, el punto va atrasado | Bajar el ancla caminando (0,25 → 0,15) |
| Caminando, el punto avanza a saltos | Subir el ancla caminando (0,25 → 0,4) |

## 4. Calidad del rumbo

La calidad del rumbo dice cuánto se puede confiar en la brújula, y sale de las últimas 8 lecturas del heading, de las que se calcula la longitud R del promedio de los ángulos tomados como vectores unitarios, que vale 1 cuando todas las lecturas apuntan igual y baja a medida que se dispersan. Con R se calcula la calidad entre dos umbrales, `rMalo` (0,90) y `rBueno` (0,985), definidos en el getter `calidadRumbo` de `lib/orientacion_service.dart`:

```
calidad = (R − rMalo) / (rBueno − rMalo), limitada entre 0 y 1
```

Por ejemplo, con R = 0,96 queda calidad = (0,96 − 0,90) / (0,985 − 0,90) = 0,06 / 0,085 = 0,71. Los umbrales salieron de una cuenta que supone que con el teléfono en la mano el heading oscila entre ±10° y ±20° por el braceo y los pasos, y quedan en el código porque dependen de la brújula del teléfono y de cómo se lo lleva más que del edificio, así que se ajustan una vez por modelo de teléfono.

Para medirlos, con el teléfono conectado se anotan unos 10 valores de R (uno cada 2 s, unos 20 s) en cada una de estas situaciones:

1. Caminando recto 20 m por un pasillo sin metal cerca, con el teléfono como se lo lleva siempre.
2. Pasando al lado de un ascensor, una columna de metal o un tablero eléctrico.
3. Parado, mirando fijo hacia un lado, como referencia.

Con esos valores, `rBueno` se pone en el R típico de la primera situación y `rMalo` en el R típico de la segunda, de manera que caminando recto la calidad dé cerca de 1 y al lado del metal cerca de 0. Si las dos situaciones dan valores de R parecidos, la brújula del teléfono no llega a distinguirlas y conviene dejar los umbrales como están y resolver con la calidad mínima de la sección 5. Durante un giro R también baja, cosa que no molesta porque en ese momento la brújula no tiene que frenar nada.

## 5. Calidad mínima de la brújula

Cuando la calidad del rumbo supera la calidad mínima, la brújula pasa a frenar el movimiento de costado (sección 6), y cuando baja 0,2 por debajo de ese valor deja de hacerlo, diferencia que evita que entre y salga en cada ciclo cuando la calidad oscila cerca del umbral. Durante los primeros 6 s después de ubicarse la brújula no frena nada, ya que el error de la primera posición puede estar en cualquier dirección. El valor de fábrica es 0,35 (se apaga en 0,15), se eligió sin medir y se cambia en el panel, en la sección "Brújula", con el deslizador "Calidad mínima de la brújula", que se puede ajustar por edificio porque la cantidad de metal cambia de un edificio a otro.

La prueba es la misma caminata de la sección 4, con sus umbrales ya ajustados, mirando el campo `activo=` de la línea `[Rumbo]`, que tiene que dar `true` en casi todo el pasillo y `false` al lado del metal y al doblar. Si da `false` caminando recto en un lugar sin metal, se baja la calidad mínima (0,35 → 0,25), y si da `true` al lado del metal y el punto se traba de costado, se sube (0,35 → 0,5). Para comparar sirve el interruptor "Freno lateral por brújula" del panel, que apaga todo el frenado en la misma caminata: si con el interruptor apagado el punto acompaña mejor sin bambolearse más, la brújula está frenando movimiento real.

## 6. Paso de costado y hacia atrás

Caminando y con la brújula activa, el desplazamiento de cada ciclo se divide en lo que va hacia donde mira la persona y lo que va de costado, y mientras lo que va hacia adelante pasa entero, de costado pasa sólo el 3 % y hacia atrás el 15 %, debido a que el ruido de la señal mueve el punto para los dos lados mientras que una persona casi siempre camina hacia donde mira. El movimiento de costado pasa entero recién cuando es sostenido, o sea cuando va hacia el mismo lado durante 12 ciclos seguidos (unos 2,2 s) y a más de 0,90 m/s en promedio, umbrales que se ajustaron en el campo y quedan en el código, mientras que con la persona quieta no se frena nada. Los porcentajes salieron de simulaciones y cuentas, y se cambian en el panel, en la sección "Brújula", con los deslizadores "Paso de costado" y "Paso hacia atrás", que se pueden ajustar por edificio.

Antes de probarlos tienen que estar bien el norte del plano y la sección 5, porque con la brújula desviada el frenado retiene movimiento real, y una vez revisado eso se hacen estas pruebas:

1. Caminar recto 20 m por el medio de un pasillo y ver si el punto se queda en su fila de celdas o se corre una como mucho.
2. Caminando, correrse 2 m hacia la otra pared y seguir derecho, tomando el tiempo que tarda el punto en pasarse (en el log, `puerta(apertura=…)` sube hacia 1 cuando la puerta se abre).
3. Caminar 3 m de espaldas, mirando hacia adelante, y ver si el punto acompaña.

Se toma como referencia, también sin medir, que el corrimiento de la segunda prueba se vea en 3 s como mucho y el retroceso de la tercera en unos 4 s. En la Tabla 4 se resume qué cambiar según lo observado.

Tabla 4. Ajuste del paso de costado y hacia atrás según lo observado.

| Lo que se observa | Qué cambiar |
|---|---|
| Caminando recto, el punto se bambolea de costado | Bajar el paso de costado (3 % → 2 %) |
| Un corrimiento real tarda mucho en verse | Subir el paso de costado (3 % → 6 a 10 %) |
| Caminando de espaldas, el punto no acompaña | Subir el paso hacia atrás (15 % → 25 %) |

## 7. Coincidencia perfecta

Cada vez que se compara la lectura en vivo con un punto clave sale una diferencia en dB entre los dos patrones, y con esa diferencia se calcula la confianza, que decide cuánto se corre la posición hacia el punto. Por debajo de la coincidencia perfecta la confianza es total, por encima de la coincidencia mínima es nula, y entre las dos baja en línea recta:

```
confianza = (mínima − dB) / (mínima − perfecta), limitada entre 0 y 1
```

Con los valores de fábrica, 4 dB de perfecta y 10 dB de mínima, una diferencia de 7 dB da confianza = (10 − 7) / (10 − 4) = 0,5. Los dos valores salieron de una simulación con 5 dB de variación por beacon y se cambian en el panel, en la sección "Puntos clave", con los deslizadores "Coincidencia perfecta" y "Coincidencia mínima", que se pueden ajustar por edificio. Si la perfecta queda por encima de la mínima, la app la baja a medio dB de la mínima.

Para medirlos se usa la línea `[Fingerprint]` del log:

1. Parado en el punto clave, mirando hacia el mismo lado que cuando se tomó, anotar durante 30 s los dB de ese punto (unos 15 valores): el típico y el más alto.
2. Parado a 2 m del punto, del lado por el que se llega caminando, anotar los dB otra vez.

La coincidencia perfecta se pone en el valor típico estando en el punto, y la mínima entre el valor más alto estando en el punto y el típico a 2 m, de manera que en el punto la confianza quede alta y a 2 m baje a cero. Si los valores en el punto y a 2 m se pisan, el punto no se distingue de su alrededor con la señal que hay, y conviene volver a tomarlo o sumar un beacon cerca antes de seguir moviendo los umbrales.

## 8. Otros valores fijos en el código

Aparte de los seis parámetros anteriores, hay otros valores que se eligieron sin medir y que sólo hace falta revisar si aparece el problema de la última columna de la Tabla 5. Todos se cambian en el archivo indicado y obligan a volver a instalar las dos apps.

Tabla 5. Otros valores del código elegidos sin medir.

| Valor | Archivo | Valor actual | Cuándo cambiarlo |
|---|---|---|---|
| RSSI a 1 m por defecto (`_txPower`) | `lib/procesador_senal.dart` | −55 dBm | Sólo rige para un beacon sin ninguna calibración; conviene calibrar en vez de tocarlo |
| n por defecto (`_pathLossExponent`) | `lib/procesador_senal.dart` | 2,7 | Si los n de `[Rango]` del edificio rondan otro valor, para los beacons con menos de 3 calibraciones |
| Umbral para usar un beacon (`_umbralRSSI`) | `lib/pantalla_naveg.dart` | −90 dBm | Si en los bordes quedan menos de 3 beacons donde se oyen más, bajar a −93; si los lejanos tiran la posición, subir a −85 |
| Caída de un beacon que no se oye | `lib/pantalla_naveg.dart` | 8 dB/s, después de 1 s | Si el panel muestra 1 lectura por segundo o menos, subir la espera a 2 o 3 s |
| Velocidad máxima parado (`_velMaxQuietoMs`) | `lib/pantalla_naveg.dart` | 1,2 m/s | Si parado el punto da saltos, bajarla |
| Zona muerta parado | `lib/pantalla_naveg.dart` | 0,35 m | Si parado el punto salta de celda, subir a 0,5; si tarda en corregir un error real, bajarla |
| Fase de ajuste al arrancar | `lib/pantalla_naveg.dart` | 3 s + 3 s | Si "Ubicación lista" sale con la posición todavía mal, alargarla |
| Primera posición | `lib/pantalla_naveg.dart` | Espera 3 beacons, hasta 1,5 s | Si arranca mal ubicado, subir la espera a 3 s |
| Celda firme del otro lado de una pared | `lib/pantalla_naveg.dart` | 5 ciclos caminando, 11 parado | Si caminando junto a una pared fina el punto salta al otro lado, subirlos |
| Penalización por cambiar de lado | `lib/restriccion_zonas.dart` | 1,5 m | Lo mismo que la fila anterior |
| Ventana de la brújula | `lib/orientacion_service.dart` | 8 lecturas | Si el rumbo tiembla parado, subirla |
| Espera para "quieto" | `lib/detector_movimiento.dart` | 0,8 s | Si al frenar el punto sigue de largo, bajarla |
| Tolerancias al llegar | `lib/orientador_llegada.dart` | De frente 30°, un poco 60°, date la vuelta 150° | Si al llegar la guía no deja de frente a la entrada |
| "Sobre la ruta" | `lib/seguidor_ruta.dart`, `lib/pantalla_naveg.dart` | 0,75 m; recalcula a los 1,5 s fuera o enseguida con 3 m | Si caminando bien por el camino recalcula seguido, subir 0,75 a 1 o 1,5 |
| Cambiar a otro camino | `lib/seguidor_ruta.dart` | Si ahorra 3 m o más | Si la ruta salta entre dos caminos parecidos, subirlo |
| Maniobras repetidas | `lib/pantalla_naveg.dart` | No repetir en 12 s; misma esquina a 2,5 m | Si repite "Girá" en la misma esquina, subirlos |
| Salida de la escalera | `lib/pantalla_naveg.dart` | 2,5 m | Si después de cambiar de piso la ruta arranca para atrás, subirlo |
| Costos del A\* | `lib/pathfinder.dart` | Giro 4, borde 2, zona 0,6 | Si las rutas dan vueltas raras o pasan rozando las paredes |
| Ventaja de un punto clave sobre otra celda (`_fpMargenDb`) | `lib/procesador_senal.dart` | 2 dB | Si dos puntos clave cercanos se confunden, subir a 3 |
| Ventaja para elegir el piso | `lib/modo_automatico.dart` | 4 dB, con 3 beacons por piso | Si al abrir la app elige el piso de arriba o el de abajo, subir a 6 u 8 dB |
| Escucha antes de elegir el piso | `lib/modo_automatico.dart` | 3 s (hasta 6 s) | Si elige mal al arrancar, subir a 5 s |
| Filtro de las indicaciones | `lib/voz_service.dart` | 4 confirmaciones y 1,8 s | Si las indicaciones llegan tarde después de doblar, bajar a 1,2 s; si se contradicen, subirlo |

Los parámetros del firmware del auricular están explicados en `hardware/esp32_blindroute_audio/COMO_FUNCIONA.md`, el colchón de la música, la ganancia y el ecualizador en la sección 4.1 y la reconexión en la sección 2, con la aclaración de que el firmware 2.1 todavía no se compiló ni se probó.

## 9. Valores ya medidos

Los valores de la Tabla 6 sí se midieron o se probaron en la realidad, así que no conviene cambiarlos sin una prueba que lo justifique, aunque cabe aclarar que se midieron en un solo lugar y con un solo teléfono, por lo que en otro edificio conviene confirmarlos.

Tabla 6. Valores que se midieron o se probaron en la realidad.

| Valor | Archivo o lugar | Cómo se obtuvo |
|---|---|---|
| Umbral de "quieto" del acelerómetro (0,25 m/s²) y de caminata de la clase (0,80 m/s²) | `lib/detector_movimiento.dart` | Medido en el aula con el teléfono en la mano; el panel usa 0,6 para caminar |
| Apertura de la puerta lateral (0,90 m/s) y su tiempo (3,5 s) | `lib/posicionador.dart` | Ajustados en el campo, caminando en línea recta |
| Tolerancia de rumbo de los puntos clave (90°) | Panel, "Puntos clave" | Probada en el campo con 45°, que dejaba afuera el punto mirando hacia otro lado |
| Gracia de 4 ciclos de los puntos clave | `lib/pantalla_naveg.dart` | En una toma real, parado a 45 cm de un beacon, el RSSI crudo iba de −64 a −35 dBm |
| Radio de llegada (0,5 m) | `lib/pantalla_naveg.dart` | Elegido después de probar con 1,5 m, que anunciaba la llegada con el lugar todavía lejos |
| Tiempos del reconocimiento de voz | `lib/voz_service.dart` | Medidos en un Pixel 9 Pro XL |
| Altura del teléfono (1,1 m), emisión cada 160 ms y −55 dBm a 1 m | `lib/procesador_senal.dart` y beacons | Datos medidos y configurados en los beacons |
