# Resumen de los cambios del 23 y 24 de noviembre de 2026

Los cambios hechos al proyecto después del firmware del auricular con A2DP y HFP (commit `e2a767c`) quedaron en los seis commits de la Tabla 1. Para cada uno se resume qué problema resolvió y por qué se resolvió de esa manera, y al final se describen los pendientes, entre ellos la diferencia de ganancia entre teléfonos, que aún no se ha resuelto.

Tabla 1. Commits de los cambios.

| Commit | Fecha | Contenido |
|---|---|---|
| `722d908` | 23 de noviembre | Altura de los beacons y firmware 2.1 del auricular |
| `64c85f4` | 23 de noviembre | Comentarios del código reescritos y tests restaurados |
| `fadcf49` | 23 de noviembre | Altura del teléfono de 1,2 a 1,1 m |
| `9bbaf50` | 23 de noviembre | Seis parámetros nuevos en el panel de ajustes |
| `b094969` | 23 de noviembre | Guía para ajustar los parámetros en un edificio real |
| `7c97883` | 24 de noviembre | Calibración en el punto exacto y debajo de un beacon |

## 1. Altura de los beacons

El plano del piso es 2D, pero la señal de un beacon viaja en 3D, y hasta ahora tanto la calibración como el cálculo de la posición usaban la distancia sobre el plano, lo que equivale a suponer que todos los beacons están a la misma altura que el teléfono. Con un beacon en el techo, unos 1,4 m por encima del teléfono, esto deforma el modelo de cada beacon: en una simulación con calibraciones a 1, 3, 6 y 10 m la recta ajustada sobre la distancia del plano dio un n de 1,53 en lugar del 2,0 real, y la distancia calculada quedó 0,8 m más larga justo debajo del beacon, 0,45 m más corta a 4 m y 2 m más larga a 12 m. Como cada beacon a una altura distinta se deforma de forma distinta, las circunferencias dejaban de cruzarse en un punto y la posición se corría.

Para corregirlo, cada beacon guarda ahora su altura sobre el piso y la distancia que se usa en todo el cálculo es la real:

```
d = √(d_plano² + Δh²)
Δh = altura del beacon − altura del teléfono
```

La altura se carga en la configuración del piso, en la sección "Altura de los beacons", con un deslizador de 0 a 5 m de a 10 cm y la opción "Usar en todos" para los edificios donde todos los beacons están a la misma altura. Se guarda en la base de datos local, que pasó a la versión 18 con la columna `altura` en la tabla `beacons`, y viaja a la nube dentro del mismo JSON del mapa, por lo que no hizo falta una columna nueva en Supabase y las versiones viejas de la app la ignoran. Un beacon sin altura indicada se toma a la altura del teléfono, que es lo que se suponía antes, de manera que los mapas viejos siguen funcionando igual.

En el ajuste de los modelos, la distancia de cada calibración se calcula en 3D con la altura que tiene el beacon al abrir la navegación, por lo que cambiar la altura de un beacon después de calibrarlo no obliga a calibrar de nuevo. En el posicionador las incógnitas siguen siendo x e y sobre el plano, pero la distancia que se compara con la de cada beacon es la 3D, ya que si se tomara como distancia sobre el plano nunca se podría ubicar a una persona justo debajo de un beacon alto.

La altura del teléfono quedó como una constante (`alturaTelefonoM` en `lib/procesador_senal.dart`) y no como un ajuste por persona, debido a que entre una persona alta y una baja la altura del teléfono cambia unos 40 cm, lo que en una simulación agregó entre 0,1 y 0,15 m de error medio, bastante menos que el resto de los errores de la señal. En el commit `fadcf49` esa constante pasó de 1,2 m, que era un valor supuesto, a 1,1 m, que es la altura a la que se midió que se lleva el teléfono, y los tests pasaron a tomar el valor de la constante en vez de tenerlo escrito.

## 2. Firmware 2.1 del auricular

El auricular ESP32 tenía dos problemas, que se corrigieron en el firmware 2.1 (`hardware/esp32_blindroute_audio/`) y se explican con detalle en su `COMO_FUNCIONA.md`.

El primero era que con el Pixel 9 Pro XL el auricular emparejaba pero no se conectaba. El firmware 2.0 buscaba para siempre al teléfono que tenía guardado, con un intento de HFP cada 5 s y uno de A2DP cada 10 s, y como cada intento ocupa la radio hasta 5 s cuando el teléfono no contesta, la radio pasaba casi todo el tiempo llamando a ese teléfono y casi no escuchaba a otros. A su vez, el teléfono guardado era el primero de la lista de vinculados (el Samsung S24) y no el último que se usó, por lo que con el Samsung cerca el ESP32 se reconectaba a él y ocupaba A2DP y HFP, que admiten un solo teléfono a la vez, y con el Samsung lejos la radio estaba ocupada buscándolo. En la 2.1 el auricular guarda el último teléfono usado y lo busca sólo durante 60 s al arrancar o al perder el enlace, turnando un intento de HFP y uno de A2DP cada 6 s, y después queda visible y conectable para que cualquier teléfono vinculado se conecte desde sus ajustes de Bluetooth. También se agregó el comando `o` por USB, que olvida todos los teléfonos vinculados.

