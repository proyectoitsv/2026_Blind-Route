# Blind Route: contexto del proyecto

- No modificar código `.dart`, `pubspec.yaml` ni configuración de plataforma sin pedido explícito del usuario.
- **Al empezar un chat nuevo:** leer este archivo primero (Claude lo carga solo). Las secciones "Estado actual" y "Registro de cambios" dicen qué está hecho y qué falta, así no hace falta repetir el contexto.
- **Regla de contexto:** cada vez que la conversación supere el **30%** del contexto, avisar al usuario y actualizar este archivo con los cambios hechos en el chat (ver [Registro de cambios](#registro-de-cambios-entre-chats)), para continuar en un chat nuevo.
- Antes de afirmar algo sobre el código, leer el archivo correspondiente. El código cambia seguido y este documento puede quedar desactualizado.

## Qué es

Blind Route (BlindRoute) es un sistema de **navegación interior accesible** para personas con discapacidad visual. Guía dentro de edificios usando:

- Beacons BLE ubicados sobre el plano de cada piso, para estimar la posición del usuario.
- Rutas calculadas con A* sobre una grilla del plano.
- Guía por voz (texto a voz y reconocimiento de voz) con instrucciones habladas.
- Brújula y sensores del teléfono para orientación y detección de movimiento y giros.

Hay **dos apps Flutter** (flavors de Android) que comparten código:

| App | Entry point | Flavor | Función |
|---|---|---|---|
| Usuario | `lib/main_user.dart` | `user` (BlindRoute) | Navegar y descargar mapas publicados |
| Admin | `lib/main_admin.dart` | `admin` (BlindRoute Admin, sufijo `.admin`) | Cargar edificios, pisos, beacons, zonas, lugares, rubros y calibraciones |

Build de referencia (de los comentarios de cada `main`):

```bash
flutter run --flavor user -t lib/main_user.dart
flutter run --flavor admin -t lib/main_admin.dart
```

Backend: **Supabase** (login de admin por email y contraseña, con registro público desactivado; catálogo de mapas publicados; Storage con el bucket `map-images` para los planos).

## Stack

- Flutter / Dart, SDK `^3.11.5`.
- `flutter_blue_plus` (BLE), `sqflite` (base local), `path_provider`, `shared_preferences`.
- `flutter_compass`, `sensors_plus` (orientación y movimiento).
- `flutter_tts`, `speech_to_text` (voz).
- `supabase_flutter`, `wakelock_plus`, `permission_handler`, `image_picker`.
- Lints: `flutter_lints` (`analysis_options.yaml`).
- Tests: `test/zonas_test.dart` (bloqueo por centro, paredes, snap y rutas que no cruzan zonas; 21 casos) `test/histeresis_celda_test.dart` (histéresis frente a paredes angostas; 12 casos) `test/ajustes_navegacion_test.dart` (ajustes en capas; 10 casos), `test/asistente_trazo_test.dart` (imán con zoom, paredes finas; 5 casos) `test/orientador_llegada_test.dart` (orientación hacia el lugar al llegar; 12 casos) y `test/ajustes_voz_test.dart` (ajustes de voz del usuario; 3 casos). Se corren con `flutter test`. Fuera de eso, los tests de verificación de cada sesión se hacen en archivos temporales y se borran.

## Estructura de `lib/`

**Pantallas y UI**
- `pantalla_princ_usuario.dart`: inicio de la app de usuario.
- `pantalla_login_admin.dart`: login del admin.
- `pantalla_config.dart` (~3700 líneas): configuración de pisos, beacons, zonas y lugares (admin). Incluye la escala con puntos desplazables y la calibración.
- `pantalla_naveg.dart` (~4900 líneas): pantalla de navegación.
- `pantalla_mapas_online.dart`: catálogo de mapas publicados (usuario).
- `pantalla_mapas_admin.dart`: mapas publicados en la nube, de todos los dispositivos (admin).
- `lista_edificios.dart`, `lista_pisos.dart`: listas locales de edificios y pisos.
- `pantalla_rubros.dart`: rubros (categorías de lugares) editables.
- `modo_automatico.dart`: detección automática del piso y del mapa.
- `mapa_widget.dart` (~1300 líneas): painters y dibujo del plano, ruta, beacons y zonas.
- `tema.dart`: tokens de diseño. Fondo `#0D1117`, acento cian `#00C8E0`, ruta `#2979FF`. Contraste WCAG AA.

**Datos locales y modelos**
- `database.dart`: `DatabaseHelper` (singleton de sqflite), versión de esquema **17**.
- `beacon_model.dart`, `zona_model.dart`, `poi_model.dart`, `calibracion_model.dart`: modelos.
- `rubros.dart`, `piso_util.dart`: rubros y convención de numeración de pisos.

**Nube**
- `supabase_config.dart`: URL y clave pública del proyecto.
- `supabase_service.dart`: catálogo liviano de mapas publicados. Los datos pesados (beacons, zonas, calibraciones) se bajan recién al tocar "Descargar". También sube y baja los ajustes de navegación (tabla `ajustes_navegacion`).
- `../supabase/ajustes_navegacion.sql`: tabla y permisos de los ajustes de navegación (lee cualquiera, escribe cualquier admin logueado). Se corre a mano en el SQL Editor de Supabase y se puede volver a correr.

**Posicionamiento**
- `bluetooth_helper.dart`: escaneo BLE. Es un recurso global y único. Escanea en modo `lowLatency` y renueva el escaneo cada 25 min (límite de Android).
- `procesador_senal.dart`: modelo log-distancia ajustado por beacon (`txPower` y exponente `n`). Mediana sobre una ventana de **tiempo** (segundos), no de lecturas.
- `posicionador.dart`: estimación de posición por **multilateración** de los rangos.
- `filtro_un_euro.dart`: filtro One Euro sobre la posición, con término adaptativo según el movimiento.
- `detector_movimiento.dart`: quieto o caminando, a partir del acelerómetro. El umbral de caminata es regulable.
- `orientacion_service.dart`: brújula suavizada con media circular.
- `restriccion_zonas.dart`: si la medición cae en una celda bloqueada o adentro del polígono de una zona, la lleva al **centro** de la celda libre más cercana, prefiriendo el lado donde ya estaba el usuario.
- `histeresis_celda.dart`: confirma una celda nueva recién tras varios ciclos seguidos en ella. A través de una pared angosta pide más ciclos, con una ventana corta para deshacer un cruce falso.

**Navegación**
- `grilla_nav.dart`: grilla de navegación. El lado de celda es configurable por piso, entre 0.5 y 1.0 m.
- `pathfinder.dart`: A* en cruz (sin diagonales) con un heap mínimo propio. Una celda está bloqueada solo si su **centro** cae en una zona. Dos celdas vecinas se conectan si el segmento entre sus centros no atraviesa ninguna zona ("paredes", calculadas una vez por piso, también para las diagonales). Expone `esZonaProhibida`, `conectadas` y `puntoEnZona` para la restricción de zonas.
- `seguidor_ruta.dart`: dónde está el usuario respecto de la ruta y qué tramo indicarle.
- `orientador_llegada.dart`: al llegar a un lugar, escalera o ascensor, lo hace girar con la brújula hasta quedar de frente antes de anunciar la llegada. Lógica pura; la alimenta `pantalla_naveg.dart` ciclo a ciclo.
- `asistente_trazo.dart`: "imán" de ángulos (rectos y 45°) para trazar la escala y las zonas prohibidas. Con `metrosPorPixel`, la alineación y el largo mínimo se miden en píxeles de pantalla (con tope en los valores en metros de siempre): con zoom se dibuja más fino.
- `ajustes_navegacion.dart`: parámetros de los giros anticipados (atraso, anticipos) y del seguimiento de la posición (umbral de caminata, ventanas de señal, filtro One Euro, velocidad máxima). El valor vigente sale de **tres capas**: lo cambiado en el edificio actual, lo cambiado en general y el valor del código. Cada capa guarda solo lo que se cambió en ella. Por edificio solo se cambian los que dependen del edificio (`porEdificio`); el umbral de caminata y los anticipos son solo generales. Se guardan en el teléfono (`shared_preferences`) y en la nube. Los interruptores de prueba (freno lateral por brújula, restringir zonas) viven solo en memoria.
- `panel_ajustes_navegacion.dart`: panel de ajustes, **solo en la app del admin**, en la pantalla de navegación. Alcances "Este edificio" y "General", los dos para cualquier admin mientras se calibra. Cada cambio rige al instante y se sube a la nube al soltar el control. Muestra el diagnóstico "Señal ahora".
- `entorno_app.dart`: `EntornoApp.esAdmin`, que fija `main_admin.dart`. Lo usa la pantalla de navegación para mostrar el panel solo en el admin.

**Voz**
- `voz_service.dart`: TTS y STT centralizados.
- `ajustes_voz.dart`: velocidad, volumen, tono y repetición de las indicaciones, a gusto de cada persona (porcentaje de la voz de siempre). Sólo en el teléfono (`shared_preferences`, clave `ajustes_voz`). Los aplica `VozService`.
- `pantalla_ajustes_voz.dart`: pantalla de esos ajustes en la app del usuario (botón "Ajustes de voz" del inicio). Al soltar un control dice una frase de prueba.
- `buscador_lugares.dart`: búsqueda de lugares por voz, por nombre, rubro o palabras clave.

## Conceptos del dominio

- **Edificio**: contiene pisos.
- **Piso**: se identifica por número. `0` es planta baja, `>0` es piso N, `<0` es subsuelo N. El admin ofrece de -3 a 20. El nombre visible se deriva siempre del número (`PisoUtil`), y así la nube no necesita una columna extra.
- **Plano**: imagen del piso con escala (`escala_metros`, `escala_metros_alto`), tamaño de celda (`tam_celda_metros`) y rotación (`rotacion_mapa`).
- **Beacon**: posición normalizada (0 a 1) sobre la imagen del plano, con su RSSI filtrado. Emite cada **160 ms** (~6 veces por segundo).
- **Zona no transitable**: polígono de vértices normalizados.
- **Lugar de interés (POI)**: puede ser común (baño, aula, terminal) o **escalera** (sube o baja, ascensor). Tiene rubro y palabras clave.
- **Rubro**: categoría de un lugar ("Comida", "Kiosco", "Baño"...) con las palabras con las que la gente lo pide. Son de fábrica o los crea el admin.
- **Calibración**: lecturas BLE tomadas por el operador parado en una celda conocida de la grilla. Sirven para ajustar `txPower` y `n` por beacon. Un beacon con menos de 5 lecturas en la toma se descarta.
- **Catálogo local vs. nube**: el admin tiene edificios locales en su teléfono, y los mapas publicados en Supabase. El usuario descarga, actualiza o quita mapas del catálogo.

## Base de datos local (sqflite, versión 17)

Tablas: `edificios`, `pisos`, `beacons`, `zonas_no_transitables`, `lugares_interes`, `rubros`, `calibraciones`.

Historial de migraciones según el comentario del código: v14 agrega `lugares.palabras_clave`, v15 agrega `.rubro`, v16 agrega `.ascensor`, v17 agrega `rubros`. Las claves foráneas están activas (`PRAGMA foreign_keys = ON`).

## Convenciones

- **Idioma**: todo en español rioplatense: nombres de clases y variables, comentarios, textos de la UI y mensajes de commit.
- **Nombres**: clases en PascalCase, archivos en snake_case, identificadores en español.
- **Comentarios**: explican el "por qué" en bloques con separadores (`───`, `═══`). Cuando una decisión es delicada, se documenta el problema que resuelve.
- **Accesibilidad**: la app está pensada para usarse sin ver. Todo feedback importante va por voz, y la UI tiene que funcionar con lector de pantalla.
- **Commits**: mensaje corto en español. Si algo no fue probado en el teléfono, el mensaje lo aclara entre paréntesis (por ejemplo, "(no probado)").

## Estado actual

- Rama de trabajo: `app_doble`. Rama base: `main`. HEAD en el commit de la orientación al llegar, los puntos clave y los ajustes de voz (2026-10-26), sobre `aee68a8`.
- Lo de las sesiones del 2026-10-19 al 2026-10-22 está commiteado (`a600e8f`, `6c5cb19`, `54d36f1`, `01cfe36`, `6c3d063`). Según el Registro, nada de eso está probado en el teléfono.
- Lo del 2026-10-26 ("Ubicación lista" y textos del admin) está commiteado en `aee68a8` y el usuario lo probó en el teléfono.
- Lo demás del 2026-10-26 también está commiteado: orientación al llegar, "Ubicación lista" con la posición asentada, palabras cortas, puntos clave y ajustes de voz del usuario. El usuario probó los puntos clave y los ajustes de voz ("mejoró bastante"). El arreglo del idioma de la voz no está probado; de lo demás no dijo nada. Detalle en el Registro.
- `flutter analyze` pasa, con 4 avisos de lint que ya existían (ninguno nuevo). `flutter test` pasa (63 casos).
- Varios commits anteriores están marcados como "no probado" (`6d105e6`, `c34654a`, `b5c83df`, `29bc508`).
- `feedback.md` está vacío. Es el archivo de feedback del proyecto.
- `log.txt` (~8 MB, codificado en UTF-16) es un volcado de logcat en la raíz del repositorio. Es anterior a los cambios de la sesión: no tiene sus líneas de diagnóstico.

**Próximos pasos, en orden (a verificar en el teléfono):**
1. Abrir el panel de ajustes de navegación y mirar **"Señal ahora"**. Con beacons a 160 ms se esperan 4 a 6 lecturas por segundo por beacon. Si llegan 1 o 2, el límite es la recepción del teléfono, no el filtrado.
2. Probar "mapa no encontrado" con el mapa ya descargado. Buscar en el log `[Modo automático] Primer beacon con mapa local a los X s` y `[Piso] Elegido … a los X s`.
3. Ajustar el atraso empezando por **Equilibrada**: anticipo del giro en 0, después subir el atraso hasta que "Girá…" salga en la esquina.
4. Probar las zonas con el criterio por centro: que la posición no salte cerca de esquinas chicas, que la ruta pase por pasillos que antes se cortaban y que no atraviese paredes angostas. Si aparece en el log `[Pathfinder] Sin ruta con el margen de borde activo`, revisar si la franja de borde (`margenBordeMetros`) tapa un pasillo real.
5. Ajustes por edificio: volver a correr `supabase/ajustes_navegacion.sql` en Supabase (la versión sin rol de desarrollador) y probar "Probar navegación" (lista de pisos) con el panel: que los cambios digan "Todo guardado en la nube" y que la app de usuario los reciba al descargar el mapa o al abrir la navegación.
6. Poner como valores del código (`porDefecto`) los valores que el usuario va a pasar. Hoy son los de la vieja preselección "Equilibrada".
7. Orientación al llegar: llegar a un lugar que queda al costado, a uno que queda adelante y a una escalera o ascensor. Ver que diga hacia dónde girar, que no hable mientras se gira y que "Llegaste" salga al quedar de frente.
8. "Ubicación lista" con la posición asentada: abrir la navegación quieto (tendría que decirlo entre 3 y 6 s después de aparecer el punto, ya sin saltos) y caminando (a los 6 s). En el log: `[Posicionamiento] Ubicación asentada: …`.
9. Palabras cortas: contestar "sí" / "no" enseguida después de la pregunta y pedir destinos de una palabra. En el log, `[Voz] Entendido: "…" (interpretaciones: …)` muestra qué oyó el reconocedor y cuál se eligió.
10. Puntos clave: tomar uno, pararse ahí mirando para distintos lados y ver que la posición vaya a la celda. El log `[Fingerprint]` (cada ~2 s, sólo con puntos clave en el piso) dice qué dio cada uno en dB, si quedó afuera por el rumbo, por pocos beacons, por ambigüedad o por el radio, y el peso aplicado.
11. Ajustes de voz en la app del usuario: cambiar velocidad, volumen, tono y repetición con TalkBack prendido; que se escuche la frase de prueba y que los cambios sigan al reabrir la app.

**Pendientes conocidos:**
- Las calibraciones guardadas antes pueden tener valores inflados por lecturas repetidas. Conviene repetir las que se hicieron con beacons que se oían poco.
- Las preselecciones de fábrica tienen valores estimados. Si ninguna anda, el usuario va a crear la suya.
- Histéresis de celda frente a paredes angostas: implementada (`histeresis_celda.dart`), falta probarla en el teléfono. Ver el Registro del 2026-10-21.
- Cuando el usuario pase los valores calibrados, ponerlos en el código (`porDefecto`) y sacar de la app lo que ya no se tiene que poder cambiar: el alcance "General" y, por edificio, todo lo que no dependa del edificio.
- Las preselecciones viejas quedan guardadas en los teléfonos (`nav_preselecciones`) sin usarse. Se pueden borrar más adelante.
- El A* no se mueve en diagonal. Las paredes ya están calculadas para las diagonales, pero habilitarlas obliga a revisar `seguidor_ruta.dart` (tramos rectos, giros de 90°, largo de la ruta).
- **Copia de los filtros en el visualizador de beacons** (`rssi_monitor`, otro proyecto, ver el Registro del 2026-10-22): si cambia un filtro o un valor por defecto de BlindRoute (`procesador_senal.dart`, `filtro_un_euro.dart`, `posicionador.dart`, `detector_movimiento.dart`, `ajustes_navegacion.dart` o las constantes de `pantalla_naveg.dart`), hay que actualizar `rssi_monitor/lib/blindroute_filter.dart`. Cada etapa dice de dónde sale.

## Registro de cambios entre chats

Al cerrar un chat por la regla del 30%, agregar acá una entrada con fecha, los archivos de documentación modificados y lo que quedó pendiente. Así el chat nuevo arranca sabiendo qué ya está hecho.

### 2026-10-19 (chat largo, cerrado el 2026-10-21)

**Documentación modificada:** este `claude.md`.

**Cambios de código (sin commit, sin probar en el teléfono):**
- **Giros:** se quitó el ajuste a la esquina por giro de brújula y la velocidad aprendida. Se eliminaron `detector_giros.dart` y `velocidad_usuario.dart`. `pantalla_naveg.dart`, `detector_movimiento.dart`, `filtro_un_euro.dart` y `seguidor_ruta.dart` se volvieron a `20e33dc`. Los giros se anuncian con el atraso más el anticipo, y el ritmo de acercamiento a la esquina se mide en vivo.
- **Zonas prohibidas:** la posición se lleva a la celda transitable más cercana (`restriccion_zonas.dart`, `pathfinder.dart`). Si el destino cae dentro de una zona, llegar al final de la ruta cuenta como llegada.
- **Escala en el admin:** puntos desplazables como en las zonas, con medida del largo y del ancho en dos pasos (`pantalla_config.dart`, `mapa_widget.dart`). Se quitó la línea elástica.
- **Seguimiento de la posición:** parámetros regulables (umbral de caminata, ventanas de señal en segundos, filtros One Euro, velocidad máxima, freno lateral por brújula).
- **Preselecciones de ajustes:** 5 de fábrica y propias, con calificación, descripción y edición (`ajustes_navegacion.dart`, `panel_ajustes_navegacion.dart`). Incluye el diagnóstico "Señal ahora".
- **Modo automático:** recuerda cada beacon 8 s. La consulta a la nube corre aparte, con espera de 4 s y límite de 6 s, y no frena al mapa local (`modo_automatico.dart`).
- **BLE:** escaneo en `lowLatency` (antes `balanced`, que escucha 1 s de cada 4). Renovación del escaneo cada 25 min (`bluetooth_helper.dart`).
- **Lecturas repetidas:** navegación y admin cuentan solo lecturas nuevas por beacon (`pantalla_naveg.dart`, `pantalla_config.dart`). Las calibraciones exigen un mínimo de 5 lecturas por beacon.

**Pendiente:** lo indicado en "Próximos pasos" y "Pendientes conocidos" del Estado actual.

### 2026-10-21: zonas prohibidas por centro de celda

**Documentación modificada:** este `claude.md`.

**Problema:** las zonas bloqueaban celdas enteras por contacto con el contorno. Una esquina de 20 cm bloqueaba una celda de 1 m: la posición saltaba y la ruta se cortaba.

**Cambios de código (sin commit, sin probar en el teléfono):**
- `pathfinder.dart`: una celda se bloquea solo si su centro cae en la zona. Se quitó `_rasterizarContorno`. Dos celdas vecinas (también diagonales) se conectan si el segmento entre sus centros no atraviesa ninguna zona. Esas "paredes" se calculan una vez por piso (`_marcarParedes`, bits en `_paredes`), y el A* no pasa por una conexión cortada. Las celdas pegadas a una pared angosta siguen sumando el costo de despegue. Los centros salen de `GrillaNav`, igual que en `mapa_widget.dart` y `restriccion_zonas.dart`. Nuevos `conectadas()` y `puntoEnZona()`.
- `restriccion_zonas.dart`: el snap va al **centro** de la celda libre más cercana (se quitó `_puntoMasCercanoEnCelda`). También corrige cuando la medición cae adentro del polígono aunque su celda esté libre (pared angosta), para que la preferencia por el lado evite el salto de celda. El "lado" ya no atraviesa paredes. `radioLocalMetros` y `penalizacionOtroLadoMetros` no cambiaron.
- `pantalla_naveg.dart`: la restricción recibe `conectadas` y `puntoEnZona`. `_finDeRutaSiObjetivoEnZona` ya mira la celda del lugar, que es lo correcto con el nuevo criterio (solo se aclaró el comentario).
- `test/zonas_test.dart`: 21 casos (esquina de 20 cm, pared de 20 cm, celda de 0,5 m con la mitad bloqueada, medición en medio de una pared angosta y de una gruesa, snap, rutas que no cruzan zonas, simetría de las conexiones).

**Sin tocar:** el estimador (`procesador_senal`, `posicionador`, filtros), la histéresis de celda, `margenBordeMetros` y `grilla_nav.dart`.

**Pendiente:** lo indicado en "Próximos pasos" y "Pendientes conocidos" del Estado actual.

### 2026-10-21: histéresis de celda frente a paredes angostas

**Documentación modificada:** este `claude.md`.

**Nota:** el Estado actual dice que todo está sin commitear en `a5d4db0`, pero `a600e8f` y `6c5cb19` ya incluyen los cambios del 2026-10-19 y del 2026-10-21 (zonas por centro, `test/zonas_test.dart`), y el árbol estaba limpio.

**Problema:** con el bloqueo por centro, una medición apenas del otro lado de una pared angosta (afuera del polígono) cambia de celda, y caminando `_HisteresisCelda` confirma en 1 ciclo (no filtra). Antes la franja bloqueada obligaba a la medición a pasar unos 0,65 m más allá de la pared. Además, `previa` de la restricción es `_posicionPermitida`: un solo ciclo del otro lado da vuelta la preferencia de lado.

**Análisis (simulación 1D con ruido correlacionado; detalle y script en las notas de la sesión, `histeresis-celda-paredes.md`):** hoy, caminando a 0,5 m de la pared con σ 0,5 m, salen unos 14 cruces falsos por minuto. Subir los ciclos contando la misma celda no sirve con celdas de 0,5 m (la candidata cambia de celda y el conteo se reinicia). Subirlos sin más baja el parpadeo pero alarga los episodios del lado equivocado (más recálculos de ruta que hoy), porque volver también cuesta N ciclos.

**Cambios de código (aprobados por el usuario; sin commit, sin probar en el teléfono):**
- `histeresis_celda.dart` (nuevo): la histéresis salió de `pantalla_naveg.dart` y ahora es `HisteresisCelda`, pública, para poder probarla. Recibe la grilla, `esZonaProhibida` y `conectadas`, igual que `RestriccionZonas`. Si la candidata está del otro lado de una pared (desde la celda confirmada no se llega caminando, en cruz y sin atravesar paredes, sin un rodeo de más de `rodeoMaxMetros` = 2 m; no se busca a más de `distanciaMaxMetros` = 6 m), pide `ciclosPared` ciclos seguidos del otro lado, en cualquier celda. Durante `ciclosParaDeshacer` = 11 ciclos (~2 s) después de cruzar, volver al lado de antes cuesta lo normal, y deshacer no abre otra ventana.
- `pantalla_naveg.dart`: se construye con `late final`, como `_restriccionZonas`. El uso pide 1 ciclo caminando y 3 parado del mismo lado (como antes), y 5 caminando (~0,9 s) y 11 parado (~2 s) a través de una pared. La regla de la pared corre solo con `restringirZonas` activo y el resolvedor listo. Se quitó la clase privada vieja (y su `ciclosParaConfirmar = 2`, que nadie usaba) y se actualizaron los comentarios.
- `test/histeresis_celda_test.dart` (nuevo): 12 casos (sin pared y con puerta cerca se confirma igual que antes, 5 y 11 ciclos a través de la pared, el conteo por lado con celdas de 0,5 m, la ventana para deshacer y su largo exacto). `flutter test`: 33 casos en verde. `flutter analyze`: los mismos 4 avisos de antes.

**Simulado:** de 13,8 a 1,6 cruces falsos por minuto, y de 0,23 a 0,03 recálculos por minuto. Costo: corregir una posición que quedó del lado equivocado a través de una pared tarda 0,9 s en vez de 0,18 s caminando (~0,2 s más hasta que la posición se asienta) y ~2 s en vez de 0,54 s parado. Los movimientos normales y las puertas no cambian.

**Sin tocar:** el estimador, `restriccion_zonas.dart`, `pathfinder.dart` y la `previa` de la restricción. Lo opcional que no se hizo: `previa` = celda confirmada (en la simulación reduce los cruces a la mitad).

**Pendiente:** probarlo en el teléfono caminando pegado a una pared angosta. El punto no debería pasar al otro lado ni recalcular la ruta, y del lado propio tiene que seguir sin demora. Si una corrección real se siente lenta, bajar a 3 y 8 ciclos (variante liviana). Seguimientos que la histéresis no resuelve: pegado a la pared y con mucho ruido, la posición sigue del lado equivocado entre el 8 y el 23 % del tiempo (es del estimador o de `RestriccionZonas`). Además, `_verificarLlegada` mide en línea recta (1,5 m) y puede anunciar la llegada a un lugar del otro lado de una pared.

### 2026-10-22: ajustes de navegación por edificio, solo en el admin

**Documentación modificada:** este `claude.md`.

**Pedido:** el usuario no tiene que poder cambiar los filtros. Los cambia el admin, por edificio. Los generales los cambia solo el desarrollador, por ahora desde la nube; cuando estén afinados pasan al código. Las preselecciones con estrellas se eliminan.

**Cambios (sin commit, sin probar en el teléfono):**
- `ajustes_navegacion.dart`: se quitaron las preselecciones. Tres capas (edificio → general → código), cada una solo con lo cambiado. `porEdificio` en cada parámetro: atraso, ventanas de señal, filtros, empuje y velocidad máxima sí; umbral de caminata y anticipos no (dependen del teléfono o de la persona). Lo de la nube no pisa cambios locales sin subir (`pendientes`). Guardado en `shared_preferences` (`nav_ajustes_capas`).
- `supabase_service.dart`: `sincronizarAjustesNavegacion` (sube lo pendiente y baja general y edificio), `subirAjustesNavegacion` y `esDesarrollador` (rol en el `app_metadata`). `descargarMapa` baja también los ajustes del edificio.
- `supabase/ajustes_navegacion.sql` (nuevo): tabla `ajustes_navegacion` (id `general` o `edificio:<nombre>`, `valores` JSONB). La lee cualquiera; un edificio lo escribe el admin que publicó algún piso de ese edificio (o el desarrollador); los generales, solo el desarrollador. Incluye el `update` para darle el rol a un email.
- `panel_ajustes_navegacion.dart`: reescrito. Alcance "Este edificio" o "General", origen de cada valor, "Volver al valor general" o "al del código", estado de la subida y "Señal ahora".
- `pantalla_naveg.dart`: al abrir usa los ajustes guardados del edificio y consulta la nube aparte (8 s de límite). El botón del panel solo aparece con `EntornoApp.esAdmin`.
- `lista_pisos.dart`: botón "Probar navegación" en cada piso (admin).
- `entorno_app.dart` (nuevo) y `main_admin.dart`: `EntornoApp.esAdmin = true`.
- `test/ajustes_navegacion_test.dart` (nuevo): 10 casos.
- **Arreglo, rol de desarrollador:** la app del admin reusa la sesión guardada al abrirse, y el rol viaja en el usuario y el token de esa sesión, así que un rol dado después de iniciar sesión no se veía (ni la nube lo aceptaba) hasta renovar el token. Ahora el panel renueva la sesión al abrirse (`SupabaseService.actualizarSesion`) y muestra el email y el rol. El desarrollador arranca en "General"; en "Este edificio", el umbral de caminata y los anticipos siguen bloqueados a propósito (se cambian en "General").
- **Se sacó el rol de desarrollador** (no andaba con el email, a pedido del usuario): `esDesarrollador`, `actualizarSesion` y la línea de usuario del panel. Los dos alcances quedan para cualquier admin y la nube deja escribir generales y edificios a cualquier admin logueado (el SQL nuevo borra las políticas viejas). En "Este edificio" el umbral de caminata y los anticipos siguen bloqueados; se cambian en "General". Cuando estén calibrados, los valores pasan al código.
- **Arreglo, selector de alcance ilegible:** la hoja del panel tomaba el tema claro de `MaterialApp` (se abre con el contexto de la pantalla, que está por encima de su `Theme(TemaApp.tema)`), y los textos "Este edificio" / "General" salían oscuros sobre fondo oscuro. Ahora el panel se envuelve en `TemaApp.tema`.
- **Arreglo, mapa corrido al abrir la navegación:** al llegar la primera posición la cámara iba a zoom 1, pero en un piso chico el plano se agranda hasta llenar la pantalla y el recuadro del mapa es más chico: quedaba recortado y corrido hacia un costado. Ahora la escala base es 28 px/m, salvo que a esa escala el plano entre entero en el recuadro: ahí se muestra entero y centrado (`_zoomEscalaBase` en `pantalla_naveg.dart`). En pisos grandes no cambia: cerca de un borde la vista sigue sin mostrar afuera del plano, así que el usuario puede quedar corrido del centro.

**Pendiente:** lo indicado en "Próximos pasos" y "Pendientes conocidos" del Estado actual.

### 2026-10-22: paredes finas en el editor de zonas

**Documentación modificada:** este `claude.md`.

**Problema:** no se podía dibujar una pared fina (por ejemplo, de 20 cm). Con el imán prendido se aplastaba, y sin el imán todo quedaba torcido. No eran los ángulos. Había tres medidas fijas en el plano que no achicaban con el zoom: (1) tocar a menos de 0,05 del plano normalizado de un vértice (unos 2 m en un plano de 40 m) lo agarraba en vez de crear otro; (2) la guía de cierre alineaba con el primer vértice todo lo que estuviera a menos de 40 cm, y el tercer vértice de la pared caía sobre la línea del primero; (3) el zoom tenía un tope de 2,5× (unos 24 px por metro en un plano de 40 m).

**Cambios (sin commit, sin probar en el teléfono):**
- `asistente_trazo.dart`: parámetro `metrosPorPixel`. Alineación 12 px y largo mínimo 14 px en pantalla, con tope en los 40 cm y 20 cm de siempre (sin zoom anda igual que antes).
- `pantalla_config.dart`: `TransformationController` en el mapa de edición. Zoom máximo según el plano, hasta 200 px por metro (una pared de 20 cm mide 40 px). El agarre de vértices y de puntos de escala se mide en píxeles (22 px, con tope en el radio de siempre). Pasa `metrosPorPixel` al asistente y `escalaVista` al mapa.
- `mapa_widget.dart`: parámetro `escalaVista` (por defecto 1, así la navegación no cambia). Con zoom, la grilla, los bordes de zonas, el polígono en curso, las manijas de vértices, la medición de escala, las guías y los marcadores de beacons y lugares miden lo mismo en pantalla. Las escaleras siguen a escala real.
- `test/asistente_trazo_test.dart` (nuevo): 5 casos.

**Sin tocar:** el agarre de beacons y lugares (usa el marcador tocado y un radio en el plano).

**Pendiente:** probar en el teléfono que se pueda acercar, dibujar una pared de 10 a 20 cm recta y con ancho, y que con poco zoom el imán y el agarre se sientan como antes.

### 2026-10-22: filtros de BlindRoute en el visualizador de beacons

**Documentación modificada:** este `claude.md` (también se corrigió el Estado actual: lo del 2026-10-22 ya estaba commiteado).

**Pedido:** aplicar todos los filtros de BlindRoute en el visualizador de beacons (`rssi_monitor`, otro proyecto Flutter en `C:\Users\Juani\Downloads\rssi_monitor`, sin git) para ver cómo cambian el valor que percibe la app. **El código de BlindRoute no se tocó.**

**Cambios en rssi_monitor (sin probar en el teléfono):**
- `lib/blindroute_filter.dart` (nuevo): copia de los filtros, con el reloj de la serie. Por beacon: rango −110 a −20 dBm, mediana truncada con ventana de tiempo según el movimiento, decaimiento de 8 dB/s después de 1 s sin lecturas, umbral de −90 dBm y modelo log-distancia. Sobre la distancia a ese beacon, que es una aproximación en 1D de lo que en BlindRoute es 2D: ancla del `Posicionador` (forma cerrada con Huber), One Euro, tope de velocidad, zona muerta y fase de adquisición. El acelerómetro usa `sensors_plus` 6.1.2, como `DetectorMovimiento`. Los ajustes tienen los rangos y los `porDefecto` de `AjustesNavegacion`; al cambiarlos se recalcula todo lo guardado, aun en pausa. Al reanudar una pausa, los filtros arrancan de cero.
- `lib/filter_view.dart` (nuevo): vista "Filtros" con el valor a la salida de cada etapa y el atraso aproximado, más la hoja de ajustes (también se abre desde la barra superior).
- `rssi_chart.dart`: línea violeta de BlindRoute, umbral de −90 y modo en metros (eje logarítmico: crudo, medida y percibida). `proximity_view.dart`: círculo de la distancia percibida. `chart_page.dart`: tercera vista, fila de estadísticas de BlindRoute y leyenda que oculta líneas. `rssi_series.dart`: guarda las pausas. `pubspec.yaml`: `sensors_plus`.

**Verificado:** con tests temporales (borrados) contra copias de los archivos de BlindRoute, la mediana truncada y el One Euro dan idénticos. El ancla coincide con `Posicionador.estimar`: 0,3 mm parado y hasta 3,6 cm en un salto de 20 m caminando, porque con un beacon lejano el solver corta a las 12 iteraciones antes de llegar al mínimo. La pantalla se arma sin desbordes en 360×780 dp. `flutter analyze` no da avisos y el APK de debug compila.

**Hallazgos del análisis:**
- Las ventanas regulables (2,0 y 0,8 s) rigen sólo en la navegación. `pantalla_config.dart` (RSSI en vivo del admin) y `modo_automatico.dart` usan los valores internos del `ProcesadorSenal`: 3,0 s fijos, que nunca se acortan.
- Atraso aproximado con los valores del código: parado ≈ 3,6 s (1,0 de la mediana, 0,6 del ancla y 2,0 del One Euro); caminando ≈ 0,9 s (0,4 + 0,1 + 0,35), coherente con los 0,8 s del "Atraso de la posición".

**Pendiente:** probar el visualizador en el teléfono, parado y caminando, comparando la línea violeta con el crudo.

### 2026-10-26: "Ubicación lista" y textos del admin

**Documentación modificada:** este `claude.md`.

**Problema 1:** al abrir la navegación se decía "Buscando ubicación" pero nunca "Ubicación lista", aunque la posición aparecía. "Ubicación lista." se mandaba con `hablarSinEsperar`, que descarta la frase si el motor de voz está hablando, y se intentaba una sola vez, en el ciclo de la primera posición. Esa posición llega mientras todavía suena "Buscando ubicación." (enseguida si se viene del modo automático, que deja el scan andando; y la primera vez que se abre la app el motor de voz tarda más en arrancar), así que el aviso se perdía.

**Cambios (commiteados; el usuario lo probó en el teléfono y anduvo):**
- `pantalla_naveg.dart`: `_anuncioUbicacionPendiente` y `_anunciarUbicacionLista()`. El aviso queda pendiente desde la primera posición y se reintenta en cada ciclo hasta que el motor lo acepta, antes de las indicaciones (si las dos esperan, sale primero "Ubicación lista."). Espera si hay un pedido de destino en curso o el micrófono abierto. Tras un salto de piso con destino no se dice aparte: lo dice `_calcularRuta` en "Ubicación lista. Vamos a…" (antes la frase suelta quedaba cortada por esa); si no hay escalera, se dice suelta.

**Problema 2:** los textos de ayuda del admin eran demasiado explicativos para gente que sabe del tema.

**Cambios (commiteados):** se acortaron los textos sin sacar la explicación, sólo lo que sobraba.
- `ajustes_navegacion.dart`: la `ayuda` de cada parámetro, con la regla concreta de cuándo subirlo o bajarlo.
- `panel_ajustes_navegacion.dart`: alcances, errores de la nube, señal, pista de "Seguimiento de la posición", interruptores de prueba (títulos "Freno lateral por brújula" y "Sacar la posición de zonas prohibidas") y origen de cada valor. Se mantuvo el texto del freno lateral que ya había acortado el usuario.
- `pantalla_config.dart`: pistas de cada modo (beacons, zonas, lugares, escala, calibración, brújula), modo borrar, diálogos de la escala, avisos de calibración y de punto clave, pasos y precisión de la brújula, ayudas del rubro, de las otras palabras y de la entrada de escaleras y ascensores.
- `pantalla_rubros.dart`: textos de ayuda y avisos.

**Sin tocar:** lo que escucha el usuario por voz, los textos de la app del usuario y los mensajes del log.

**Verificado:** `flutter analyze` con los mismos 4 avisos de antes y `flutter test` con 48 casos en verde.

**Pendiente:** revisar si algún texto del admin quedó demasiado corto.

### 2026-10-26: orientación hacia el lugar al llegar

**Documentación modificada:** este `claude.md`.

**Problema:** la llegada se anuncia a 1,5 m, y muchas veces el lugar queda al costado (la ruta dobla justo antes, o termina en el pasillo con la puerta a un lado). "Llegaste a X" no decía hacia dónde estaba la entrada.

**Cambios (sin commit, sin probar en el teléfono):**
- `orientador_llegada.dart` (nuevo): `OrientadorLlegada`, lógica pura. Con el rumbo objetivo fijo desde la llegada: si ya está de frente (±30°) termina enseguida; si no, dice hacia dónde girar ("Girá a la izquierda", "Girá un poco a la derecha" con menos de 60°, "Date la vuelta" desde 150°). Mientras gira (más de 30°/s) no habla. Quieto sin estar de frente 0,8 s, corrige (2,5 s entre indicaciones distintas, 5 s para repetir la misma). De frente y quieto 0,6 s → listo. A los 15 s se vence. El rumbo no se recalcula porque, girando en el lugar, el cuerpo tapa beacons y la posición se mueve.
- `orientacion_service.dart`: `rumboHacia()` (lo usa `calcularIndicacion`) y `diferenciaAngular()` pasa a ser pública.
- `pantalla_naveg.dart`: al detectar la llegada (destino final o escalera del tramo) se corta la guía como antes, pero en vez de anunciar arranca la orientación: "Estás llegando a Baño. Girá a la izquierda." Al quedar de frente: "Llegaste a Baño. Está adelante." En la escalera: "Escalera. Está adelante. Subí al piso 2 y mantené la pantalla apretada." (antes decía el giro una sola vez dentro de esa frase). Vencida, dice de qué lado quedó ("Está a tu izquierda"). Sin brújula, o con el lugar a menos de 0,5 m, se anuncia como antes. Rumbo: en escaleras y ascensores con entrada cargada, desde el punto de entrada hacia la boca; en el resto, desde la posición adelantada sobre la ruta lo que avanzó durante el atraso (`_posicionAlLlegar`) hacia el punto del lugar. Las correcciones usan `hablarSinEsperar` y se reintentan si el motor está ocupado; con un pedido de destino en curso se espera. Tarjeta propia mientras se orienta ("Girá a la izquierda" / "De frente", "Hacia Baño"), sin `liveRegion` para no pisar a la voz.
- `test/orientador_llegada_test.dart` (nuevo): 12 casos.

**Sin tocar:** el radio de llegada (1,5 m) ni los 3 ciclos para confirmarla. Los lugares comunes no tienen dirección de entrada cargada: el rumbo va al punto del lugar.

**Pendiente:** probarlo en el teléfono (paso 7 del Estado actual). Si la brújula del lugar es mala, la orientación puede dar vueltas hasta los 15 s; ahí conviene subir la tolerancia (`toleranciaGrados`) o bajar el máximo.

### 2026-10-26: "Ubicación lista" con la posición asentada

**Documentación modificada:** este `claude.md`.

**Problema:** "Ubicación lista" salía con el primer fix, pero durante la fase de adquisición (3 s con el filtro rápido y 3 s de rampa) el punto salta unos segundos hasta acomodarse.

**Cambios (sin commit, sin probar en el teléfono):**
- `pantalla_naveg.dart`: `_actualizarAsentamiento` y `_ubicacionAsentada`. El aviso sigue pendiente desde el primer fix, pero se dice recién con la posición asentada: al terminar la adquisición (6 s) o antes, pasados los 3 s del tramo pleno, si el usuario está quieto (factor de movimiento ≤ 0,5) y la posición no se alejó más de 1 m de un mismo punto durante 1,5 s. Caminando se espera a los 6 s. Lo anota en el log (`[Posicionamiento] Ubicación asentada: …`).
- Saltos de piso: "Ubicación lista. Vamos a…" lleva el "Ubicación lista" sólo si la posición ya se asentó (`_tomarUbicacionLista`). Si no, dice "Vamos a…" y el aviso sale solo después. Se quitaron los casos especiales del salto en `_anunciarUbicacionLista`.

**Sin tocar:** la guía. Si se pide un destino antes de que se asiente, la ruta y la primera indicación salen igual con la posición del momento, y "Ubicación lista" puede llegar después de esa indicación.

**Pendiente:** probarlo en el teléfono (paso 8 del Estado actual). Si tarda demasiado parado, bajar `_ventanaAsentamiento`; si igual salta después del aviso, subirla o esperar siempre al final de la adquisición.

### 2026-10-26: palabras cortas en el reconocimiento de voz

**Documentación modificada:** este `claude.md`.

**Causas encontradas:**
1. El micrófono se abría tarde. Después de la pregunta había 200 ms en la pantalla, otros 200 ms en `VozService.escuchar` y, en cada escucha, la consulta de idiomas al servicio de voz de Android (`_stt.locales()`, un broadcast de ida y vuelta que puede tardar cientos de ms), todo con la pantalla ya diciendo "Escuchando". Un "sí" dicho enseguida se perdía entero; en una frase larga sólo el principio.
2. Se usaba sólo la interpretación más probable. El plugin (speech_to_text 7.3.0, `EXTRA_MAX_RESULTS` = 10) devuelve hasta 10, y con palabras cortas la correcta muchas veces no es la primera.
3. La búsqueda de respaldo de destinos (`_buscarMejorCoincidencia`) aceptaba un lugar si su nombre CONTENÍA lo reconocido: "a", "e" o "va" coincidían con casi cualquiera y se iba a un lugar al azar sin preguntar. Un texto vacío coincidía con el primer lugar.

**Cambios (sin commit, sin probar en el teléfono):**
- `voz_service.dart`: el locale se averigua una vez, apenas se inicializa el reconocedor (`_localeEspanol`). `escuchar` recibe `entiende` y entrega la primera interpretación que el que pregunta sabe interpretar (si ninguna, la más probable). Log `[Voz] Entendido`.
- `pantalla_naveg.dart`: sin la espera de 200 ms de la pantalla (queda la de `VozService`). Cada pregunta pasa su `entiende`: sí/no, nombre u orden de una opción, "cualquiera", cancelar, género del baño, y en el pedido de destino, que nombre algún lugar (`BuscadorLugares.candidatos`) o un baño. Helper `_dice`. La búsqueda por contención pide 3 letras o más.

**Sin tocar (opciones para probar después):** el modelo de lenguaje del reconocedor. Hoy es dictado (`ListenMode.confirmation` → `LANGUAGE_MODEL_FREE_FORM`); `ListenMode.search` usa `LANGUAGE_MODEL_WEB_SEARCH`, pensado para frases cortas. Tampoco hay una vibración cuando el micrófono se abre de verdad, que ayudaría a saber cuándo hablar.

### 2026-10-26: parámetros fijos que se podrían regular

Relevamiento a pedido del usuario (sin cambios de código). Además de los filtros del panel, los de más impacto probable:
- **Instalación:** potencia de los beacons, altura (~2 m), que en cada punto se vean al menos 3, no ponerlos alineados ni sobre metal. Es lo que más pesa en la precisión.
- **Qué beacons entran al cálculo** (`pantalla_naveg.dart`): `_umbralRSSI` = −90 dBm (≈ 20 m con el modelo por defecto), `_maxBeaconsParaCalcular` = 6, `_minBeaconsActivos` = 2. Dependen de la densidad: candidatos a "por edificio".
- **Modelo por defecto** (`procesador_senal.dart`): `_txPower` −55 dBm y `_pathLossExponent` 2,7, para los beacons sin 3 calibraciones a distancias distintas.
- **Puntos clave** (`pantalla_naveg.dart`): `_fpGananciaMax` 0,35, `_fpRadioMaxMetros` 4, `_fpCiclosParaAplicar` 3. Con buenos puntos clave en las esquinas, subir la ganancia afina justo donde se dobla.
- **Indicaciones por voz** (`voz_service.dart`): `_confirmacionesNecesarias` 4 y `_estabilidadMinima` 1,8 s (anti-rebote, suma atraso a las indicaciones no anticipadas), `_intervaloMinimo` 15 s, velocidad del TTS 0,48 (una voz más rápida acorta cada indicación; es preferencia de la persona).
- **Llegada y recálculo** (`pantalla_naveg.dart`, `seguidor_ruta.dart`): `_radioLlegadaMetros` 1,5, `_ciclosParaLlegada` 3, `_tiempoFueraDeRuta` 1,5 s, `_desvioReplanInmediatoMetros` 3, `toleranciaEnRutaMetros` 0,75.
- **Rutas** (`pathfinder.dart`): `margenBordeMetros` 1, `costoMaxBorde` 2, `amortiguacionZonaMetros` 1 y `costoMaxZona` 0,6 deciden cuánto se aleja la ruta de las paredes (hay personas ciegas que prefieren ir pegadas a la pared).
- **Movimiento y adquisición:** `umbralQuieto` 0,25 y `_esperaQuietoMs` 800 (`detector_movimiento.dart`), adquisición 3 + 3 s, `_zonaMuertaQuietoMetros` 0,35.
- **Modo automático** (`modo_automatico.dart`): `_ventanaEleccionPiso` 3 s, `_margenPisoDb` 4, `_beaconsPorPiso` 3. Un piso mal elegido es de los errores más caros.
- **Calibración** (`pantalla_config.dart`): 10 s por toma y 25 s por punto clave. Las ventanas del admin y del modo automático siguen fijas en 3,0 / 1,1 s (`ProcesadorSenal`), no usan las del panel.

### 2026-10-26: puntos clave que no corregían y ajustes de voz del usuario

**Documentación modificada:** este `claude.md`.

**Referencia del usuario:** video del visualizador (rssi_monitor) con el beacon Holy-IOT-B1 quieto a ~45 cm. Crudo de −64 a −35 dBm, desviación ~3,2 dB, 5,2 lecturas/s; el filtro de BlindRoute baja la desviación a ~1,9 dB, pero la distancia percibida igual salta entre ~35 y 60 cm.

**Problema 1:** parado exactamente en un punto clave, la posición seguía en otro lado. Causas:
1. La corrección corría la posición medida un 35 % × confianza hacia el punto clave en cada ciclo, pero el ciclo siguiente la multilateración vuelve a calcular desde las lecturas (con el ancla a la posición anterior: 3 veces el peso de los rangos parado, 0,25 caminando). La posición quedaba a mitad de camino: en una cuenta aproximada, 55-70 % de la distancia parado y 27-40 % caminando.
2. Un solo ciclo sin coincidencia (ambiguo, por encima de 10 dB, o el rumbo cruzando el límite) reiniciaba todo, y con el ruido de los beacons pasaba seguido.
3. Un punto clave sólo contaba mirando a ±45° de como se tomó: parado ahí mirando para otro lado, no se usaba.
4. El radio de 4 m se medía desde la multilateración del ciclo: si seguía errada en más de 4 m, la corrección se soltaba sola.

**Cambios (sin commit, sin probar en el teléfono):**
- `pantalla_naveg.dart`: peso acumulado (`_fpPeso`) que sube hacia la confianza a 0,35 por ciclo mientras coincide y baja igual cuando deja de coincidir; la posición medida se corre ese peso hacia la celda (`_fpObjetivo`). Parado llega al 90 % o más. Se toleran 4 ciclos sin coincidencia (`_fpCiclosGracia`) antes de soltar el punto clave. El radio se mide desde la posición filtrada anterior. "Estás en X" se da por dicho sólo si el motor lo aceptó (antes se perdía si la voz estaba ocupada). Log `[Fingerprint]` cada ~2 s.
- `procesador_senal.dart`: tolerancia de rumbo de 45° a 90°. `compararFingerprints` acepta `diagnostico` (una línea por punto clave para el log).

**Sin tocar:** la métrica (diferencial y robusta), los umbrales de 4 y 10 dB, el margen de 2 dB y la toma en el admin (25 s, mediana truncada). Si con esto todavía no alcanza, lo siguiente es promediar más el vector vivo estando quieto o subir los umbrales en dB.

**Problema 2:** velocidad, volumen y demás de la voz son gustos de cada persona, y no se podían cambiar.

**Cambios (sin commit, sin probar en el teléfono):**
- `ajustes_voz.dart` (nuevo): `AjustesVoz` con velocidad (60-200 %, 100 % = la 0,48 de siempre), volumen (20-100 %), tono (70-140 %) y "repetir la indicación cada" (5-40 s, antes 15 s fijos). Reusa `ParametroAjuste`.
- `voz_service.dart`: carga y aplica los ajustes al inicializarse (`aplicarAjustes()`); `_intervaloMinimo` sale de `AjustesVoz`.
- `pantalla_ajustes_voz.dart` (nuevo) y `pantalla_princ_usuario.dart`: botón "Ajustes de voz" (el de "Mapas disponibles" pasó al helper `_botonSecundario`). Controles para lector de pantalla; 0,7 s después del último cambio guarda y dice "Así suena la voz."; "Probar la voz" y "Volver a los valores de fábrica".
- `test/ajustes_voz_test.dart` (nuevo): 3 casos.

**Sin tocar:** los anticipos del giro y del aviso, que también dependen de la persona pero hoy son ajustes generales del admin. Se podrían pasar a esta pantalla.

**Probado por el usuario:** los puntos clave y los ajustes de voz ("mejoró bastante").

**Arreglo, la frase de prueba salía en otro idioma** ("ashi suena la voiz"): `VozService._inicializarTTS` fijaba es-AR con el motor de voz todavía arrancando. flutter_tts (Android) guarda esas llamadas, las ejecuta al terminar de arrancar y después pone el idioma de la voz por defecto del teléfono, así que el es-AR quedaba pisado. Pasaba con la inicialización del inicio de la app del usuario; la navegación vuelve a inicializar con el motor listo, y por eso ahí se escuchaba bien (el modo automático, que habla antes que la navegación, probablemente también salía con la voz del teléfono). Ahora primero se hace una consulta que entra en esa cola (`isLanguageAvailable`) y recién cuando vuelve se fija el idioma; si el motor no lo acepta queda en el log (`[Voz] El motor de voz no aceptó es-AR`). Commiteado, sin probar.

**Pendiente:** pasos 10 y 11 del Estado actual, y escuchar la frase de prueba de los ajustes de voz recién abierta la app.
