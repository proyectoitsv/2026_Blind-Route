import 'package:flutter/material.dart';

import 'design/design.dart';
import 'modo_automatico.dart';
import 'pantalla_ajustes.dart';
import 'pantalla_mapas_online.dart';
import 'voz_service.dart';

/// Pantalla principal de la app de USUARIO. Solo navegar y descargar mapas.
/// No contiene ningún acceso al modo administrador: esas pantallas ni siquiera
/// se compilan en este binario (el punto de entrada main_user.dart no las
/// referencia).
///
/// ─── Sistema de diseño (fase 5.1 del rediseño) ───
/// Va envuelta en AmbienteDiseno (el tema nuevo y «Reducir movimiento») y
/// abre las pantallas con RutaApp, con la transición de la tabla de
/// movimiento. La primera vista es sólo "Comenzar a navegar": un círculo de
/// acento con ondas (BotonPulso) en el medio, que se toca en cualquier parte
/// del círculo o de su texto. "Mapas disponibles" y "Ajustes" quedan debajo,
/// a la vista desplazando, como filas de un grupo; TalkBack los nombra como
/// antes ("Mapas disponibles para descargar", "Ajustes: voz, movimiento y
/// vibración") y llega a ellos recorriendo la pantalla.
class PantallaPrincipalUsuario extends StatefulWidget {
  const PantallaPrincipalUsuario({super.key});

  @override
  State<PantallaPrincipalUsuario> createState() =>
      _PantallaPrincipalUsuarioState();
}

class _PantallaPrincipalUsuarioState extends State<PantallaPrincipalUsuario> {
  final VozService _voz = VozService();

  @override
  void initState() {
    super.initState();
    _voz.inicializar();
  }

  /// Corta la voz y abre [pantalla].
  void _abrir(Widget pantalla) {
    _voz.detener();
    Navigator.of(context).push(RutaApp<void>(builder: (_) => pantalla));
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
              titulo: 'Blind Route',
              mostrarVolver: false,
            ),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, restricciones) => CustomScrollView(
                  slivers: [
                    // La primera vista es sólo el botón con pulso: ocupa
                    // todo el alto. Si con letra grande no entra, mide lo
                    // que pide su contenido.
                    SliverToBoxAdapter(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: restricciones.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: _Portada(
                            alComenzar: () => _abrir(const ModoAutomatico()),
                          ),
                        ),
                      ),
                    ),
                    // Más abajo, a la vista desplazando: los mapas y los
                    // ajustes. TalkBack llega a ellos recorriendo, igual.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        EspaciadoApp.margenLateral,
                        EspaciadoApp.margenLateral,
                        EspaciadoApp.margenLateral,
                        EspaciadoApp.entreSecciones,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: GrupoFilas(
                          filas: [
                            FilaGrupo(
                              icono: Icons.cloud_download_rounded,
                              titulo: 'Mapas disponibles',
                              subtitulo: 'Descargá, actualizá o quitá mapas',
                              etiquetaSemantica:
                                  'Mapas disponibles para descargar',
                              navega: true,
                              alTocar: () =>
                                  _abrir(const PantallaMapasOnline()),
                            ),
                            FilaGrupo(
                              icono: Icons.settings_rounded,
                              titulo: 'Ajustes',
                              subtitulo: 'Voz, movimiento y vibración',
                              etiquetaSemantica:
                                  'Ajustes: voz, movimiento y vibración',
                              navega: true,
                              alTocar: () => _abrir(const PantallaAjustes()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// La primera vista del inicio: la frase arriba, el botón con pulso en el
/// medio y, abajo, la pista de que hay más desplazando.
class _Portada extends StatelessWidget {
  const _Portada({required this.alComenzar});

  final VoidCallback alComenzar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    // Toda la primera vista lleva a navegar, no sólo el círculo: sin ver, es
    // difícil acertarle justo. El botón ocupa todo el medio; la frase de
    // arriba, la pista de abajo y los márgenes también responden al toque
    // (TalkBack los sigue leyendo como texto: la acción es la del botón).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: alComenzar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EspaciadoApp.margenLateral,
          EspaciadoApp.margenLateral,
          EspaciadoApp.margenLateral,
          EspaciadoApp.medio,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Navegación interior para todos',
              textAlign: TextAlign.center,
              style: TipografiaApp.cuerpo.copyWith(color: e.textoSecundario),
            ),
            // Aire para las ondas, que llegan casi un radio más afuera.
            const SizedBox(
              height: BotonPulso.diametro / 2 * (BotonPulso.alcanceOnda - 1),
            ),
            Expanded(
              child: BotonPulso(
                icono: Icons.navigation_rounded,
                texto: 'Comenzar a navegar',
                detalle: 'Primero te ubico. Después decís a dónde ir.',
                alPresionar: alComenzar,
                llenar: true,
              ),
            ),
            const SizedBox(height: EspaciadoApp.entreSecciones),
            // Para quien ve: abajo hay más. TalkBack llega recorriendo.
            ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    'Mapas y ajustes',
                    textAlign: TextAlign.center,
                    style: TipografiaApp.nota.copyWith(
                      color: e.textoSecundario,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: FormasApp.icono,
                    color: e.textoSecundario,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
