import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import 'package:geolocator/geolocator.dart';
import 'garaje_screen.dart';
// Añade esta importación junto a auth_service.dart
import '../services/vehiculo_service.dart';
import '../widgets/menu_drawer.dart';
import 'dart:async'; // NUEVO: Para manejar el Stream del GPS
import '../services/map_service.dart'; // NUEVO: Nuestro mensajero de datos

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Controlador para la barra de búsqueda
  final TextEditingController _buscadorController = TextEditingController();
  final AuthService _authService = AuthService();
  final MapService _mapService = MapService(); // NUEVO: Instancia del servicio

  // ... el resto de tus variables de estado siguen igual

  // 1. GESTIÓN DE ESTADO: Aquí guardamos lo que el mapa debe dibujar
  List<LatLng> _puntosDeRuta = [];
  List<Marker> _marcadores = []; // Origen y destino de la ruta
  List<Marker> _marcadoresComunidad = []; // Reportes en tiempo real
  List<Marker> _marcadoresPoi = []; // NUEVO: Puntos de Interés (Gasolineras, etc.)
  LatLng? _miUbicacion; // Inicia vacía hasta que el GPS responda

  // Gestión del GPS en tiempo real
  StreamSubscription<Position>? _rastreadorGps;
  // NUEVO: Telemetría de navegación
// Telemetría de navegación
  bool _modoNavegacion = false;
  double _velocidadActualKmH = 0.0;
  double _distanciaRestanteKm = 0.0; // NUEVO: Kilómetros hasta el destino
  final MapController _mapController = MapController();
  bool _cargando = false;
  // NUEVO: Autonomía del vehículo principal del usuario
// Gestión del vehículo seleccionado
// Gestión del vehículo seleccionado
  List<dynamic> _listaVehiculos = [];
  Map<String, dynamic>? _vehiculoActivo;
  int _autonomiaMiVehiculo = 0;

  // 🧠 NUEVAS VARIABLES: Memoria del recálculo dinámico
  LatLng? _destinoActual;
  bool _recalculando = false;

  // ⚠️ CAMBIA ESTO POR LA IP DE TU COMPUTADORA (Ej: '192.168.1.X')
  final String ipServidor = '192.168.1.15';

  // 2. EL MENÚ: Descarga las rutas y muestra el panel inferior
  void _mostrarMenuRutas() async {
    setState(() { _cargando = true; });

    // Le pedimos los datos al servicio limpio, sin saber cómo los consigue
    List<dynamic> rutasDisponibles = await _mapService.obtenerRutas();

    setState(() { _cargando = false; });

    if (rutasDisponibles.isNotEmpty && mounted) {
      // Despliega el BottomSheet nativo exactamente igual que antes
      showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: rutasDisponibles.length,
              itemBuilder: (context, index) {
                var ruta = rutasDisponibles[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.map, color: Colors.blueAccent),
                    title: Text(ruta['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${ruta['distanciaKm']} km - Dificultad: ${ruta['dificultad']}'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      Navigator.pop(context);
                      double distanciaRuta = double.parse(ruta['distanciaKm'].toString());

                      if (_autonomiaMiVehiculo > 0 && distanciaRuta > _autonomiaMiVehiculo) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⚠️ PRECAUCIÓN: Tu vehículo (${_autonomiaMiVehiculo}km) no tiene autonomía suficiente para esta ruta (${distanciaRuta}km).'),
                            backgroundColor: Colors.red.shade800,
                          ),
                        );
                      }

                      // IMPORTANTE: _trazarRutaEnMapa aún necesita el token por ahora
                      String? token = await _authService.obtenerToken();
                      if (token != null) {
                        _trazarRutaEnMapa(ruta);
                        _cargarPoisDeRuta(ruta['idRuta']);
                      }
                    },
                  ),
                );
              },
            );
          }
      );
    } else if (rutasDisponibles.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar las rutas. Revisa tu conexión.')),
      );
    }
  }

  // 3. MOTOR DE TRAZADO: Dibuja la ruta elegida y sus pines
