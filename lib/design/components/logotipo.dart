import 'package:flutter/material.dart';

import '../estilo.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Logotipo de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// El nombre dibujado como en el kit de marca
// (docs/marca/1_logo/logotipo/logotipo_para_fondo_oscuro.svg): las letras en
// texto principal (17,77 sobre el fondo) y el punto de la i en acento
// (11,23). Va en la barra del inicio, como el nombre de Instagram.
//
// ─── Por qué un CustomPaint ───
// Sin paquetes (nada de flutter_svg) y sin un PNG, que perdería nitidez: los
// trazos del SVG están copiados acá tal cual y los lee un lector chico que
// sólo entiende los comandos absolutos que usa el kit (M, L, H, V, Q y Z) y
// falla con cualquier otro. Un test compara estos trazos con los del SVG.
//
// ─── Coordenadas ───
// El SVG tiene viewBox "0 -788.8 5129 820.8" y el grupo va con
// scale(1 -1): el punto (x, y) del trazo cae en (x, 788.8 − y) de la caja,
// que se escala a alto / 820.8.
//
// Quieto: no se anima ni depende de «Reducir movimiento». No crece con la
// letra del teléfono (es un dibujo). TalkBack no lo lee: quien lo usa le da
// el nombre (BarraSuperior.logotipo dice «Blind Route»).

/// El nombre de la app dibujado como en el kit de marca: las letras en
/// texto principal y el punto de la i en acento.
class LogotipoBlindRoute extends StatelessWidget {
  const LogotipoBlindRoute({super.key, this.alto = altoBarra});

  /// El alto de la caja; el ancho sale de la proporción del kit.
  final double alto;

  /// El alto en la barra del inicio.
  static const double altoBarra = 26;

  /// Ancho del viewBox del SVG.
  static const double anchoCaja = 5129;

  /// Alto del viewBox del SVG.
  static const double altoCaja = 820.8;

  /// Dónde empieza el viewBox (y = −788.8): el borde de arriba de la caja.
  static const double origenY = 788.8;

  /// Ancho por cada dp de alto (6,25).
  static const double proporcion = anchoCaja / altoCaja;

  /// El punto de la i: centro y radio, en coordenadas del SVG.
  @visibleForTesting
  static const Offset centroPunto = Offset(1121, 668);

  /// Radio del punto de la i, en coordenadas del SVG.
  @visibleForTesting
  static const double radioPunto = 100.8;

