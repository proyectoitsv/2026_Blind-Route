// ═══════════════════════════════════════════════════════════════════════════
// lib/tema.dart se mudó a lib/design/
// ═══════════════════════════════════════════════════════════════════════════
//
// El sistema de diseño vive en lib/design/ (design.dart). Este archivo queda
// sólo para que las pantallas que todavía importan 'tema.dart' sigan
// compilando sin tocarlas: reexporta TemaApp, la API de antes, sin valores
// propios. Cada pantalla que se migra (fase 5) pasa a importar
// 'design/design.dart'; cuando no quede ninguna, se borra este archivo.
export 'design/tema_legado.dart';
