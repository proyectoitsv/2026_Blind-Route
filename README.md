<p align="center">
  <img src="docs/estetica/fase-1-icono.png" width="140" alt="Logo de BlindRoute: un pin azul y un camino que va de azul a verde, sobre un fondo oscuro.">
</p>

<h1 align="center">BlindRoute</h1>

<p align="center">
  Navegación por voz dentro de edificios para personas con discapacidad visual.<br>
  <strong>Te dice por dónde ir, paso a paso, donde el GPS no llega.</strong>
</p>

<p align="center">
  <img alt="Android 7.0 o superior" src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white">
  <img alt="iOS: todavía no" src="https://img.shields.io/badge/iOS-todav%C3%ADa%20no-8A8F98?logo=apple&logoColor=white">
  <img alt="Flutter 3.41" src="https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white">
  <img alt="Dart 3.11" src="https://img.shields.io/badge/Dart-3.11-0175C2?logo=dart&logoColor=white">
  <img alt="Compatible con TalkBack" src="https://img.shields.io/badge/accesible-TalkBack-29D9FF">
</p>

<p align="center">
  <img src="docs/estetica/fase-5.7-guiando.jpg" width="260" alt="Pantalla de navegación con la indicación Seguí derecho, 11 metros, la ruta sobre el plano y la posición de la persona.">
</p>

---

## Índice