// 3. MOTOR DE TRAZADO: Dibuja la ruta elegida y anima la cámara
  void _trazarRutaEnMapa(Map<String, dynamic> ruta) async {
    setState(() { _cargando = true; });

    try {
      List<dynamic> coordenadasJson = ruta['coordenadas'];
      String puntosOSRM = coordenadasJson.map((p) => '${p[0]},${p[1]}').join(';');

      // Delegamos el trazado a la API externa mediante nuestro servicio
      List<dynamic> geometria = await _mapService.obtenerGeometriaOSRM(puntosOSRM);

      List<LatLng> rutaPorCarretera = [];
      if (geometria.isNotEmpty) {
        rutaPorCarretera = geometria.map((punto) => LatLng(punto[1], punto[0])).toList();
      }

      setState(() {
        _puntosDeRuta = rutaPorCarretera;
        _marcadores = [];
        _cargando = false;
        _modoNavegacion = true; // NUEVO: Encendemos el tablero
        _destinoActual = rutaPorCarretera.last;
      });

      if (rutaPorCarretera.isNotEmpty) {
        // En lugar del CameraFit directo, pasamos por el escudo
        _enfocarRutaSegura(rutaPorCarretera);
      }
    } catch (e) {
      debugPrint("Error trazando ruta: $e");
      setState(() { _cargando = false; });
    }
  }
  // Función maestra: Busca el lugar, genera la ruta desde tu GPS y arranca el viaje
  void _buscarYNavegar() async {
    if (_miUbicacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Esperando tu ubicación GPS...', style: TextStyle(color: Colors.white)), backgroundColor: Colors.orange));
      return;
    }
    if (_buscadorController.text.trim().isEmpty) return;

    setState(() { _cargando = true; });

    // 1. Traducimos el texto a coordenadas
    LatLng? destino = await _mapService.buscarCoordenadasDestino(_buscadorController.text);

    if (destino == null) {
      setState(() { _cargando = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No encontramos ese lugar. Intenta agregar "Cúcuta" o la ciudad al final.'), backgroundColor: Colors.red));
      return;
    }

    // 2. Construimos la ruta dinámica: Desde tu punto AZUL hasta el DESTINO
    String puntosOSRM = '${_miUbicacion!.longitude},${_miUbicacion!.latitude};${destino.longitude},${destino.latitude}';
    List<dynamic> geometria = await _mapService.obtenerGeometriaOSRM(puntosOSRM);

    if (geometria.isNotEmpty) {
      List<LatLng> rutaPorCarretera = geometria.map((punto) => LatLng(punto[1], punto[0])).toList();

      setState(() {
        _puntosDeRuta = rutaPorCarretera;
        _marcadoresPoi = [];
        _marcadores = [
          Marker(point: destino, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.red, size: 40))
        ];
        _cargando = false;
        _modoNavegacion = true;

        _destinoActual = destino; // NUEVO: Memorizamos a dónde vamos
      });

      // Animamos la cámara para mostrar toda la ruta
      // ESTO SE BORRA:
      // final limitesRuta = LatLngBounds.fromPoints(rutaPorCarretera);
      // final ajuste = CameraFit.bounds(bounds: limitesRuta, padding: const EdgeInsets.all(50.0));
      // final camaraDestino = ajuste.fit(_mapController.camera);
      // _animarCamara(camaraDestino.center, camaraDestino.zoom);

      // SE REEMPLAZA POR ESTO:
      _enfocarRutaSegura(rutaPorCarretera);
    } else {
      setState(() { _cargando = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay carreteras para llegar allí.')));
    }
  }

  // 🛡️ ESCUDO PROTECTOR CONTRA PANTALLAS ROJAS (NaN)
  void _enfocarRutaSegura(List<LatLng> puntosRuta) {
    if (puntosRuta.isEmpty) return;

    try {
      final limitesRuta = LatLngBounds.fromPoints(puntosRuta);

      // Si origen y destino son idénticos (División por cero inminente)
      if (limitesRuta.southWest == limitesRuta.northEast) {
        _animarCamara(puntosRuta.first, 16.0); // Zoom manual seguro
        return;
      }

      final ajuste = CameraFit.bounds(bounds: limitesRuta, padding: const EdgeInsets.all(50.0));
      final camaraDestino = ajuste.fit(_mapController.camera);

      // Blindaje final por si la librería colapsa internamente
      if (camaraDestino.center.latitude.isNaN || camaraDestino.center.longitude.isNaN) {
        _animarCamara(puntosRuta.first, 15.0);
      } else {
        _animarCamara(camaraDestino.center, camaraDestino.zoom);
      }
    } catch (e) {
      debugPrint("Escudo salvó la app de un crash: $e");
      _animarCamara(puntosRuta.first, 15.0); // Aterrizaje de emergencia
    }
  }

  // Función para animar el vuelo de la cámara (Estilo Google Maps)
// Función para animar el vuelo de la cámara (Estilo Google Maps - Blindada)
  void _animarCamara(LatLng destino, double zoomDestino) {
    // BLOQUEO ANTIMISILES: Abortamos si nos envían un destino corrupto
    if (destino.latitude.isNaN || destino.longitude.isNaN) return;

    // 1. ESCUDO MATEMÁTICO...
    // (Tu código original continúa igual abajo)
    // 1. ESCUDO MATEMÁTICO: Filtramos el zoom antes de iniciar el vuelo
    double zoomSeguro = 15.0; // Valor seguro por defecto por si el cálculo colapsa

    // Verificamos que el zoom no sea "NaN" o Infinito
    if (zoomDestino.isFinite) {
      zoomSeguro = zoomDestino;
      // Forzamos la cámara a respetar los límites físicos de tu mapa
      if (zoomSeguro < 3.0) zoomSeguro = 3.0;   // Evita alejarse al vacío exterior
      if (zoomSeguro > 18.0) zoomSeguro = 18.0; // Evita acercarse a nivel microscópico
    }

    // Capturamos dónde está la cámara AHORA mismo
    final latInicio = _mapController.camera.center.latitude;
    final lngInicio = _mapController.camera.center.longitude;
    final zoomInicio = _mapController.camera.zoom;

    // Creamos las matemáticas del trayecto (Tweens) con el ZOOM SEGURO
    final latTween = Tween<double>(begin: latInicio, end: destino.latitude);
    final lngTween = Tween<double>(begin: lngInicio, end: destino.longitude);
    final zoomTween = Tween<double>(begin: zoomInicio, end: zoomSeguro); // ¡Usamos la variable blindada!

    // Configuramos la duración de la animación (1.5 segundos)
    final controller = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this
    );

    // Le damos un efecto de aceleración/desaceleración suave (Curva)
    final Animation<double> animation = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut
    );

    // Escuchamos cada cuadro generado para mover el mapa
    controller.addListener(() {
      // Envolvemos el movimiento en un try-catch por máxima seguridad
      try {
        _mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation),
        );
      } catch (e) {
        // Si un cuadro falla, silenciamos el error para no romper la pantalla roja
        debugPrint("Error en frame de animación: $e");
      }
    });

    // Limpiamos la memoria cuando el vuelo termine
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    // ¡Iniciamos el despegue!
    controller.forward();
  }

  // Función para interactuar con el hardware del GPS