El segundo era el sonido metálico. El amplificador estaba configurado en modo mono de 16 bits, que en el ESP32 clásico lee las muestras de a pares, y si salen en el orden invertido aparece una copia espejada del sonido, que en las llamadas (8 o 16 kHz) cae en plena voz y suena metálica o robótica y en la música agrega un brillo áspero por encima de 14 kHz. Desde la 2.1 el firmware manda tramas estéreo con la misma muestra en las dos ranuras, con lo que el orden deja de importar. Además, antes de empezar a sonar y después de cada corte se juntan 80 ms de música (`PREBUFFER_A2DP_MS`), debido a que sin ese colchón cualquier ráfaga atrasada del Bluetooth dejaba al amplificador sin datos y metía huecos de silencio que también suenan ásperos, y el informe `[bt-audio]` del puerto serie ahora cuenta esos huecos en `cortes`.

Cabe aclarar que el firmware 2.1 no se compiló ni se probó en la placa, porque en la computadora donde se hizo no está instalado el núcleo del ESP32 para Arduino.

## 3. Comentarios del código

En el commit `64c85f4` se reescribieron los comentarios de todo `lib/` y del firmware como los escribiría el propio desarrollador, sin frases del tipo "el usuario comenta que" ni la historia de cada cambio, y se acortaron los que repetían lo que ya dice el código. Los procesos más difíciles de seguir, como el A\* del cálculo de la ruta y el ajuste de los modelos con las calibraciones, quedaron explicados paso a paso, y cada archivo de `lib/` empieza ahora con un comentario que dice qué contiene y en qué se diferencia de los archivos parecidos (por ejemplo, el filtro One Euro, que suaviza la posición, y el detector de movimiento, que decide con el acelerómetro si la persona está quieta o caminando).

Durante esa reescritura se perdieron algunas marcas de dónde salió cada valor, como "medido en el aula" o "probado en el campo". Esas marcas se recuperaron del historial de git para armar la Tabla 6 de `docs/AJUSTES_EN_EL_EDIFICIO.md`, pero no se volvieron a agregar a los comentarios del código.

## 4. Tests

Hasta ahora los tests se borraban antes de cada commit, y como el código siguió cambiando sin ellos, al correrlos fallaban 41. Esto se debía a que los cambios de los tests que acompañaban a la versión 18 de la base de datos se habían descartado, entre ellos la versión de la base de datos falsa que usan los tests (`test/base_falsa.dart`), por lo que se restauraron y se actualizaron, y desde este cambio los tests se suben en el mismo commit que el código que prueban. Un test arma una situación conocida (por ejemplo, un piso con tres beacons y las lecturas que darían a cierta distancia), corre el código real de la app y verifica que el resultado sea el esperado, por lo que sirve para detectar cuando un cambio rompe algo que antes andaba.

Todos se corren con `flutter test`, y uno solo indicando su archivo, por ejemplo `flutter test test/alturas_test.dart`. Al cierre de estos cambios pasan los 376 tests.

## 5. Parámetros nuevos en el panel de ajustes

Seis valores que estaban fijos en el código pasaron al panel de ajustes en el commit `9bbaf50`, debido a que dependen del edificio (del ruido de la señal y de la cantidad de metal) y la única forma de elegirlos es caminando con distintos valores, cosa que con el valor en el código obliga a volver a instalar la app en cada prueba. Todos se pueden ajustar por edificio y arrancan en el mismo valor que tenían en el código, por lo que nada cambia hasta que se mueven. En la Tabla 2 se resumen los seis.

Tabla 2. Parámetros que pasaron al panel de ajustes.

| Parámetro | Sección del panel | De fábrica | Rango |
|---|---|---|---|
| Ancla, parado | Seguimiento de la posición | 3 | 0,5 a 8 |
| Ancla, caminando | Seguimiento de la posición | 0,25 | 0,05 a 1,5 |
| Calidad mínima de la brújula | Brújula (sección nueva) | 0,35 (se apaga 0,2 por debajo) | 0,1 a 0,9 |
| Paso de costado | Brújula | 3 % | 0 a 50 % |
| Paso hacia atrás | Brújula | 15 % | 0 a 100 % |
| Coincidencia perfecta | Puntos clave | 4 dB | 1 a 8 dB |

Si la coincidencia perfecta queda por encima de la mínima, la app la baja a medio dB por debajo de la mínima. En cambio, los límites de n y los umbrales de la calidad del rumbo quedaron en el código, porque los primeros funcionan como un control de seguridad que se revisa una vez y los segundos dependen del modelo de teléfono más que del edificio. Las notas del panel que decían "Antes: X" pasaron a decir "De fábrica: X", y se agregaron los tests de `test/ancla_y_rumbo_test.dart` y uno de los valores de fábrica en `test/ajustes_navegacion_test.dart`.