- [Qué es](#qué-es)
- [Cómo funciona](#cómo-funciona)
- [Las dos apps](#las-dos-apps)
- [Capturas](#capturas)
- [Qué hace hoy](#qué-hace-hoy)
- [Compatibilidad](#compatibilidad)
- [Estado del proyecto](#estado-del-proyecto)
- [Cómo compilar e instalar](#cómo-compilar-e-instalar)
- [Estructura del código](#estructura-del-código)
- [Tecnologías](#tecnologías)
- [Datos y privacidad](#datos-y-privacidad)
- [Más documentación](#más-documentación)

## Qué es

Moverse solo por un edificio que no se conoce, como una facultad, un hospital o un shopping, es difícil para una persona ciega o con baja visión, y el GPS del teléfono no sirve bajo techo. **BlindRoute** resuelve eso: la persona dice a dónde quiere ir y la app la guía **por voz**, con indicaciones como "Girá a la izquierda" o "Seguí derecho", hasta dejarla frente al lugar.

La app está pensada para usarse **sin mirar la pantalla**: se toca en cualquier parte para hablar, todo lo importante se dice en voz alta y funciona con TalkBack, el lector de pantalla de Android.

## Cómo funciona

Antes de usarla, el edificio se prepara una sola vez: se colocan **beacons**, unos dispositivos chicos que emiten una señal Bluetooth, y se carga su plano en la app del administrador. Después, cada vez que alguien navega, pasa esto:

| | Qué pasa | Con qué |
|:---:|---|---|
| 1 | El teléfono escucha los beacons cercanos y estima **dónde estás** dentro del plano. | Bluetooth |
| 2 | Decís **a dónde querés ir**, por nombre o por tipo de lugar ("baño", "quiero comer"). | Micrófono |
| 3 | La app calcula el **camino** esquivando paredes y zonas por donde no se puede pasar. | Plano del edificio |
| 4 | Te **guía por voz**, sabiendo hacia dónde estás mirando, y corrige si te desviás. | Voz y brújula |
| 5 | Al llegar, te hace **girar hasta quedar de frente** al lugar y te avisa. | Brújula |

## Las dos apps

Del mismo código salen dos aplicaciones, que se instalan por separado:

| App | Para quién | Para qué |
|---|---|---|
| **BlindRoute** | La persona que navega | Descargar los mapas publicados y moverse por el edificio |
| **BlindRoute Admin** | Quien prepara el edificio | Cargar edificios, pisos, beacons, zonas y lugares, calibrar la señal y publicar los mapas |

## Capturas

Generadas en la computadora con datos y planos de ejemplo.

**App del usuario**

<table>
  <tr>
    <td align="center"><img src="docs/estetica/fase-5.7-ficha.jpg" width="190" alt="Inicio con la ficha Comenzar a navegar y las opciones Mapas disponibles y Ajustes."><br><sub>Inicio</sub></td>
    <td align="center"><img src="docs/estetica/fase-5.7-lista-destinos.jpg" width="190" alt="Hoja con la pregunta A dónde querés ir y la lista de lugares."><br><sub>Elegir destino</sub></td>
    <td align="center"><img src="docs/estetica/fase-5.7-llegaste.jpg" width="190" alt="Navegación con el aviso Llegaste y los tramos recorridos en verde."><br><sub>Llegada</sub></td>
    <td align="center"><img src="docs/estetica/fase-5.2-descargando.jpg" width="190" alt="Catálogo de mapas disponibles, con un mapa descargándose."><br><sub>Mapas disponibles</sub></td>
  </tr>
</table>

**App del administrador**

<table>
  <tr>
    <td align="center"><img src="docs/estetica/fase-5.4-edificios.jpg" width="190" alt="Lista de edificios con el botón Agregar edificio."><br><sub>Edificios</sub></td>
    <td align="center"><img src="docs/estetica/fase-5.4-pisos.jpg" width="190" alt="Lista de pisos de un edificio, con botones para probar la navegación, cambiar el número y eliminar."><br><sub>Pisos</sub></td>
    <td align="center"><img src="docs/estetica/fase-5.7-panel-admin.jpg" width="190" alt="Panel de ajustes de navegación con deslizadores."><br><sub>Ajustes de navegación</sub></td>
  </tr>
</table>

**Con la letra al 200 %**

<table>
  <tr>
    <td align="center"><img src="docs/estetica/fase-5.7-guiando-200.jpg" width="190" alt="Navegación con la letra al 200 %, con la indicación en primer lugar."><br><sub>Navegación</sub></td>
    <td align="center"><img src="docs/estetica/fase-5.2-catalogo-200.jpg" width="190" alt="Catálogo de mapas con la letra al 200 %."><br><sub>Mapas disponibles</sub></td>
  </tr>
</table>

## Qué hace hoy

**Para la persona que navega**

- **Encuentra sola el edificio y el piso** a partir de los beacons que escucha.
- **Destino por voz:** se toca cualquier parte de la pantalla y se dice el nombre o el tipo de lugar. También se puede elegir de una lista.
- **Indicaciones habladas** que se anticipan a cada esquina, y una ruta nueva si te pasás o tomás otro pasillo.
- **Varios pisos:** te lleva hasta la escalera o el ascensor, y manteniendo apretada la pantalla se cambia de piso.
- **Orientación al llegar:** te indica para dónde girar hasta quedar de frente al lugar.
- **Mapas disponibles:** se descargan, actualizan o quitan desde un catálogo.
- **A tu gusto:** velocidad, volumen, tono y repetición de la voz, vibración y "Reducir movimiento".

**Para quien prepara el edificio**

- Edificios y pisos, con la imagen del plano y su escala en metros.
- Ubicación de los **beacons**, **zonas** por donde no se puede pasar y **lugares** (aulas, baños, escaleras, ascensores) con palabras para encontrarlos.
- **Calibración** de la señal y **puntos clave** para afinar la posición en lugares puntuales.
- **Publicación en la nube**, para que los mapas le lleguen a la app del usuario.
- Panel para regular la navegación caminando, por edificio o en general.

**Accesibilidad**

- Funciona con **TalkBack**, con etiquetas en español en los controles propios.
- La pantalla se puede usar con **letra al 200 %** sin que se corten los textos importantes.
- Contraste calculado para cada color y áreas táctiles de al menos **48 dp**.
- Respeta "Quitar animaciones" del teléfono.

## Compatibilidad

| Plataforma | Estado |
|---|---|
| **Android** | ✅ Desde **Android 7.0** (API 24), compilada para **Android 16** (API 36). Se prueba en un Samsung Galaxy S24 Ultra. |
| **iOS** | ⏳ **Todavía no.** Existe la carpeta `ios/` que crea Flutter (iOS 13 o superior), pero faltan los permisos de Bluetooth y micrófono, y las dos apps están armadas solamente para Android. |

Para navegar hacen falta un teléfono con **Bluetooth y brújula**, y un edificio con **beacons instalados** y su mapa publicado.

| Permiso | Para qué se usa |
|---|---|
| Bluetooth | Escuchar los beacons |
| Ubicación | Android la exige para buscar dispositivos Bluetooth |
| Micrófono | Decir el destino |
| Fotos | Elegir la imagen del plano (administrador) |
| Internet | Bajar y publicar mapas |
| Vibración | Avisos al doblar y al llegar |

## Estado del proyecto

El proyecto está en desarrollo y todavía se está calibrando en el teléfono.

| Parte | Estado |
|---|:---:|
| Posicionamiento, rutas y guía por voz | 🔄 |
| App del administrador y publicación en la nube | ✅ |
| Rediseño visual (rama `estética`) | ✅ |
| Prueba en el teléfono de las pantallas rediseñadas | ⏳ |
| Versión para iOS | ⏳ |

✅ hecho · 🔄 en ajuste · ⏳ pendiente. El rediseño se explica en [`docs/ESTETICA.md`](docs/ESTETICA.md).

## Cómo compilar e instalar

### Requisitos

- **Flutter 3.41** (Dart 3.11) y el SDK de Android.
- Un teléfono Android con la **depuración USB** activada.

### Correr las apps

```bash
flutter pub get
```

```bash
flutter run --flavor user -t lib/main_user.dart
```

```bash
flutter run --flavor admin -t lib/main_admin.dart
```

### Generar un APK e instalarlo

```bash
flutter build apk --debug --flavor user -t lib/main_user.dart
```

```bash
adb install -r build/app/outputs/flutter-apk/app-user-debug.apk
```

Conviene instalar con `adb install -r` y no con `flutter install`, que puede desinstalar la app y borrar sus datos. Para la del administrador, se cambia `user` por `admin`.

### Tests y galería de componentes

```bash
flutter test
```

```bash
flutter run --flavor user -t lib/main_galeria.dart
```

La galería muestra todos los componentes visuales. Se instala en lugar de la app del usuario, y se vuelve con el comando de arriba.

## Estructura del código

Todo está en `lib/`, y las dos apps comparten casi todo:

| Dónde | Qué hay |
|---|---|
| `main_user.dart`, `main_admin.dart` | El punto de entrada de cada app |
| `pantalla_*.dart`, `vista_navegacion.dart`, `mapa_widget.dart` | Pantallas y dibujo del plano |
| `design/` | Sistema de diseño: colores, letra, formas, movimiento y componentes |
| `bluetooth_helper.dart`, `procesador_senal.dart`, `posicionador.dart`, `filtro_un_euro.dart` | De la señal Bluetooth a la posición |
| `pathfinder.dart`, `grilla_nav.dart`, `seguidor_ruta.dart`, `orientador_llegada.dart` | Cálculo y seguimiento de la ruta |
| `voz_service.dart`, `buscador_lugares.dart` | Voz y búsqueda de lugares |
| `database.dart` | Base de datos del teléfono |
| `supabase_service.dart`, `supabase_config.dart` | Nube |

Los tests están en `test/` y el SQL de la nube, en `supabase/`.

## Tecnologías

| Área | Librería |
|---|---|
| Interfaz | Flutter, Material 3 y la fuente Inter |
| Bluetooth | `flutter_blue_plus` |
| Sensores | `flutter_compass`, `sensors_plus` |
| Voz | `flutter_tts`, `speech_to_text` |
| Datos en el teléfono | `sqflite`, `shared_preferences`, `path_provider` |
| Nube | `supabase_flutter` |
| Otros | `permission_handler`, `image_picker`, `wakelock_plus` |

## Datos y privacidad

- La **posición se calcula en el teléfono** y no se manda a la nube.
- La app del usuario **no pide cuenta**. Sólo el administrador inicia sesión, con email y contraseña.
- La nube guarda los **mapas publicados**, sus planos y los ajustes de navegación.
- La voz se reconoce con el **servicio de voz del teléfono**, y sólo cuando se pide un destino.

## Más documentación

| Archivo | Para qué sirve |
|---|---|
| [`docs/ESTETICA.md`](docs/ESTETICA.md) | Cómo quedó la parte visual, cómo se llegó y qué falta |
| [`supabase/ajustes_navegacion.sql`](supabase/ajustes_navegacion.sql) | Tabla y permisos de los ajustes en la nube |

---

<p align="center"><sub>Este repositorio no incluye una licencia de código abierto. La fuente Inter se distribuye bajo la licencia OFL.</sub></p>
