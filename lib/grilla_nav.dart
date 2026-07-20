import 'dart:ui';

/// Definición de la grilla de navegación para un plano. El lado de celda es
/// **configurable por piso** ([tamCeldaMetros]) en el rango 0.5–1.0 m: 0.5 m da
/// mayor resolución en espacios reducidos, 1.0 m es el valor por defecto.
///
/// Las posiciones se guardan normalizadas en `[0, 1]`. La escala es
/// **configurable por piso y por eje**: el operador la define con una medida de
/// referencia interactiva (largo y ancho) en la pantalla de configuración.
///
/// - [metrosX] = metros que representa el lado horizontal completo del plano.
/// - [metrosY] = metros que representa el lado vertical completo del plano.
///
/// Al tener una escala por eje, la grilla puede ser **rectangular**
/// ([celdasX] × [celdasY]) y cada celda mide ~[tamCeldaMetros] m de lado en el
/// mundo real aunque la imagen del plano no sea cuadrada.
///
/// Es la única fuente de verdad de la grilla: la usan el pathfinder (para
/// calcular el camino) y el `MapaWidget` (para pintar las celdas), de modo que
/// el camino calculado y el dibujado coincidan exactamente.
class GrillaNav {
  /// Metros que representa el lado horizontal completo del plano (eje X).
  final double metrosX;

  /// Metros que representa el lado vertical completo del plano (eje Y).
  final double metrosY;

  /// Lado de cada celda de la grilla, en metros.
  final double tamCeldaMetros;

  /// Cantidad de celdas en cada eje.
  final int celdasX;
  final int celdasY;

  /// Lado de una celda en coordenadas normalizadas `[0, 1]` en cada eje.
  final double tamCeldaX;
  final double tamCeldaY;

  /// Escala por defecto (m) cuando un piso todavía no tiene escala configurada.
  static const double escalaPorDefecto = 50.0;

  /// Límites de cantidad de celdas para evitar grillas degeneradas o gigantes.
  /// _minCeldas = 6: con celdas de 0.5 m permite grillas en espacios muy chicos
  ///   (≥3 m de lado) sin degenerar.
  /// _maxCeldas = 1000: soporta celdas de 0.5 m en planos de hasta 500 m por eje
  ///   (excede de sobra cualquier interior; no se baja para no limitar planos
  ///   grandes ya configurados).
  static const int _minCeldas = 6;
  static const int _maxCeldas = 1000;

  const GrillaNav._({
    required this.metrosX,
    required this.metrosY,
    required this.tamCeldaMetros,
    required this.celdasX,
    required this.celdasY,
    required this.tamCeldaX,
    required this.tamCeldaY,
  });

  factory GrillaNav({
    double metrosX = escalaPorDefecto,
    double metrosY = escalaPorDefecto,
    double tamCeldaMetros = 1.0,
  }) {
    final t = (tamCeldaMetros.isFinite && tamCeldaMetros > 0) ? tamCeldaMetros : 1.0;
    final mx = (metrosX.isFinite && metrosX > 0) ? metrosX : escalaPorDefecto;
    final my = (metrosY.isFinite && metrosY > 0) ? metrosY : escalaPorDefecto;
    final ejeX = _calcularEje(mx, t);
    final ejeY = _calcularEje(my, t);
    return GrillaNav._(
      metrosX: mx,
      metrosY: my,
      tamCeldaMetros: t,
      celdasX: ejeX.$1,
      celdasY: ejeY.$1,
      tamCeldaX: ejeX.$2,
      tamCeldaY: ejeY.$2,
    );
  }

  /// Calcula (cantidad de celdas, tamaño normalizado de celda) para un eje.
  ///
  /// Las celdas miden [tamCeldaMetros] m exactos, así que se ven cuadradas en
  /// un plano a escala. Si los metros no son múltiplo entero del tamaño de
  /// celda, la última celda queda **parcial** (media cuadrícula) y se recorta
  /// al borde del plano, llenando todo el espacio. Si la cantidad cae fuera de
  /// `[_minCeldas, _maxCeldas]` se usan celdas uniformes que llenan `[0,1]`.
  static (int, double) _calcularEje(double metros, double tamCeldaMetros) {
    final exactas = metros / tamCeldaMetros; // p. ej. 30.4
    var celdas = exactas.ceil();             // incluye la celda parcial
    if (celdas < _minCeldas) {
      celdas = _minCeldas;
      return (celdas, 1.0 / celdas);         // uniforme
    }
    if (celdas > _maxCeldas) {
      celdas = _maxCeldas;
      return (celdas, 1.0 / celdas);         // uniforme
    }
    // tamaño normalizado de una celda de tamCeldaMetros; la última se recorta.
    return (celdas, 1.0 / exactas);
  }

  /// Índice de celda en X (`0..celdasX-1`) para una coordenada normalizada.
  int indiceX(double nx) => _indice(nx, tamCeldaX, celdasX);

  /// Índice de celda en Y (`0..celdasY-1`) para una coordenada normalizada.
  int indiceY(double ny) => _indice(ny, tamCeldaY, celdasY);

  static int _indice(double n, double tamCelda, int celdas) {
    final i = (n / tamCelda).floor();
    if (i < 0) return 0;
    if (i >= celdas) return celdas - 1;
    return i;
  }

  /// Centro normalizado (eje X) de la celda [i], recortado al borde del plano
  /// para que la última celda (parcial) tenga su centro dentro de `[0,1]`.
  double centroX(int i) => _centro(i, tamCeldaX);

  /// Centro normalizado (eje Y) de la celda [j].
  double centroY(int j) => _centro(j, tamCeldaY);

  static double _centro(int i, double tamCelda) {
    final inicio = i * tamCelda;
    final fin = (inicio + tamCelda) > 1.0 ? 1.0 : inicio + tamCelda;
    return (inicio + fin) / 2;
  }

  /// Centro normalizado de la celda que contiene el punto [p].
  Offset centroDeCelda(Offset p) =>
      Offset(centroX(indiceX(p.dx)), centroY(indiceY(p.dy)));
}