  /// Los 10 trazos de las letras, copiados del SVG del kit.
  @visibleForTesting
  static const List<String> trazos = [
    'M44.0 0.0V668.0H336.0Q409.0 668.0 466.0 653.5Q523.0 639.0 556.5 601.5Q590.0 564.0 590.0 494.0Q590.0 448.0 569.5 413.0Q549.0 378.0 511.0 355.0Q558.0 339.0 587.5 303.0Q617.0 267.0 617.0 206.0Q617.0 131.0 583.5 86.0Q550.0 41.0 489.0 20.5Q428.0 0.0 347.0 0.0ZM202.0 404.0H341.0Q381.0 404.0 403.5 422.5Q426.0 441.0 426.0 472.0Q426.0 504.0 403.5 521.5Q381.0 539.0 341.0 539.0H202.0ZM202.0 131.0H348.0Q399.0 131.0 424.5 151.5Q450.0 172.0 450.0 207.0Q450.0 242.0 424.5 262.0Q399.0 282.0 348.0 282.0H202.0Z',
    'M853.0 0.0Q792.0 0.0 756.0 10.5Q720.0 21.0 704.5 51.5Q689.0 82.0 689.0 140.0V668.0H841.0V180.0Q841.0 145.0 855.0 134.5Q869.0 124.0 907.0 124.0H950.0V0.0Z',
    'M1044.0 0.0V381.0H950.0V496.0H1197.0V0.0Z',
    'M1277.0 0.0V496.0H1410.0L1429.0 430.0Q1446.0 458.0 1485.5 484.0Q1525.0 510.0 1582.0 510.0Q1678.0 510.0 1713.5 456.5Q1749.0 403.0 1749.0 302.0V0.0H1597.0V264.0Q1597.0 299.0 1593.0 328.0Q1589.0 357.0 1573.5 374.5Q1558.0 392.0 1521.0 392.0Q1473.0 392.0 1451.0 357.5Q1429.0 323.0 1429.0 255.0V0.0Z',
    'M2034.0 -12.0Q1970.0 -12.0 1920.5 20.0Q1871.0 52.0 1843.0 111.5Q1815.0 171.0 1815.0 252.0Q1815.0 333.0 1843.0 390.5Q1871.0 448.0 1920.5 479.0Q1970.0 510.0 2034.0 510.0Q2075.0 510.0 2118.0 489.5Q2161.0 469.0 2185.0 428.0V668.0H2337.0V194.0Q2337.0 157.0 2340.5 106.0Q2344.0 55.0 2354.0 0.0H2209.0L2189.0 67.0Q2158.0 24.0 2116.5 6.0Q2075.0 -12.0 2034.0 -12.0ZM2083.0 106.0Q2127.0 106.0 2159.5 139.0Q2192.0 172.0 2192.0 249.0Q2192.0 325.0 2159.5 358.5Q2127.0 392.0 2083.0 392.0Q2038.0 392.0 2005.5 356.0Q1973.0 320.0 1973.0 252.0Q1973.0 183.0 2005.5 144.5Q2038.0 106.0 2083.0 106.0Z',
    'M2431.0 0.0V668.0H2688.0Q2775.0 668.0 2843.5 651.0Q2912.0 634.0 2951.5 589.0Q2991.0 544.0 2991.0 461.0Q2991.0 423.0 2977.0 385.5Q2963.0 348.0 2928.5 317.0Q2894.0 286.0 2830.0 269.0L3024.0 0.0H2841.0L2660.0 252.0H2589.0V0.0ZM2589.0 384.0H2693.0Q2749.0 384.0 2786.5 398.5Q2824.0 413.0 2824.0 459.0Q2824.0 506.0 2786.5 520.5Q2749.0 535.0 2693.0 535.0H2589.0Z',
    'M3328.0 -12.0Q3259.0 -12.0 3199.0 16.0Q3139.0 44.0 3102.0 102.5Q3065.0 161.0 3065.0 250.0Q3065.0 340.0 3102.0 397.5Q3139.0 455.0 3199.0 482.5Q3259.0 510.0 3328.0 510.0Q3396.0 510.0 3456.0 482.5Q3516.0 455.0 3553.0 397.5Q3590.0 340.0 3590.0 250.0Q3590.0 161.0 3553.0 102.5Q3516.0 44.0 3456.0 16.0Q3396.0 -12.0 3328.0 -12.0ZM3328.0 106.0Q3374.0 106.0 3404.5 139.0Q3435.0 172.0 3435.0 250.0Q3435.0 329.0 3403.5 360.5Q3372.0 392.0 3328.0 392.0Q3283.0 392.0 3251.5 360.5Q3220.0 329.0 3220.0 250.0Q3220.0 172.0 3251.0 139.0Q3282.0 106.0 3328.0 106.0Z',
    'M3836.0 -12.0Q3770.0 -12.0 3732.5 12.5Q3695.0 37.0 3679.5 84.0Q3664.0 131.0 3664.0 198.0V496.0H3816.0V219.0Q3816.0 151.0 3836.5 128.5Q3857.0 106.0 3894.0 106.0Q3939.0 106.0 3959.5 136.0Q3980.0 166.0 3980.0 235.0V496.0H4133.0V0.0H4001.0L3980.0 70.0Q3958.0 33.0 3925.5 10.5Q3893.0 -12.0 3836.0 -12.0Z',
    'M4443.0 0.0Q4382.0 0.0 4346.0 10.5Q4310.0 21.0 4294.5 51.5Q4279.0 82.0 4279.0 140.0V380.0H4197.0V496.0H4279.0V620.0H4431.0V496.0H4539.0V380.0H4431.0V180.0Q4431.0 145.0 4444.5 134.5Q4458.0 124.0 4495.0 124.0H4539.0V0.0Z',
    'M4859.0 -12.0Q4779.0 -12.0 4717.5 19.5Q4656.0 51.0 4621.5 110.0Q4587.0 169.0 4587.0 251.0Q4587.0 330.0 4623.5 388.0Q4660.0 446.0 4720.5 478.0Q4781.0 510.0 4853.0 510.0Q4935.0 510.0 4993.5 471.5Q5052.0 433.0 5082.0 365.5Q5112.0 298.0 5107.0 210.0H4740.0Q4744.0 158.0 4778.5 132.0Q4813.0 106.0 4855.0 106.0Q4890.0 106.0 4915.5 116.5Q4941.0 127.0 4955.0 143.0L5076.0 99.0Q5037.0 42.0 4978.5 15.0Q4920.0 -12.0 4859.0 -12.0ZM4740.0 300.0H4966.0Q4965.0 348.0 4933.0 372.5Q4901.0 397.0 4857.0 397.0Q4814.0 397.0 4780.5 374.0Q4747.0 351.0 4740.0 300.0Z',
  ];

  /// Las letras ya leídas y puestas en la caja (sin escalar). Se leen una
  /// sola vez.
  @visibleForTesting
  static final List<Path> letras = [for (final d in trazos) leerTrazo(d)];

