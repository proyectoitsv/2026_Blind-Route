import 'package:flutter/material.dart';

import 'design/galeria_componentes.dart';

/// Punto de entrada de la GALERÍA DE COMPONENTES, sólo para debug.
/// Build: flutter run --flavor user -t lib/main_galeria.dart
///
/// Muestra los componentes del sistema de diseño (lib/design/components/)
/// con el tema nuevo, sin Supabase ni nada de la app. No es una tercera app:
/// usa el flavor del usuario, así que se instala EN LUGAR de BlindRoute;
/// para volver, flutter run --flavor user -t lib/main_user.dart. Ninguna de
/// las dos apps la referencia, así que no entra en sus APK.
void main() => runApp(const AppGaleria());
