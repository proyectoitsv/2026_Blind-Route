import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';
import 'pantalla_login_admin.dart';
import 'supabase_config.dart';

/// Punto de entrada de la app de ADMINISTRADOR.
/// Build: flutter run --flavor admin -t lib/main_admin.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.configurado) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  // Catálogo de rubros editable de este teléfono. Si la base falla se sigue
  // con los rubros de fábrica, que es con lo que arranca Rubros.
  try {
    await DatabaseHelper.instance.cargarRubros();
  } catch (e) {
    debugPrint('[Rubros] No se pudo cargar el catálogo: $e');
  }

  runApp(const AppAdmin());
}

class AppAdmin extends StatelessWidget {
  const AppAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BlindRoute Admin',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const PantallaLoginAdmin(),
    );
  }
}