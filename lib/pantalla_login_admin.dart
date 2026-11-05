import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design/design.dart';
import 'lista_edificios.dart';
import 'supabase_config.dart';

/// Login de la app de ADMINISTRADOR. La autenticación real la hace Supabase
/// Auth (email + contraseña); las cuentas se crean desde el dashboard, con los
/// registros públicos DESACTIVADOS. Sin una sesión válida, el servidor rechaza
/// cualquier publicación aunque alguien tenga el APK y la anon key.
///
/// ─── Sistema de diseño (fase 5.3 del rediseño) ───
/// Va envuelta en AmbienteDiseno. Arriba, el ícono de administrador en un
/// cuadro hundido, "Acceso de administrador" y una frase en gris; después,
/// Email y Contraseña (CampoTexto, con la etiqueta arriba) y "Ingresar", el
/// botón principal. Los dos campos van en un AutofillGroup: el teléfono los
/// completa y, al entrar, ofrece guardar la contraseña. En el teclado,
/// "Siguiente" pasa del email a la contraseña y "Listo" ingresa.
///
/// Los errores van debajo de los campos (antes, en un SnackBar), en rojo y
/// con un ícono, y TalkBack los anuncia: "Completá el email." y "Completá la
/// contraseña." debajo del que falte, y el de Supabase debajo de la
/// contraseña. Escribir en un campo le borra el error.
///
/// Mientras ingresa, los campos se deshabilitan y el botón dice "Ingresando…"
/// (TalkBack lo anuncia), sin nada que gire. Si entra, queda así mientras la
/// pantalla se va: durante la transición no vuelve a "Ingresar". Mientras
/// revisa si hay una sesión guardada (dura un cuadro), se ve sólo la barra.
class PantallaLoginAdmin extends StatefulWidget {
  const PantallaLoginAdmin({super.key, this.configurado});

  /// Si Supabase está configurado. null: lo dice SupabaseConfig, como en la
  /// app. Los tests lo fijan para ver el aviso "Falta configurar Supabase",
  /// que con las credenciales cargadas no aparece nunca.
  @visibleForTesting
  final bool? configurado;

  @override
  State<PantallaLoginAdmin> createState() => _PantallaLoginAdminState();
}

