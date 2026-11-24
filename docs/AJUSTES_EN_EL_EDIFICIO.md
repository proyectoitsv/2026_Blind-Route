# Ajuste de los parámetros en el edificio

Varios de los valores que usa la navegación para calcular la posición se eligieron con simulaciones en la computadora, con cuentas o tomando valores típicos, ya que hasta ahora no se pudo medir cada uno en un edificio real, por lo que en la práctica pueden necesitar otro valor. En este documento se explica, para cada parámetro que conviene revisar, qué hace, dónde se cambia, qué se tiene que medir y cómo se decide el valor a partir de lo medido.

Algunos datos ya se midieron y quedaron cargados: los beacons emiten cada 160 ms (se puede cambiar desde la app del fabricante), la señal configurada a 1 m es de −55 dBm, que coincide con el valor por defecto de la app, y el teléfono se lleva a unos 1,1 m del piso, que pasó a ser el valor de `alturaTelefonoM` en `lib/procesador_senal.dart`. La sección 10 explica aparte un problema que todavía no se resolvió, la diferencia de ganancia entre los teléfonos, junto con lo que se probó y lo que hace falta medir.

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

Primero que todo hay que revisar los datos del edificio, ya que todo lo demás depende de ellos: la altura de cada beacon medida con cinta desde el piso, la posición de cada beacon en el plano (un metro de error en el plano se convierte en un metro de error en la posición), la escala del plano medida sobre dos paredes largas y el norte del plano, tomado con "Usar la dirección actual" lejos de columnas de metal. Una vez cargados, conviene calibrar cada beacon en al menos tres lugares a distancias distintas, porque varios de los ajustes de las secciones siguientes se apoyan en esas calibraciones. Cada calibración guarda el punto exacto que se marca en el plano, por lo que no hace falta pararse en el centro de una celda, aunque sí marcar bien dónde se está parado, con zoom y midiendo con cinta desde paredes o columnas que se vean en el plano. En espacios abiertos, sin referencias cerca, la opción "Justo debajo de un beacon" usa la posición del beacon como lugar de la calibración, y como un mismo punto da la distancia a todos los demás beacons, con una calibración debajo de cada uno ya se tienen puntos a distancias variadas para todos.

Los parámetros se ajustan de a uno y en el orden de las secciones, debido a que varios se cruzan entre sí (por ejemplo, el ancla y el filtro del panel actúan sobre lo mismo) y cambiando dos a la vez no se sabe cuál produjo el resultado. Para no perder lo probado sirve anotar cada prueba en una tabla con las columnas de la Tabla 2, completando una fila por cada cambio.

Tabla 2. Columnas del registro de pruebas.

| Fecha | Edificio | Parámetro | Valor anterior → nuevo | Prueba | Resultado |
|---|---|---|---|---|---|
| | | | | | |

## 2. Límites de n

Cuando se abre la navegación, la app ajusta para cada beacon una recta entre el RSSI y el logaritmo de la distancia con todas sus calibraciones, y de esa recta salen el n y el RSSI a 1 m. Si el n que sale queda fuera de los límites `_nMin` (1,5) y `_nMax` (4,5), definidos en `lib/procesador_senal.dart`, el ajuste se descarta y ese beacon usa el modelo por defecto (n = 2,7), debido a que un n así suele salir de calibraciones con ruido o de un beacon mal ubicado en el plano. Los límites se eligieron sin medir y quedan en el código, porque funcionan como un control de seguridad que se revisa una vez y no como un ajuste de gusto.

Para revisarlos se siguen estos pasos:

1. Calibrar cada beacon en al menos tres lugares, uno a 1 o 2 m, otro a 4 o 5 m y otro a 8 o 10 m, con el teléfono en la mano a 1,1 m del piso (los puntos debajo de los otros beacons también cuentan).
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

## 10. Diferencia de ganancia entre teléfonos (sin resolver)

Cada modelo de teléfono mide la señal de un mismo beacon con algunos dB de más o de menos según su antena, su carcasa y su chip Bluetooth, y como el n y el RSSI a 1 m de cada beacon salen de las calibraciones hechas con el teléfono del administrador, una persona que navega con otro modelo calcula las distancias con un modelo que no corresponde a su teléfono. Este problema aún no se ha resuelto, por lo que la app usa las calibraciones tal como las tomó el administrador, sin ninguna corrección según el teléfono que navega.

### 10.1 Cómo afecta a la posición

