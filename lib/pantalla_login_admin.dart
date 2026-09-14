import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lista_edificios.dart';
import 'supabase_config.dart';
import 'tema.dart';

/// Login de la app de ADMINISTRADOR. La autenticación real la hace Supabase
/// Auth (email + contraseña); las cuentas se crean desde el dashboard, con los
/// registros públicos DESACTIVADOS. Sin una sesión válida, el servidor rechaza
/// cualquier publicación aunque alguien tenga el APK y la anon key.
class PantallaLoginAdmin extends StatefulWidget {
  const PantallaLoginAdmin({super.key});

  @override
  State<PantallaLoginAdmin> createState() => _PantallaLoginAdminState();
}

class _PantallaLoginAdminState extends State<PantallaLoginAdmin> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _cargando = false;
  bool _verificandoSesion = true;

  @override
  void initState() {
    super.initState();
    // Se difiere al primer frame: navegar durante initState (cuando hay sesión
    // guardada y se saltea el login) deja el navegador en negro. Con
    // addPostFrameCallback, el salto ocurre después de dibujar la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarSesionExistente();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Si ya hay una sesión guardada, saltea el login y entra directo.
  Future<void> _verificarSesionExistente() async {
    if (!SupabaseConfig.configurado) {
      if (mounted) setState(() => _verificandoSesion = false);
      return;
    }
    final sesion = Supabase.instance.client.auth.currentSession;
    if (sesion != null && !sesion.isExpired) {
      _irAPanel();
      return;
    }
    if (mounted) setState(() => _verificandoSesion = false);
  }

  void _irAPanel() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ListaEdificios()),
    );
  }

  Future<void> _ingresar() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      _mostrar('Completá email y contraseña.');
      return;
    }

    setState(() => _cargando = true);
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: pass);
      _irAPanel();
    } on AuthException catch (e) {
      _mostrar(e.message);
    } catch (e) {
      _mostrar('No se pudo iniciar sesión: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: const Text('Blind Route — Administrador')),
        body: _verificandoSesion
            ? const Center(
                child: CircularProgressIndicator(color: TemaApp.acento))
            : !SupabaseConfig.configurado
                ? _avisoNoConfigurado()
                : _formulario(),
      ),
    );
  }

  Widget _formulario() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.admin_panel_settings_rounded,
              color: TemaApp.acento, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Acceso de administrador',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: TemaApp.textoBlanco,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ingresá con tu cuenta para cargar y publicar mapas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TemaApp.textoSecundario, fontSize: 13),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_cargando,
            style: const TextStyle(color: TemaApp.textoBlanco),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            enabled: !_cargando,
            onSubmitted: (_) => _cargando ? null : _ingresar(),
            style: const TextStyle(color: TemaApp.textoBlanco),
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _cargando ? null : _ingresar,
            icon: _cargando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: TemaApp.fondo),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_cargando ? 'Ingresando...' : 'Ingresar'),
          ),
        ],
      ),
    );
  }

  Widget _avisoNoConfigurado() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 64, color: TemaApp.textoSecundario),
            SizedBox(height: 16),
            Text(
              'Falta configurar Supabase',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: TemaApp.textoBlanco,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Cargá url y anonKey en supabase_config.dart para usar la app '
              'de administrador.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TemaApp.textoSecundario, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}