class _PantallaLoginAdminState extends State<PantallaLoginAdmin> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _focoContrasena = FocusNode();
  bool _cargando = false;
  bool _verificandoSesion = true;

  /// Lo que está mal, debajo de cada campo. El error de Supabase va debajo
  /// de la contraseña.
  String? _errorEmail;
  String? _errorContrasena;

  bool get _configurado => widget.configurado ?? SupabaseConfig.configurado;

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
    _focoContrasena.dispose();
    super.dispose();
  }

  /// Si ya hay una sesión guardada, saltea el login y entra directo.
  Future<void> _verificarSesionExistente() async {
    if (!_configurado) {
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
      RutaApp<void>(builder: (_) => const ListaEdificios()),
    );
  }

  Future<void> _ingresar() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      // Debajo del que falte (de los dos, si faltan los dos).
      setState(() {
        _errorEmail = email.isEmpty ? 'Completá el email.' : null;
        _errorContrasena = pass.isEmpty ? 'Completá la contraseña.' : null;
      });
      return;
    }

    setState(() {
      _cargando = true;
      _errorEmail = null;
      _errorContrasena = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pass,
      );
      // Sigue en "Ingresando…" mientras la pantalla se va: si volviera a
      // "Ingresar", se vería (y se podría tocar) durante la transición.
      _irAPanel();
    } on AuthException catch (e) {
      _mostrarError(e.message);
    } catch (e) {
      _mostrarError('No se pudo iniciar sesión: $e');
    }
  }

  /// El error del inicio de sesión, debajo de la contraseña.
  void _mostrarError(String msg) {
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _errorContrasena = msg;
    });
  }

  /// Escribir en un campo le borra el error: ya no dice lo que pasa.
  void _alCambiarEmail(String _) {
    if (_errorEmail != null) setState(() => _errorEmail = null);
  }

  void _alCambiarContrasena(String _) {
    if (_errorContrasena != null) setState(() => _errorContrasena = null);
  }

  @override
  Widget build(BuildContext context) {
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: const BarraSuperior(
              titulo: 'Blind Route — Administrador',
              mostrarVolver: false,
            ),
            body: SafeArea(
              top: false,
              child: _verificandoSesion
                  // Dura un cuadro: la barra con el fondo vacío.
                  ? const SizedBox.shrink()
                  : !_configurado
                  ? _avisoNoConfigurado()
                  : _formulario(e),
            ),
          );
        },
      ),
    );
  }

  Widget _formulario(EstiloApp e) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        EspaciadoApp.margenLateral,
        EspaciadoApp.entreSecciones,
        EspaciadoApp.margenLateral,
        EspaciadoApp.entreSecciones,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: CuadroIcono(icono: Icons.admin_panel_settings_rounded),
          ),
          const SizedBox(height: EspaciadoApp.margenLateral),
          Semantics(
            header: true,
            child: Text(
              'Acceso de administrador',
              textAlign: TextAlign.center,
              style: TipografiaApp.titulo.copyWith(color: e.textoPrincipal),
            ),
          ),
          const SizedBox(height: EspaciadoApp.chico),
          Text(
            'Ingresá con tu cuenta para cargar y publicar mapas.',
            textAlign: TextAlign.center,
            style: TipografiaApp.cuerpo.copyWith(color: e.textoSecundario),
          ),
          const SizedBox(height: EspaciadoApp.entreSecciones),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CampoTexto(
                  etiqueta: 'Email',
                  icono: Icons.mail_rounded,
                  controlador: _emailCtrl,
                  tipoTeclado: TextInputType.emailAddress,
                  accionTeclado: TextInputAction.next,
                  autocorrector: false,
                  pistasAutocompletar: const [AutofillHints.email],
                  habilitado: !_cargando,
                  error: _errorEmail,
                  alCambiar: _alCambiarEmail,
                  // "Siguiente": a la contraseña.
                  alEnviar: (_) => _focoContrasena.requestFocus(),
                ),
                const SizedBox(height: EspaciadoApp.margenLateral),
                CampoTexto(
                  etiqueta: 'Contraseña',
                  icono: Icons.lock_rounded,
                  controlador: _passCtrl,
                  focusNode: _focoContrasena,
                  oculto: true,
                  accionTeclado: TextInputAction.done,
                  pistasAutocompletar: const [AutofillHints.password],
                  habilitado: !_cargando,
                  error: _errorContrasena,
                  alCambiar: _alCambiarContrasena,
                  // "Listo": ingresa.
                  alEnviar: (_) => _cargando ? null : _ingresar(),
                ),
              ],
            ),
          ),
          // Más aire que el alcance de la luz del botón: ninguna sombra cae
          // sobre el error de la contraseña.
          const SizedBox(height: EspaciadoApp.entreSecciones),
          // Mientras ingresa, el botón es una región en vivo: TalkBack dice
          // "Ingresando…" al cambiar. Fuera de eso no, así al volver a
          // "Ingresar" (después de un error) sólo se anuncia el error.
          MergeSemantics(
            child: Semantics(
              liveRegion: _cargando,
              child: BotonPrincipal(
                texto: _cargando ? 'Ingresando…' : 'Ingresar',
                icono: _cargando ? null : Icons.login_rounded,
                alPresionar: _cargando ? null : _ingresar,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// En el medio de la pantalla; si con letra grande no entra, se desplaza.
  Widget _avisoNoConfigurado() {
    return const CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EstadoPantalla(
              icono: Icons.cloud_off_rounded,
              titulo: 'Falta configurar Supabase',
              detalle:
                  'Cargá url y anonKey en supabase_config.dart para usar la '
                  'app de administrador.',
            ),
          ),
        ),
      ],
    );
  }
}
