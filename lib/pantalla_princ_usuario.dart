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
/// movimiento. "Comenzar a navegar" es el botón principal en grande, la ficha
/// (BotonPrincipalGrande): llena todo el lugar libre, así se acierta sin
/// mirar con cuidado. "Mapas
/// disponibles" y "Ajustes" son las filas de un grupo, y TalkBack las nombra
/// como antes ("Mapas disponibles para descargar", "Ajustes: voz, movimiento
/// y vibración").
///
/// Con letra grande o en un teléfono bajo, si no entra todo, la pantalla se
/// desplaza y el botón grande mide lo que pide su contenido.
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
              child: CustomScrollView(
                slivers: [
                  // Llena la pantalla; si con letra grande no entra todo,
                  // mide lo que pide el contenido y la pantalla se desplaza.
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        EspaciadoApp.margenLateral,
                        EspaciadoApp.margenLateral,
                        EspaciadoApp.margenLateral,
                        EspaciadoApp.entreSecciones,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Navegación interior para todos',
                            style: TipografiaApp.cuerpo.copyWith(
                              color: e.textoSecundario,
                            ),
                          ),
                          // Más aire que el alcance de la luz del botón:
                          // ninguna sombra cae sobre el texto.
                          const SizedBox(height: EspaciadoApp.entreSecciones),
                          Expanded(
                            child: BotonPrincipalGrande(
                              icono: Icons.explore_rounded,
                              texto: 'Comenzar a navegar',
                              detalle:
                                  'Primero te ubico. Después decís a dónde ir.',
                              accion: 'Empezar',
                              alPresionar: () => _abrir(const ModoAutomatico()),
                            ),
                          ),
                          const SizedBox(height: EspaciadoApp.entreSecciones),
                          GrupoFilas(
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