Si la diferencia Δ entre los dos teléfonos es constante, todas las distancias quedan multiplicadas por el mismo factor:

```
factor = 10^(Δ / (10 · n))
```

Con el n por defecto de 2,7 y un teléfono que mide 5 dB menos queda factor = 10^(5 / 27) = 10^0,185 = 1,53, por lo que ese teléfono ve todos los beacons un 53 % más lejos de lo que están, mientras que con 3 dB el factor es 10^(3 / 27) = 1,29. Con todas las distancias estiradas o achicadas en la misma proporción las circunferencias dejan de cruzarse en un punto, y la posición que mejor las explica queda lejos de la real. En la Tabla 7 se resume una simulación sin ruido hecha con el posicionador de la app, con 5 beacons en el techo y n = 2, valor con el que las distancias se estiran más que con 2,7 (5 dB dan un factor de 1,78 en vez de 1,53).

Tabla 7. Error de la posición según la diferencia del teléfono, en una simulación sin ruido.

| El teléfono del usuario mide | Distancias que calcula | Error medio | Peor caso |
|---|---|---|---|
| 8 dB menos | ×2,51 | 7,0 m | 17,8 m |
| 5 dB menos | ×1,78 | 5,0 m | 11,0 m |
| 3 dB menos | ×1,41 | 3,6 m | 7,9 m |
| Igual | ×1 | 0 m | 0,06 m |
| 3 dB más | ×0,71 | 2,7 m | 6,2 m |
| 5 dB más | ×0,56 | 3,4 m | 7,5 m |

Los puntos clave no se ven afectados, debido a que antes de comparar la lectura en vivo con el patrón guardado se resta la mediana de las diferencias de todos los beacons, de manera que un teléfono que mide todo 5 dB menos da la misma comparación que el del administrador.

Por otro lado, nada asegura que la diferencia entre dos teléfonos sea la misma a cualquier distancia. Si un teléfono mide −40 dBm donde el del administrador mide −50 dBm, y −65 dBm donde el otro mide −70 dBm, la relación entre los dos es una recta con pendiente distinta de 1:

```
rssi_usuario = a · rssi_admin + b
a = (−40 − (−65)) / (−50 − (−70)) = 25 / 20 = 1,25
b = −40 − 1,25 · (−50) = 22,5
```

Reemplazando el modelo del beacon, rssi_admin = tx − 10 · n · log10(d), queda:

```
rssi_usuario = (a · tx + b) − 10 · (a · n) · log10(d)
```

por lo que con una pendiente distinta de 1 el teléfono del usuario ve un n distinto (en el ejemplo, 1,25 veces el del administrador) además de un RSSI a 1 m distinto, y una corrección que sólo suma o resta dB no alcanza para compensarlo del todo.

### 10.2 Lo que se probó

Se programó y se probó en simulación una forma de que la navegación aprenda sola la diferencia, suponiendo que es constante. En cada ciclo se busca a la vez la posición y la diferencia que mejor explican todas las distancias, de manera parecida a como el GPS calcula el error del reloj del receptor, y el valor que se usa se acerca de a poco al que van dando los ciclos (con una constante de tiempo de 60 s caminando y de 240 s parado), debido a que cada ciclo tiene el ruido y el multicamino del lugar donde se tomó. Sólo aprende con 4 beacons o más y con la posición rodeada por ellos, porque con 3 beacons, o con todos los beacons de un mismo lado, la diferencia se confunde con un corrimiento de la posición, y cuando un punto clave coincide con buena confianza también usa el desplazamiento común que da esa comparación. Lo aprendido se guarda en el teléfono por edificio, ya que depende del teléfono con que se calibró cada uno.

Un primer intento, que tomaba la mediana de los residuos en la posición ya calculada, no funcionó con los teléfonos que miden menos, ya que la posición se corría hacia los bordes del plano y absorbía la diferencia, y por eso se pasó a resolver las tres incógnitas (x, y y la diferencia) juntas en cada ciclo. En una simulación caminando 3 minutos con 2 dB de ruido por lectura y 3 dB de multicamino por lugar, el valor aprendido quedó a menos de 1,5 dB del real entre los 50 y los 160 s, más tarde cuanto mayor era la diferencia, con los errores de la Tabla 8.

Tabla 8. Resultado del aprendizaje en una simulación de 3 minutos caminando, con tres semillas por diferencia.

