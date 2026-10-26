import 'package:flutter/material.dart';

import 'modo_automatico.dart';
import 'pantalla_ajustes_voz.dart';
import 'pantalla_mapas_online.dart';
import 'voz_service.dart';
import 'tema.dart';

/// Pantalla principal de la app de USUARIO. Solo navegar y descargar mapas.
/// No contiene ningún acceso al modo administrador: esas pantallas ni siquiera
/// se compilan en este binario (el punto de entrada main_user.dart no las
/// referencia).
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: TemaApp.acento,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: TemaApp.acento.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text('Blind Route'),
            ],
          ),
          centerTitle: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Navegación interior\npara todos',
                style: TextStyle(
                  color: TemaApp.textoSecundario,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Botón principal: navegar
              Expanded(
                flex: 4,
                child: Semantics(
                  label: 'Comenzar a navegar',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      _voz.detener();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ModoAutomatico(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: TemaApp.acentoSuave,
                        borderRadius:
                            BorderRadius.circular(TemaApp.radiusCard),
                        border: Border.all(
                          color: TemaApp.acento.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: TemaApp.acento.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.explore_rounded,
                              color: TemaApp.acento, size: 72),
                          const SizedBox(height: 20),
                          const Text(
                            'Comenzar a\nNavegar',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 36,
                              color: TemaApp.textoBlanco,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: TemaApp.acento.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Tocá para comenzar',
                              style: TextStyle(
                                color: TemaApp.acento,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Catálogo de mapas publicados y ajustes de la voz.
              _botonSecundario(
                icono: Icons.cloud_download_rounded,
                texto: 'Mapas disponibles',
                etiqueta: 'Mapas disponibles para descargar',
                pantalla: const PantallaMapasOnline(),
              ),
              const SizedBox(height: 12),
              _botonSecundario(
                icono: Icons.record_voice_over_rounded,
                texto: 'Ajustes de voz',
                etiqueta: 'Ajustes de voz: velocidad, volumen y tono',
                pantalla: const PantallaAjustesVoz(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Botón secundario: objetivo táctil grande y ancho completo (más fácil de
  /// acertar para personas con baja visión), pero visualmente secundario al
  /// botón de navegar.
  Widget _botonSecundario({
    required IconData icono,
    required String texto,
    required String etiqueta,
    required Widget pantalla,
  }) {
    return Semantics(
      button: true,
      label: etiqueta,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(TemaApp.radiusButton),
          onTap: () {
            _voz.detener();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => pantalla),
            );
          },
          child: Ink(
            height: 76,
            decoration: BoxDecoration(
              color: TemaApp.acento.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(TemaApp.radiusButton),
              border: Border.all(
                color: TemaApp.acento.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, color: TemaApp.acento, size: 30),
                const SizedBox(width: 14),
                Text(
                  texto,
                  style: const TextStyle(
                    color: TemaApp.textoBlanco,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}