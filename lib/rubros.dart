/// Un rubro: la categoría de un lugar ("Comida", "Kiosco", "Baño"…) con las
/// palabras con las que la gente lo pide.
class Rubro {
  /// Identificador estable. Es lo que se guarda en la base y viaja en el
  /// mapa publicado: NO cambiarlo una vez que hay mapas cargados con él.
  final String id;

  /// Nombre que ve el admin en la lista.
  final String nombre;

  /// Palabras (o frases cortas) con las que el usuario puede pedir un lugar
  /// de este rubro. Se pueden escribir como se quiera ("baño", "Librería"):
  /// el buscador les saca tildes, mayúsculas y eñes antes de comparar. En
  /// singular: el plural lo tolera el buscador.
  final List<String> palabras;

  const Rubro(this.id, this.nombre, this.palabras);
}

/// ═══════════════════════════════════════════════════════════════════════════
/// RUBROS
/// ═══════════════════════════════════════════════════════════════════════════
///
/// En vez de que cada admin escriba, lugar por lugar, las palabras con las
/// que el usuario lo puede pedir ("restaurante, comer, almorzar…"), el admin
/// elige el RUBRO del lugar y las palabras vienen con el rubro. Ventajas:
///
///  • Se carga con un toque y queda igual en todos los mapas.
///  • Las palabras se mantienen en un solo lugar (este archivo): agregar
///    "morfar" a Comida lo arregla para todos los lugares de comida de todos
///    los edificios, sin tocar ni republicar ningún mapa.
///  • Cubre lo que un admin no prevé: verbos ("comer", "almorzar"),
///    necesidades ("hambre", "sed"), formas de decir ("tomar algo").
///
/// Las palabras clave libres de cada lugar siguen existiendo, pero para lo
/// que es propio de ESE lugar: apodos ("el mac"), una marca, un producto.
///
/// PARA AGREGAR UN RUBRO: sumar un `Rubro(...)` a [todos]. Para agregar una
/// palabra a uno existente: sumarla a su lista. Nada más.
class Rubros {
  /// Id del rubro de los baños. La navegación lo usa para su flujo propio
  /// (pregunta hombres / mujeres).
  static const String bano = 'bano';

  static const List<Rubro> todos = [
    Rubro('comida', 'Comida / restaurante', [
      'restaurante', 'resto', 'restoran', 'comida', 'comer', 'almorzar',
      'almuerzo', 'cenar', 'cena', 'hambre', 'comedor', 'cantina', 'buffet',
      'bodegon', 'parrilla', 'rotiseria', 'hamburguesa', 'hamburgueseria',
      'pizza', 'pizzeria', 'empanada', 'lomito', 'sandwich', 'comida rapida',
      'patio de comidas',
    ]),
    Rubro('cafe', 'Café / bar', [
      'cafe', 'cafeteria', 'cafetin', 'bar', 'confiteria', 'desayuno',
      'desayunar', 'merienda', 'merendar', 'medialuna', 'tomar algo',
      'cerveza', 'trago', 'panaderia', 'heladeria', 'helado',
    ]),
    Rubro(bano, 'Baño', [
      'bano', 'sanitario', 'toilette', 'toilet', 'wc', 'servicios',
    ]),
    Rubro('kiosco', 'Kiosco / almacén', [
      'kiosco', 'quiosco', 'kiosko', 'maxikiosco', 'almacen', 'despensa',
      'drugstore', 'golosina', 'caramelo', 'chicle', 'cigarrillo', 'bebida',
      'gaseosa', 'agua', 'sed', 'snack',
    ]),
    Rubro('tienda', 'Tienda / local', [
      'tienda', 'local', 'negocio', 'comercio', 'comprar', 'compra', 'ropa',
      'regalo', 'libreria', 'fotocopia', 'fotocopiadora', 'jugueteria',
      'zapateria', 'perfumeria',
    ]),
    Rubro('salud', 'Farmacia / salud', [
      'farmacia', 'remedio', 'medicamento', 'enfermeria', 'enfermera',
      'medico', 'doctor', 'doctora', 'consultorio', 'guardia', 'emergencia',
      'primeros auxilios', 'salud',
    ]),
    Rubro('cajero', 'Cajero / banco', [
      'cajero', 'cajero automatico', 'banco', 'efectivo', 'plata',
      'extraccion', 'extraer', 'sacar plata',
    ]),
    Rubro('informacion', 'Información / recepción', [
      'informacion', 'informes', 'recepcion', 'mesa de entrada', 'atencion',
      'ayuda', 'porteria', 'portero', 'mostrador', 'seguridad',
    ]),
    Rubro('oficina', 'Oficina / administración', [
      'oficina', 'administracion', 'secretaria', 'direccion', 'preceptoria',
      'preceptor', 'rectorado', 'tesoreria', 'caja', 'pagar',
    ]),
    Rubro('aula', 'Aula / salón', [
      'aula', 'salon', 'clase', 'curso', 'sum', 'auditorio', 'salon de actos',
    ]),
    Rubro('laboratorio', 'Laboratorio / taller', [
      'laboratorio', 'lab', 'taller',
    ]),
    Rubro('biblioteca', 'Biblioteca', [
      'biblioteca', 'libros', 'leer', 'estudiar', 'sala de lectura',
    ]),
    Rubro('salida', 'Salida / entrada', [
      'salida', 'salir', 'entrada', 'ingreso', 'acceso', 'puerta', 'calle',
      'afuera', 'puerta principal',
    ]),
    Rubro('descanso', 'Descanso / sala de espera', [
      'descansar', 'descanso', 'sentarme', 'sentarse', 'asiento', 'espera',
      'sala de espera', 'esperar',
    ]),
    Rubro('deporte', 'Patio / gimnasio', [
      'patio', 'gimnasio', 'cancha', 'deporte', 'recreo', 'educacion fisica',
    ]),
    Rubro('capilla', 'Capilla', [
      'capilla', 'iglesia', 'oratorio', 'rezar', 'misa',
    ]),
    Rubro('estacionamiento', 'Estacionamiento', [
      'estacionamiento', 'cochera', 'parking', 'garage', 'playa de estacionamiento',
    ]),
    Rubro('transporte', 'Transporte / parada', [
      'parada', 'colectivo', 'bondi', 'omnibus', 'taxi', 'remis', 'tren',
      'subte',
    ]),
  ];

  /// Rubro con ese id, o null si no existe (id null, o un mapa hecho con una
  /// versión más nueva de la app que trae un rubro que esta no conoce).
  static Rubro? porId(String? id) {
    if (id == null) return null;
    for (final r in todos) {
      if (r.id == id) return r;
    }
    return null;
  }
}