// Función para interactuar con el hardware del GPS (Mejorada con UX)
  Future<void> _obtenerUbicacionActual() async {
    LocationPermission permiso;
    bool servicioHabilitado;

    // 1. PRIMERO validamos y pedimos permisos (lanza el pop-up nativo)
    permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        debugPrint('Permisos denegados por el usuario.');
        return;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      debugPrint('Permisos bloqueados permanentemente.');
      return;
    }

    // 2. LUEGO verificamos si la antena física del celular está encendida
    servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      // Como no podemos encenderlo a la fuerza, guiamos al usuario:
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Activa la ubicación para verte en el mapa.'),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'AJUSTES',
              textColor: Colors.white,
              onPressed: () {
                // Esto abre directamente el menú de GPS del celular
                Geolocator.openLocationSettings();
              },
            ),
          ),
        );
      }
      return;
    }

// 3. Si tiene permisos y el GPS está encendido, trazamos el punto azul
    Position posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
    );

    setState(() {
      _miUbicacion = LatLng(posicion.latitude, posicion.longitude);

      // Efecto de vuelo hacia la ubicación
      _animarCamara(_miUbicacion!, 16.0);
    });
  }

  // Función para mostrar las opciones de reporte
  void _mostrarMenuReportes() {
// Bloqueo de seguridad: No se puede reportar sin GPS
    if (_miUbicacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Esperando señal GPS para poder reportar...'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('¿Qué sucede en la vía?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _construirBotonAlerta(Icons.car_crash, Colors.red, 'Accidente'),
                    _construirBotonAlerta(Icons.local_police, Colors.blue, 'Retén / Policía'),
                    _construirBotonAlerta(Icons.remove_road, Colors.orange, 'Vía Cerrada'),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }
    );
  }

