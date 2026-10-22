/// Qué app está corriendo: la del usuario o la del administrador.
///
/// Las dos comparten código (la pantalla de navegación, por ejemplo) y hay
/// cosas que sólo tiene que ver el admin, como el panel de ajustes de
/// navegación. Lo fija `main_admin.dart` antes de arrancar la app. Es global
/// y no un parámetro de cada pantalla porque la pantalla de navegación se
/// vuelve a crear a sí misma en cada salto de piso.
class EntornoApp {
  EntornoApp._();

  static bool esAdmin = false;
}