  /// Lee un trazo de SVG con comandos absolutos M, L, H, V, Q y Z, y lo da
  /// vuelta de arriba abajo para que caiga en la caja. Con otro comando
  /// falla: el kit no los usa, y si cambia hay que saberlo.
  @visibleForTesting
  static Path leerTrazo(String d) {
    final partes = RegExp(
      r'[A-Za-z]|-?\d+(?:\.\d+)?',
    ).allMatches(d).map((m) => m.group(0)!).toList();
    final trazo = Path();
    var i = 0;
    var x = 0.0;
    var y = 0.0;
    double numero() => double.parse(partes[i++]);
    double yCaja(double v) => origenY - v;
    String? comando;
    while (i < partes.length) {
      final p = partes[i];
      if (RegExp('[A-Za-z]').hasMatch(p)) {
        comando = p;
        i++;
        if (comando == 'Z') {
          trazo.close();
          continue;
        }
      }
      switch (comando) {
        case 'M':
          x = numero();
          y = numero();
          trazo.moveTo(x, yCaja(y));
          comando = 'L'; // Los pares que siguen a un M son líneas.
        case 'L':
          x = numero();
          y = numero();
          trazo.lineTo(x, yCaja(y));
        case 'H':
          x = numero();
          trazo.lineTo(x, yCaja(y));
        case 'V':
          y = numero();
          trazo.lineTo(x, yCaja(y));
        case 'Q':
          final cx = numero();
          final cy = numero();
          x = numero();
          y = numero();
          trazo.quadraticBezierTo(cx, yCaja(cy), x, yCaja(y));
        default:
          throw FormatException('Comando de SVG que no se lee: $comando', d);
      }
    }
    return trazo;
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return SizedBox(
      width: alto * proporcion,
      height: alto,
      child: CustomPaint(
        painter: _PintorLogotipo(letras: e.textoPrincipal, punto: e.acento),
      ),
    );
  }
}

class _PintorLogotipo extends CustomPainter {
  const _PintorLogotipo({required this.letras, required this.punto});

  final Color letras;
  final Color punto;

  @override
  void paint(Canvas canvas, Size size) {
    final escala = size.height / LogotipoBlindRoute.altoCaja;
    canvas.save();
    canvas.scale(escala, escala);
    final pintura = Paint()
      ..color = letras
      ..isAntiAlias = true;
    for (final letra in LogotipoBlindRoute.letras) {
      canvas.drawPath(letra, pintura);
    }
    const c = LogotipoBlindRoute.centroPunto;
    canvas.drawCircle(
      Offset(c.dx, LogotipoBlindRoute.origenY - c.dy),
      LogotipoBlindRoute.radioPunto,
      Paint()
        ..color = punto
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorLogotipo viejo) =>
      viejo.letras != letras || viejo.punto != punto;
}

/// El logotipo de la app de administración: el de siempre y, debajo, la
/// palabra «ADMINISTRADOR» de punta a punta, del borde de la B al de la e.
///
/// Las letras de abajo van repartidas a lo ancho (una por una, con el mismo
/// espacio entre cada una), en acento, como el punto de la i. Es parte del
/// dibujo: no crece con la letra del teléfono y TalkBack no lo lee (quien lo
/// usa le da el nombre, como en [LogotipoBlindRoute]).
class LogotipoAdministrador extends StatelessWidget {
  const LogotipoAdministrador({super.key});

  /// La palabra de abajo.
  static const String palabra = 'ADMINISTRADOR';

  /// Tamaño de la letra de la palabra de abajo.
  static const double tamanoPalabra = 10;

  /// Aire entre el logotipo y la palabra.
  static const double separacion = 4;

  /// Dónde empieza la tinta del logotipo (la B) y dónde termina (la e), en
  /// coordenadas del SVG: la palabra va de una a la otra.
  static const double inicioTinta = 44;
  static const double finTinta = 5112;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    const alto = LogotipoBlindRoute.altoBarra;
    const escala = alto / LogotipoBlindRoute.altoCaja;
    final estilo = TextStyle(
      fontFamily: 'Inter',
      fontSize: tamanoPalabra,
      fontWeight: FontWeight.w600,
      height: 1,
      color: e.acento,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LogotipoBlindRoute(),
        const SizedBox(height: separacion),
        SizedBox(
          width: alto * LogotipoBlindRoute.proporcion,
          child: Padding(
            padding: const EdgeInsets.only(
              left: inicioTinta * escala,
              right: (LogotipoBlindRoute.anchoCaja - finTinta) * escala,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final letra in palabra.split(''))
                  Text(letra, textScaler: TextScaler.noScaling, style: estilo),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