| Diferencia real | Valor aprendido | Error en el último minuto, aprendiendo | Sin aprender |
|---|---|---|---|
| −8 dB | −7,0 a −7,3 dB | 2,6 a 3,2 m | 7,5 a 8,5 m |
| −5 dB | −4,5 a −4,7 dB | 2,4 a 2,7 m | 5,5 a 6,1 m |
| −3 dB | −2,8 a −3,0 dB | 2,3 a 2,5 m | 3,6 a 4,1 m |
| 0 dB | −0,3 dB | 2,2 a 2,4 m | 2,2 a 2,4 m |
| +3 dB | +2,3 dB | 2,1 a 2,3 m | 2,1 a 2,3 m |
| +5 dB | +4,0 a +4,1 dB | 2,0 a 2,3 m | 2,3 a 2,5 m |

Con relaciones con pendiente distinta de 1, como la del ejemplo de la sección 10.1, se repitió la misma simulación, cuyos resultados están en la Tabla 9. En los dos casos con poca diferencia el error casi no cambió con o sin aprendizaje, y en los dos con mucha diferencia el aprendizaje recuperó la mayor parte, aunque quedaron entre 0,3 y 0,7 m de más comparado con los 2,25 m que dio un teléfono igual al del administrador en la misma simulación.

Tabla 9. Resultado del aprendizaje con relaciones entre teléfonos de pendiente distinta de 1, donde r es el RSSI que mide el teléfono del administrador.

| Relación | Valor aprendido | Error aprendiendo | Sin aprender |
|---|---|---|---|
| 1,25 · r + 22,5 (el ejemplo de la sección 10.1) | +2,2 dB | 2,19 m | 2,13 m |
| 0,8 · r − 15 | +0,3 dB | 2,29 m | 2,27 m |
| 1,25 · r + 15 | −4,3 dB | 2,53 m | 4,76 m |
| 1,25 · r + 10 | −8,5 dB | 2,97 m | 8,14 m |

### 10.3 Por qué quedó sin integrar

El aprendizaje no se integró a la app debido a que todas las pruebas fueron simulaciones y todavía no se sabe cómo es la diferencia real entre el teléfono del administrador y otros modelos: si es constante alcanza con aprender un solo número, si cambia con la distancia también hay que corregir el n, y si es chica puede que no haga falta corregir nada. A su vez, un aprendizaje que se equivoca empeora la posición de teléfonos que sin él andarían bien, por lo que se decidió medir primero.

El código de la prueba quedó guardado aparte con `git stash`, con el nombre "Aprendizaje de la ganancia del telefono (sin terminar, para mas adelante)", e incluye `lib/estimador_ganancia.dart`, sus 12 tests, el interruptor "Aprender la ganancia del teléfono" del panel y los cambios en la navegación. Cabe aclarar que el stash existe sólo en la copia local del repositorio de la computadora donde se hizo y no se sube a GitHub. Para recuperarlo se busca su número en la lista y se aplica con ese número en lugar de N:

```bash
git stash list
git stash apply stash@{N}
```

### 10.4 Qué medir antes de resolverlo

Para saber cómo es la diferencia se comparan dos teléfonos en el mismo lugar, con la app del administrador instalada en los dos:

1. Poner el teléfono del administrador y uno de otro modelo uno al lado del otro, a 1,1 m del piso, con la calibración del piso abierta en los dos.
2. Parado a 1, 2, 4, 8 y 12 m de un beacon, anotar durante 20 o 30 s el valor típico de ese beacon en "Lecturas actuales" en cada teléfono, completando la Tabla 10.
3. Repetir con otro beacon y, si se puede, con un tercer modelo de teléfono.

Tabla 10. Registro de la comparación entre dos teléfonos.

| Distancia | RSSI del administrador | RSSI del otro teléfono | Diferencia |
|---|---|---|---|
| 1 m | | | |
| 2 m | | | |
| 4 m | | | |
| 8 m | | | |
| 12 m | | | |

Si la diferencia queda igual a todas las distancias, con 1 o 2 dB de variación, es constante, y alcanza con el aprendizaje guardado o con una corrección fija por modelo de teléfono. Si cambia de forma pareja con la distancia hay una pendiente, y además del RSSI a 1 m hay que corregir el n. Si en todos los modelos la diferencia queda en 1 o 2 dB, probablemente no haga falta corregirla, aunque ese caso no se simuló y conviene confirmarlo caminando el mismo recorrido con los dos teléfonos.
