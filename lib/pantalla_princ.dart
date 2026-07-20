import 'package:flutter/material.dart';
import 'lista_edificios.dart';
import 'modo_automatico.dart';
import 'voz_service.dart';
import 'tema.dart';

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  final VozService _voz = VozService();

  @override
  void initState() {
    super.initState();
    _voz.inicializar();
  }

  void _solicitarClave(BuildContext context) {
    final TextEditingController claveController = TextEditingController();
    const String claveCorrecta = "1234";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaApp.fondoCard,
        title: const Text('Acceso Administrativo', style: TextStyle(color: TemaApp.textoBlanco)),
        content: TextField(
          controller: claveController,
          obscureText: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: TemaApp.textoBlanco),
          decoration: const InputDecoration(
            hintText: 'Ingresá la clave de acceso',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (claveController.text == claveCorrecta) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ListaEdificios()),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Clave incorrecta")),
                );
              }
            },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
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
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: TemaApp.acento,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: TemaApp.acento.withValues(alpha: 0.6), blurRadius: 8)],
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
              // Subtítulo de bienvenida
              const Text(
                'Navegación interior\npara todos',
                style: TextStyle(
                  color: TemaApp.textoSecundario,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Botón principal
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
                        MaterialPageRoute(builder: (context) => const ModoAutomatico()),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: TemaApp.acentoSuave,
                        borderRadius: BorderRadius.circular(TemaApp.radiusCard),
                        border: Border.all(color: TemaApp.acento.withValues(alpha: 0.5), width: 1.5),
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
                          Icon(Icons.explore_rounded, color: TemaApp.acento, size: 72),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: TemaApp.acento.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Tocá para comenzar',
                              style: TextStyle(color: TemaApp.acento, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Botón configurar
              Center(
                child: SizedBox(
                  height: TemaApp.targetTactil,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: TemaApp.textoSecundario,
                      textStyle: const TextStyle(fontSize: 15),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 22),
                    label: const Text('Configurar Mapa'),
                    onPressed: () => _solicitarClave(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