// Función para capturar y enviar el reporte al backend
  void _enviarReporte(String tipoAlerta) async {
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Enviando alerta de $tipoAlerta...'), backgroundColor: Colors.blueAccent, duration: const Duration(seconds: 2)),
    );

    if (_miUbicacion == null) return;

    // Le pasamos el trabajo al servicio
    bool exito = await _mapService.enviarReporte(tipoAlerta, _miUbicacion!.latitude, _miUbicacion!.longitude);

    if (mounted) {
      if (exito) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Reporte guardado con éxito! Gracias por avisar.'), backgroundColor: Colors.green),
        );
        _cargarReportes(); // Refrescamos el mapa
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Error al enviar el reporte.'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  // Función para descargar y renderizar las alertas de la comunidad
  Future<void> _cargarReportes() async {
    // Delegamos la petición de red al servicio
    List<dynamic> datos = await _mapService.obtenerReportes();

    if (datos.isNotEmpty) {
      List<Marker> nuevosMarcadores = datos.map((reporte) {
        IconData iconoAlerta = Icons.warning;
        Color colorAlerta = Colors.orange;

        if (reporte['tipoAlerta'] == 'Accidente') {
          iconoAlerta = Icons.car_crash;
          colorAlerta = Colors.red;
        } else if (reporte['tipoAlerta'] == 'Retén / Policía') {
          iconoAlerta = Icons.local_police;
          colorAlerta = Colors.blueAccent;
        } else if (reporte['tipoAlerta'] == 'Vía Cerrada') {
          iconoAlerta = Icons.remove_road;
          colorAlerta = Colors.orange.shade900;
        }

        return Marker(
          point: LatLng(reporte['latitud'], reporte['longitud']),
          width: 45,
          height: 45,
          child: GestureDetector(
            onTap: () {
              _mostrarDetallePin(
                  reporte['tipoAlerta'],
                  'Alerta reportada por la comunidad en tiempo real.',
                  iconoAlerta,
                  colorAlerta,
                  esReporte: true,
                  idReporte: reporte['idReporte']
              );
            },
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
              ),
              child: Icon(iconoAlerta, color: colorAlerta, size: 28),
            ),
          ),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _marcadoresComunidad = nuevosMarcadores;
        });
      }
    } else {
      // NUEVO: Si la lista de datos está vacía (0 alertas),
      // forzamos al mapa a limpiar todos los pines comunitarios.
      if (mounted) {
        setState(() {
          _marcadoresComunidad = [];
        });
      }
    }
  }

  // Función para descargar y dibujar los Puntos de Interés de una ruta específica
  Future<void> _cargarPoisDeRuta(int idRuta) async {
    List<dynamic> datos = await _mapService.obtenerPoisDeRuta(idRuta);

    if (datos.isNotEmpty) {
      List<Marker> nuevosPois = datos.map((poi) {
        IconData iconoPoi = Icons.place;
        Color colorPoi = Colors.purple;

        if (poi['idTipo'] == 1) { iconoPoi = Icons.local_gas_station; colorPoi = Colors.teal; }
        else if (poi['idTipo'] == 2) { iconoPoi = Icons.restaurant; colorPoi = Colors.brown; }
        else if (poi['idTipo'] == 3) { iconoPoi = Icons.camera_alt; colorPoi = Colors.green.shade700; }
        else if (poi['idTipo'] == 4) { iconoPoi = Icons.build; colorPoi = Colors.blueGrey; }

        return Marker(
          point: LatLng(poi['latitud'], poi['longitud']),
          width: 35,
          height: 35,
          child: GestureDetector(
            onTap: () => _mostrarDetallePin(poi['nombre'] ?? 'Punto de Interés', 'Instalación en ruta.', iconoPoi, colorPoi),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                border: Border.all(color: colorPoi, width: 2),
                boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)],
              ),
              child: Icon(iconoPoi, color: colorPoi, size: 20),
            ),
          ),
        );
      }).toList();

      if (mounted) {
        setState(() { _marcadoresPoi = nuevosPois; });
      }
    }
  }
  // Función para escuchar el GPS continuamente en segundo plano
  void _iniciarRastreoGps() async {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    LocationPermission permiso = await Geolocator.checkPermission();

    // Si el usuario no ha dado permisos, no intentamos rastrear
    if (!servicioHabilitado || permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
      return;
    }

    // Configuramos la sensibilidad del GPS
    const LocationSettings opcionesGps = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Se actualiza cada 5 metros recorridos
    );

    // Abrimos el canal de comunicación con la antena
    _rastreadorGps = Geolocator.getPositionStream(locationSettings: opcionesGps).listen(
            (Position posicion) {
          if (mounted) {
            setState(() {
              _miUbicacion = LatLng(posicion.latitude, posicion.longitude);
              _velocidadActualKmH = (posicion.speed * 3.6).clamp(0.0, 999.0);

              // NUEVO: Calculamos los kilómetros faltantes en tiempo real
              // Calculamos los kilómetros faltantes en tiempo real
              if (_modoNavegacion && _puntosDeRuta.isNotEmpty) {
                final destinoFinal = _puntosDeRuta.last;
                const distanciaMatematica = Distance();

                _distanciaRestanteKm = distanciaMatematica.as(LengthUnit.Meter, _miUbicacion!, destinoFinal) / 1000.0;

                if (_distanciaRestanteKm < 0.05) {
                  _finalizarViajeConExito();
                } else {
                  // NUEVO: Comprobamos en cada paso si nos salimos de la ruta
                  _verificarDesvio();
                }
              }
            });
          }
        }
    );
  }
  // Constructor de botones circulares para el menú de reportes
  Widget _construirBotonAlerta(IconData icono, Color color, String texto) {
    return InkWell(
      onTap: () => _enviarReporte(texto),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icono, color: color, size: 32)
          ),
          const SizedBox(height: 8),
          Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
  // Función universal para mostrar detalles al tocar un pin en el mapa
