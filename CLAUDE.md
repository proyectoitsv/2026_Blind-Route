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
- Tests: `test/zonas_test.dart` (bloqueo por centro, paredes, snap y rutas que no cruzan zonas; 21 casos) `test/histeresis_celda_test.dart` (histéresis frente a paredes angostas; 12 casos) y `test/ajustes_navegacion_test.dart` (ajustes en capas; 10 casos). Se corren con `flutter test`. Fuera de eso, los tests de verificación de cada sesión se hacen en archivos temporales y se borran.

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
- `asistente_trazo.dart`: "imán" de ángulos (rectos y 45°) para trazar la escala y las zonas prohibidas.
- `ajustes_navegacion.dart`: parámetros de los giros anticipados (atraso, anticipos) y del seguimiento de la posición (umbral de caminata, ventanas de señal, filtro One Euro, velocidad máxima). El valor vigente sale de **tres capas**: lo cambiado en el edificio actual, lo cambiado en general y el valor del código. Cada capa guarda solo lo que se cambió en ella. Por edificio solo se cambian los que dependen del edificio (`porEdificio`); el umbral de caminata y los anticipos son solo generales. Se guardan en el teléfono (`shared_preferences`) y en la nube. Los interruptores de prueba (freno lateral por brújula, restringir zonas) viven solo en memoria.
- `panel_ajustes_navegacion.dart`: panel de ajustes, **solo en la app del admin**, en la pantalla de navegación. Alcances "Este edificio" y "General", los dos para cualquier admin mientras se calibra. Cada cambio rige al instante y se sube a la nube al soltar el control. Muestra el diagnóstico "Señal ahora".
- `entorno_app.dart`: `EntornoApp.esAdmin`, que fija `main_admin.dart`. Lo usa la pantalla de navegación para mostrar el panel solo en el admin.

**Voz**
- `voz_service.dart`: TTS y STT centralizados.
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

- Rama de trabajo: `app_doble`. Rama base: `main`. HEAD en `54d36f1`.
- Lo de las sesiones del 2026-10-19 y del 2026-10-21 está commiteado (`a600e8f`, `6c5cb19`, `54d36f1`). **Los ajustes de navegación por edificio (2026-10-22) están SIN commitear.** Nada de esas sesiones está probado en el teléfono. Detalle en el Registro.
- `flutter analyze` pasa, con 4 avisos de lint que ya existían (ninguno nuevo). `flutter test` pasa (43 casos).
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
7. Decidir con el usuario si se commitea lo pendiente (marcado "(no probado)").

**Pendientes conocidos:**
- Las calibraciones guardadas antes pueden tener valores inflados por lecturas repetidas. Conviene repetir las que se hicieron con beacons que se oían poco.
- Las preselecciones de fábrica tienen valores estimados. Si ninguna anda, el usuario va a crear la suya.
- Histéresis de celda frente a paredes angostas: implementada (`histeresis_celda.dart`), falta probarla en el teléfono. Ver el Registro del 2026-10-21.
- Cuando el usuario pase los valores calibrados, ponerlos en el código (`porDefecto`) y sacar de la app lo que ya no se tiene que poder cambiar: el alcance "General" y, por edificio, todo lo que no dependa del edificio.
- Las preselecciones viejas quedan guardadas en los teléfonos (`nav_preselecciones`) sin usarse. Se pueden borrar más adelante.
- El A* no se mueve en diagonal. Las paredes ya están calculadas para las diagonales, pero habilitarlas obliga a revisar `seguidor_ruta.dart` (tramos rectos, giros de 90°, largo de la ruta).

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
