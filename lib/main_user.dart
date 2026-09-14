import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pantalla_princ_usuario.dart';
import 'supabase_config.dart';

/// Punto de entrada de la app de USUARIO.
/// Build: flutter run --flavor user -t lib/main_user.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // El usuario necesita Supabase para el catálogo y las descargas. Si no está
  // configurado, la app igual arranca y navega los mapas ya descargados.
  if (SupabaseConfig.configurado) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  runApp(const AppUsuario());
}

class AppUsuario extends StatelessWidget {
  const AppUsuario({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BlindRoute',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const PantallaPrincipalUsuario(),
    );
  }
}