## 6. Guía de ajustes en el edificio

El documento `docs/AJUSTES_EN_EL_EDIFICIO.md` (commit `b094969`) explica, para los límites de n, el ancla, la calidad del rumbo, la calidad mínima de la brújula, el paso de costado y hacia atrás y la coincidencia perfecta, qué hace cada uno, dónde se cambia, qué hay que medir y cómo se decide el valor a partir de lo medido. También tiene la lista de los demás valores del código que se eligieron sin medir, con el problema que indica que hay que revisarlos, y la de los que sí se midieron. Los datos medidos que se cargaron son la emisión de los beacons cada 160 ms, la señal de −55 dBm a 1 m y la altura del teléfono de 1,1 m.

## 7. Calibración en el punto exacto

Hasta el commit `7c97883` cada calibración guardaba sólo la celda donde se tocó, y el ajuste del modelo suponía que el administrador estaba parado en el centro de esa celda. Con celdas de 1 m eso podía meter hasta 0,7 m de error en la distancia de cada calibración (la mitad de la diagonal de la celda), y como las celdas de la grilla no coinciden con las baldosas del piso, al calibrar siempre se quedaba un poco corrido sin forma de saber cuánto.

Ahora se toca el punto exacto donde se está parado y la calibración guarda ese punto, en las columnas `pos_x` y `pos_y` de la base de datos, que pasó a la versión 19. Las posiciones de los beacons ya se guardaban como un punto exacto del plano y no como una celda, por lo que la distancia de cada calibración se calcula de punto a punto, con la escala del plano y la altura del beacon, sin importar en qué parte de la celda esté cada uno. Las calibraciones viejas, que no tienen el punto, siguen usando el centro de su celda.

En los espacios abiertos, donde no hay paredes ni puertas cerca para ubicarse en el plano, es difícil marcar el punto con precisión, por lo que se agregó la opción "Justo debajo de un beacon", que usa la posición del beacon como lugar de la calibración. Como un mismo punto da la distancia a todos los beacons que se escuchan desde ahí, con una calibración debajo de cada beacon ya se tienen puntos a distancias variadas para todos los demás. En el plano los pines de las calibraciones se dibujan en el punto exacto, y mientras se toma una calibración el plano no acepta toques, para que un toque accidental no cambie el punto a mitad de la captura. Se agregaron los tests de `test/calibracion_punto_test.dart` y se actualizó `test/configuracion_piso_test.dart`.

Cuando hay varias calibraciones en el mismo lugar, cada una entra como un punto más en la recta que se ajusta para cada beacon, por lo que dos calibraciones en el mismo punto funcionan como una sola con el promedio de las dos lecturas y el doble de peso. Las calibraciones a menos de 0,5 m de un beacon (en 3D) no se usan para el ajuste de ese beacon, debido a que tan cerca el modelo logarítmico deja de valer (campo cercano) y el RSSI se satura, por lo que esos puntos torcerían la pendiente de la recta.

## 8. Pendiente: diferencia de ganancia entre teléfonos

Cada modelo de teléfono mide la señal de un mismo beacon con algunos dB de diferencia según su antena, y como las calibraciones se hacen con el teléfono del administrador, una persona con otro modelo calcula todas las distancias más largas o más cortas en la misma proporción. En una simulación sin ruido, una diferencia de 3 a 5 dB llevó el error medio de la posición a entre 2,7 y 5 m, mientras que los puntos clave no se ven afectados porque su comparación ya descuenta el desplazamiento común a todos los beacons.

Este problema aún no se ha resuelto. Se programó un aprendizaje automático de la diferencia, que en simulación la estimó con menos de 1,5 dB de error en 50 a 160 s de caminata, pero quedó sin integrar a la app, debido a que supone que la diferencia es constante y todavía no se midió con teléfonos reales si lo es o si cambia con la distancia (en ese caso también cambia el n y una corrección de dB no alcanza). El código quedó guardado aparte con `git stash`, sólo en la copia local del repositorio, con el nombre "Aprendizaje de la ganancia del telefono (sin terminar, para mas adelante)". La explicación completa, los resultados de las simulaciones y la medición que hay que hacer antes de resolverlo están en la sección 10 de `docs/AJUSTES_EN_EL_EDIFICIO.md`.

## 9. Otros pendientes

Los cambios de la app se verificaron con los tests automáticos y con `flutter analyze`, pero la altura del teléfono y los parámetros nuevos del panel no se probaron en el teléfono, y los parámetros que se eligieron con simulaciones todavía se tienen que medir en un edificio real siguiendo la guía. Por otra parte, el firmware 2.1 del auricular falta compilarlo y probarlo, siguiendo la lista de "Qué probar si suena metálico" de su `COMO_FUNCIONA.md`, y las marcas de origen de algunos valores ("medido en el aula", "probado en el campo") siguen sin volver a los comentarios del código.