// Función universal para mostrar detalles al tocar un pin en el mapa
// 1. Agregamos el parámetro opcional "idReporte" al final de la firma
  void _mostrarDetallePin(String titulo, String descripcion, IconData icono, Color color, {bool esReporte = false, int? idReporte}) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                    radius: 35,
                    backgroundColor: color.withOpacity(0.15),
                    child: Icon(icono, color: color, size: 40)
                ),
                const SizedBox(height: 16),
                Text(titulo, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(descripcion, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.blueGrey)),
                const SizedBox(height: 24),

                // NUEVO: Botones de validación comunitaria (Solo aparecen en alertas)
                if (esReporte && idReporte != null) ...[
                  const Text('¿Sigue esta alerta en la vía?', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                        icon: const Icon(Icons.thumb_up),
                        label: const Text('Sigue ahí'),
                        onPressed: () async {
                          // Usamos idReporte! en lugar de alerta.idReporte
                          bool exito = await _mapService.votarAlerta(idReporte, 'confirmar');
                          if (exito) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Gracias por confirmar!')));
                            Navigator.pop(context);
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        icon: const Icon(Icons.thumb_down),
                        label: const Text('Ya no está'),
                        onPressed: () async {
                          // Usamos idReporte! en lugar de alerta.idReporte
                          bool exito = await _mapService.votarAlerta(idReporte, 'descartar');
                          if (exito) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voto registrado. Ayudaste a limpiar el mapa.')));
                            Navigator.pop(context);
                            _cargarReportes(); // Refrescamos el mapa para ver si desapareció
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // ... (el botón de cerrar sigue igual)

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CERRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        }
    );
  }
  @override
  void dispose() {
    // Cerramos la conexión con el GPS cuando la pantalla se destruye
    _rastreadorGps?.cancel();
    super.dispose();
  }
  // 5. Hacemos que esto se ejecute automáticamente al abrir esta pantalla
  @override
  void initState() {
    super.initState();
    _obtenerUbicacionActual(); // 1. Centra la cámara la primera vez y pide permisos
    _iniciarRastreoGps();      // 2. NUEVO: Mantiene el punto actualizándose silenciosamente
    _cargarReportes();
    _cargarVehiculoPrincipal();
  }
  // Función para obtener la autonomía del vehículo registrado
// 1. Modificamos la carga para guardar toda la lista
  Future<void> _cargarVehiculoPrincipal() async {
    final vehiculoService = VehiculoService();
    final vehiculos = await vehiculoService.obtenerMisVehiculos();

    if (vehiculos.isNotEmpty && mounted) {
      setState(() {
        _listaVehiculos = vehiculos;
        _vehiculoActivo = vehiculos[0]; // Por defecto selecciona el primero
        _autonomiaMiVehiculo = vehiculos[0]['autonomiaKm'];
      });
    }
  }

  // 2. NUEVO: Menú inferior para elegir qué vehículo estamos manejando
  void _mostrarSelectorVehiculo() {
    if (_listaVehiculos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes vehículos. ¡Ve a tu garaje!'), backgroundColor: Colors.orange),
      );
      return;
    }

    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('¿En qué vehículo viajas hoy?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Construimos la lista de opciones dinámicamente
                ..._listaVehiculos.map((vehiculo) {
                  bool esActivo = _vehiculoActivo != null && _vehiculoActivo!['idVehiculo'] == vehiculo['idVehiculo'];

                  return ListTile(
                    leading: Icon(
                        vehiculo['idCategoria'] == 3 ? Icons.directions_car : Icons.two_wheeler,
                        color: esActivo ? Colors.blueAccent : Colors.grey
                    ),
                    title: Text(vehiculo['marca'], style: TextStyle(fontWeight: esActivo ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text('Autonomía: ${vehiculo['autonomiaKm']} km'),
                    trailing: esActivo ? const Icon(Icons.check_circle, color: Colors.green) : null,
                    onTap: () {
                      // Actualizamos el estado con el nuevo vehículo
                      setState(() {
                        _vehiculoActivo = vehiculo;
                        _autonomiaMiVehiculo = vehiculo['autonomiaKm'];
                      });
                      Navigator.pop(context); // Cerramos el menú
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Vehículo actualizado a ${vehiculo['marca']}'), backgroundColor: Colors.blueAccent),
                      );
                    },
                  );
                }), // IMPORTANTE: El .toList() va implícito por el operador spread (...)
              ],
            ),
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Llamamos a nuestro componente modular
      drawer: const MenuDrawer(),

      appBar: AppBar(
        title: const Text('WayFinder - Explorar'),
        backgroundColor: Colors.blueAccent,
        actions: [
          // NUEVO BOTÓN: Selector de Vehículo Activo
          IconButton(
            icon: const Icon(Icons.swap_calls, color: Colors.white), // Icono de cambio
            tooltip: 'Cambiar Vehículo',
            onPressed: _mostrarSelectorVehiculo,
          ),

          // Tus botones existentes (Garaje y Reportes)
          IconButton(
            icon: const Icon(Icons.garage, color: Colors.white),
            tooltip: 'Mi Garaje',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const GarajeScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_alert, color: Colors.white),
            tooltip: 'Reportar Novedad',
            onPressed: _mostrarMenuReportes,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. EL MAPA COMPLETO Y RESTAURADO
          // 1. EL MAPA COMPLETO Y RESTAURADO
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _miUbicacion ?? const LatLng(7.9333, -72.6),
              initialZoom: 15.0,

              // 🛡️ SOLUCIÓN: Cambiamos 2.0 por 5.0 para evitar el colapso de los polos
              // Un zoom de 5.0 permite ver todo el país (Colombia), pero no el planeta entero.
              minZoom: 5.0,
              maxZoom: 18.49,
            ),
            children: [
              // Capa base: Las calles
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.wayfinder.app',
                maxZoom: 19,
                maxNativeZoom: 19,
              ),
              // Capa de ruta: La línea roja
              PolylineLayer(
                polylines: [
                  if (_puntosDeRuta.isNotEmpty)
                    Polyline(
                      points: _puntosDeRuta,
                      color: Colors.red,
                      strokeWidth: 4.0,
                    ),
                ],
              ),

              // 🛡️ NUEVA CAPA: Radar de Autonomía del Vehículo
              if (_miUbicacion != null && _autonomiaMiVehiculo > 0 && !_modoNavegacion)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _miUbicacion!,
                      color: Colors.tealAccent.withOpacity(0.15), // Relleno verde tecnológico
                      borderColor: Colors.teal, // Borde sólido
                      borderStrokeWidth: 2.0,
                      useRadiusInMeter: true, // ¡Clave! El radio será físico, no en píxeles
                      radius: _autonomiaMiVehiculo * 1000.0, // Convertimos kilómetros a metros
                    ),
                  ],
                ),

              // Capa de pines: Tú, reportes, gasolineras, etc.
              MarkerLayer(
                markers: [
                  ..._marcadores,
                  ..._marcadoresComunidad,
                  ..._marcadoresPoi,
                  if (_miUbicacion != null)
                    Marker(
                      point: _miUbicacion!,
                      width: 25,
                      height: 25,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black45)],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // 3. NUEVO: BARRA DE BÚSQUEDA FLOTANTE (Se oculta si estamos navegando)
          if (!_modoNavegacion)
            Positioned(
              top: 15, left: 15, right: 15,
              child: Card(
                elevation: 5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.blueAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _buscadorController,
                          decoration: const InputDecoration(
                            // Modificamos el texto para educar al usuario
                            hintText: 'Ej. Chapinero, Cúcuta (Agrega la ciudad)',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) => _buscarYNavegar(),
                        ),
                      ),
                      if (_cargando)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                ),
              ),
            ),
          // 2. EL PANEL DE TELEMETRÍA FLOTANTE (Se muestra si _modoNavegacion es true)
          if (_modoNavegacion)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 1. Indicador de Velocidad
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('VELOCIDAD', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text('${_velocidadActualKmH.toStringAsFixed(0)} km/h',
                            style: TextStyle(
                                color: _velocidadActualKmH > 80 ? Colors.redAccent : Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold
                            )
                        ),
                      ],
                    ),

                    // 2. NUEVO: Indicador de Distancia Restante
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('FALTAN', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text('${_distanciaRestanteKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: Colors.greenAccent, // Le damos un toque verde moderno
                                fontSize: 24,
                                fontWeight: FontWeight.bold
                            )
                        ),
                      ],
                    ),

                    // 3. Botón para cancelar la ruta
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Salir'),
                      onPressed: () {
                        setState(() {
                          _modoNavegacion = false;
                          _puntosDeRuta = [];
                          _marcadoresPoi = [];
                          _distanciaRestanteKm = 0.0; // Reiniciamos la distancia al salir
                        });
                      },
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. Nuevo botón del GPS
          FloatingActionButton(
            heroTag: "btnGPS", // Necesario cuando hay múltiples FABs
            onPressed: _obtenerUbicacionActual,
            backgroundColor: Colors.white,
            child: const Icon(Icons.my_location, color: Colors.blueAccent),
          ),
          const SizedBox(height: 16), // Espacio entre los botones
          // 2. Botón de rutas (el que ya tenías)
          FloatingActionButton.extended(
            heroTag: "btnRutas",
            onPressed: _cargando ? null : _mostrarMenuRutas,
            backgroundColor: Colors.blueAccent,
            icon: _cargando
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.format_list_bulleted, color: Colors.white),
            label: const Text("Ver Rutas", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  // 🧠 ALGORITMO DE CONSCIENCIA ESPACIAL (Recálculo dinámico)
  Future<void> _verificarDesvio() async {
    // Escudos: Si no estamos navegando, o ya está recalculando, o no hay destino, no hace nada
    if (!_modoNavegacion || _puntosDeRuta.isEmpty || _recalculando || _destinoActual == null || _miUbicacion == null) return;

    const distanciaMatematica = Distance();
    double distanciaMinima = double.infinity;

    // Escanea todos los nodos de la línea roja para encontrar qué tan lejos estamos de la ruta
    for (var punto in _puntosDeRuta) {
      double distanciaAlPunto = distanciaMatematica.as(LengthUnit.Meter, _miUbicacion!, punto);
      if (distanciaAlPunto < distanciaMinima) {
        distanciaMinima = distanciaAlPunto;
      }
    }

    // LÍMITE DE TOLERANCIA: 50 metros. Si estamos más lejos, activamos el recálculo
    if (distanciaMinima > 50.0) {
      setState(() => _recalculando = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Desvío detectado. Recalculando ruta...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );

      // Pedimos al servidor OSRM una nueva ruta desde DONDE ESTAMOS AHORA hasta la META original
      String puntosOSRM = '${_miUbicacion!.longitude},${_miUbicacion!.latitude};${_destinoActual!.longitude},${_destinoActual!.latitude}';
      List<dynamic> geometria = await _mapService.obtenerGeometriaOSRM(puntosOSRM);

      if (geometria.isNotEmpty && mounted) {
        List<LatLng> nuevaRuta = geometria.map((punto) => LatLng(punto[1], punto[0])).toList();

        setState(() {
          _puntosDeRuta = nuevaRuta; // Actualizamos la línea roja en el mapa
          _recalculando = false;
        });
      } else {
        setState(() => _recalculando = false);
      }
    }
  }
  // Función para cerrar la ruta automáticamente al llegar al destino
  void _finalizarViajeConExito() {
    setState(() {
      _modoNavegacion = false;
      _puntosDeRuta = [];
      _marcadoresPoi = [];
      _distanciaRestanteKm = 0.0;
    });

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.flag_circle, color: Colors.green, size: 60),
              SizedBox(height: 16),
              Text('¡Has llegado!', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text('Llegaste a tu destino con éxito. WayFinder ha finalizado la navegación.', textAlign: TextAlign.center),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () => Navigator.pop(context),
                child: const Text('ENTENDIDO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        )
    );
  }
}