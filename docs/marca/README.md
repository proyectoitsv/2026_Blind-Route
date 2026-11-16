# BlindRoute · brand kit

Versión definitiva del brand board: fondo `#0B1020`, acento `#29D9FF`, logotipo en Atkinson Hyperlegible Bold con el punto de la i en el acento.

## Qué hay en cada carpeta

| Carpeta | Contenido |
|---|---|
| `1_logo/combinado` | Logo horizontal (símbolo + nombre) en PNG transparente de 2507 × 744: para fondo oscuro, para fondo claro, monocromo blanco y monocromo oscuro. |
| `1_logo/simbolo` | El símbolo solo, 622 × 600. El original y tres versiones: claro en azules, monocromo blanco y monocromo oscuro. |
| `1_logo/logotipo` | El nombre solo en SVG (vector), en las mismas cuatro versiones. |
| `2_icono` | El ícono de la app (192 px) y la capa monocroma para Android 13. |
| `3_color` | Colores en CSS y JSON con sus contrastes, y el degradado del logo en SVG. |
| `4_tipografia` | Atkinson Hyperlegible Regular y Bold (logotipo), con su licencia OFL. Inter (interfaz) no se copia acá: es la misma que usa la app y está en `assets/fonts/Inter/`. |
| `5_aplicaciones` | Gráfico de tienda de 1024 × 500 y la pantalla de navegación. |
| `brand_board_BlindRoute.png` | La lámina completa, 3840 × 2160. |

## Cuál logo usar

- **Sobre fondo oscuro:** `para_fondo_oscuro`. Es el principal.
- **Sobre fondo claro:** `para_fondo_claro`. El símbolo va en los azules del logo y el punto de la i en `#0A68FF`, porque el cian sobre blanco no llega al contraste mínimo.
- **Un solo color** (sellos, impresión en una tinta): `monocromo_blanco` sobre oscuro, `monocromo_oscuro` sobre claro.
- **Sobre fotos o fondos de color:** el logo para fondo oscuro, dentro de la baldosa `#010317`.

Los archivos que dicen **derivada** salen del PNG original: tienen exactamente la misma forma y sólo cambia el color.

## Reglas

- El degradado del logo es sólo gráfico: nunca va en la interfaz ni en texto.
- En la interfaz, el único acento es el cian `#29D9FF`. El verde `#3DF5B0` sólo marca el tramo recorrido y el destino.
- Contraste mínimo: 4,5:1 en texto, 7:1 en lo importante y 3:1 en íconos y bordes.

## Límites conocidos

- El símbolo y el ícono son imágenes, no vectores. No se agrandaron: el símbolo llega a 622 × 600 y el ícono a 192 px. Para el ícono de tienda de 512 px o para impresión grande hace falta redibujarlo en vector.
- Los archivos de Atkinson Hyperlegible traen sólo los caracteres latinos básicos, que alcanzan para el español. La familia completa está en Google Fonts.
