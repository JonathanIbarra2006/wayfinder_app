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
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';

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
  String _filtroActivo = ""; // NUEVO: Guarda el nombre del filtro seleccionado
  List<dynamic> _listaRutasNube = [];
  bool _cargandoRutasNube = true; // 👈 NUEVO: Interruptor dedicado
  // NUEVO: Autonomía del vehículo principal del usuario
// Gestión del vehículo seleccionado
// Gestión del vehículo seleccionado
  List<dynamic> _listaVehiculos = [];
  Map<String, dynamic>? _vehiculoActivo;
  int _autonomiaMiVehiculo = 0;
// 🎥 NUEVA VARIABLE: Control inteligente de la cámara
  bool _seguirUsuario = true;

  // 🛑 NUEVO: Frenos de emergencia para la animación
  AnimationController? _controladorCamara;

// 🧠 NUEVAS VARIABLES: Memoria del recálculo dinámico
  LatLng? _destinoActual;
  bool _recalculando = false;

  // 🗣️ NUEVO: Memoria del Asistente de Voz / Texto
// 🗣️ NUEVO: Memoria del Asistente de Voz / Texto
// 🗣️ NUEVO: Memoria del Asistente de Voz / Texto
  String _instruccionActual = "Sigue la ruta marcada";
  final FlutterTts _asistenteVoz = FlutterTts(); // NUEVO MOTOR DE VOZ

  // 🚦 NUEVAS VARIABLES: Panel de Pre-Visualización
  bool _modoPrevisualizacion = false;
  double _distanciaTotalKm = 0.0;
  int _tiempoEstimadoMin = 0;
// 🎨 NUEVA VARIABLE: Interruptor de diseño
  bool _temaOscuro = false;

// 🗺️ Llave maestra obtenida desde la bóveda segura (.env)
  final String _mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
  // 💾 NUEVO: Base de datos local para guardar el mapa sin internet
  HiveCacheStore? _almacenCache;

  // ⚠️ CAMBIA ESTO POR LA IP DE TU COMPUTADORA (Ej: '192.168.1.X')
  final String ipServidor = '192.168.1.17';

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
        _modoNavegacion = true;
        _destinoActual = rutaPorCarretera.isNotEmpty ? rutaPorCarretera.last : null;

        // 👇 NUEVO: Cálculo matemático inmediato sin esperar al acelerómetro del GPS
        if (_miUbicacion != null && _destinoActual != null) {
          const distanciaMatematica = Distance();
          _distanciaRestanteKm = distanciaMatematica.as(LengthUnit.Meter, _miUbicacion!, _destinoActual!) / 1000.0;
        } else {
          // Si el GPS falla temporalmente, usamos la distancia teórica de la base de datos
          _distanciaRestanteKm = double.parse(ruta['distanciaKm'].toString());
        }
      });

      if (rutaPorCarretera.isNotEmpty) {
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
// 2. Construimos la ruta dinámica: Desde tu punto AZUL hasta el DESTINO
    String puntosOSRM = '${_miUbicacion!.longitude},${_miUbicacion!.latitude};${destino.longitude},${destino.latitude}';

    // NUEVO: Usamos el servicio avanzado
    var rutaCompleta = await _mapService.obtenerRutaCompletaOSRM(puntosOSRM);

    if (rutaCompleta != null) {
      List<dynamic> geometria = rutaCompleta['geometry']['coordinates'];
      List<dynamic> pasos = rutaCompleta['legs'][0]['steps']; // Extraemos las instrucciones

      List<LatLng> rutaPorCarretera = geometria.map((punto) => LatLng(punto[1], punto[0])).toList();

      setState(() {
        _puntosDeRuta = rutaPorCarretera;
        _marcadoresPoi = [];
        _marcadores = [
          Marker(point: destino, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.red, size: 40))
        ];
        _cargando = false;

        // 🚦 CAMBIO CLAVE: Entramos a modo pre-visualización en lugar de navegar directo
        _modoPrevisualizacion = true;
        _destinoActual = destino;

        // Extraemos la distancia (viene en metros) y el tiempo (viene en segundos)
        _distanciaTotalKm = (rutaCompleta['distance'] ?? 0.0) / 1000.0;
        _tiempoEstimadoMin = ((rutaCompleta['duration'] ?? 0) / 60.0).round();

        // Extraemos la instrucción de manejo
        if (pasos.length > 1) {
          _instruccionActual = _traducirManiobra(pasos[1]['maneuver'], pasos[1]['name'] ?? '');
        } else if (pasos.isNotEmpty) {
          _instruccionActual = _traducirManiobra(pasos[0]['maneuver'], pasos[0]['name'] ?? '');
        }
        // Extraemos la instrucción de manejo
        if (pasos.length > 1) {
          _instruccionActual = _traducirManiobra(pasos[1]['maneuver'], pasos[1]['name'] ?? '');
        } else if (pasos.isNotEmpty) {
          _instruccionActual = _traducirManiobra(pasos[0]['maneuver'], pasos[0]['name'] ?? '');
        }
      }); // AQUÍ TERMINA TU setState

      // 🗣️ NUEVO: El celular lee la instrucción en voz alta
      await _asistenteVoz.setLanguage("es-ES");
      await _asistenteVoz.setVolume(1.0);
      await _asistenteVoz.speak(_instruccionActual);

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
  // 🗣️ TRADUCTOR DE NAVEGACIÓN (De máquina a Español)
  String _traducirManiobra(Map<String, dynamic> maneuver, String nombreCalle) {
    String tipo = maneuver['type'] ?? '';
    String modificador = maneuver['modifier'] ?? '';
    String accion = "Continúa en la ruta";

    if (tipo == 'depart') accion = "Inicia tu recorrido";
    else if (tipo == 'arrive') accion = "Llegarás a tu destino";
    else if (tipo == 'turn') {
      if (modificador.contains('left')) accion = "Gira a la izquierda";
      else if (modificador.contains('right')) accion = "Gira a la derecha";
      else if (modificador == 'uturn') accion = "Da la vuelta en U";
      else accion = "Gira";
    } else if (tipo == 'continue') {
      accion = "Continúa recto";
    } else if (tipo == 'roundabout') {
      accion = "En la rotonda, toma la salida";
    }

    if (nombreCalle.isNotEmpty) {
      return "$accion por $nombreCalle";
    }
    return accion;
  }

  // Función para animar el vuelo de la cámara (Estilo Google Maps)
// Función para animar el vuelo de la cámara (Estilo Google Maps - Blindada)
  // Función para animar el vuelo de la cámara (Estilo Google Maps - Blindaje Total)
// Función para animar el vuelo de la cámara (Blindaje Extremo Anti-Gestos)
// Función para animar el vuelo de la cámara (Blindaje Anti-Choques de Gestos)
  void _animarCamara(LatLng destino, double zoomDestino) {
    if (!destino.latitude.isFinite || !destino.longitude.isFinite) return;

    double zoomSeguro = 15.0;
    if (zoomDestino.isFinite) zoomSeguro = zoomDestino.clamp(3.0, 18.0);

    final latInicio = _mapController.camera.center.latitude;
    final lngInicio = _mapController.camera.center.longitude;
    final zoomInicio = _mapController.camera.zoom;

    if (!latInicio.isFinite || !lngInicio.isFinite || !zoomInicio.isFinite) {
      _mapController.move(destino, zoomSeguro);
      return;
    }

    // 🛑 DESTRUYE CUALQUIER ANIMACIÓN PREVIA PARA QUE NO PELEEN ENTRE SÍ
    _controladorCamara?.dispose();

    // CREAMOS EL NUEVO VUELO Y LO GUARDAMOS EN LA VARIABLE GLOBAL
    _controladorCamara = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    final animation = CurvedAnimation(parent: _controladorCamara!, curve: Curves.easeInOut);

    final latTween = Tween<double>(begin: latInicio, end: destino.latitude);
    final lngTween = Tween<double>(begin: lngInicio, end: destino.longitude);
    final zoomTween = Tween<double>(begin: zoomInicio, end: zoomSeguro);

    _controladorCamara!.addListener(() {
      try {
        final lat = latTween.evaluate(animation);
        final lng = lngTween.evaluate(animation);
        final z = zoomTween.evaluate(animation);

        if (lat.isFinite && lng.isFinite && z.isFinite) {
          _mapController.move(LatLng(lat, lng), z);
        }
      } catch (e) {
        debugPrint("Frame ignorado");
      }
    });

    _controladorCamara!.forward();
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
    try {
      List<dynamic> puntos = await _mapService.obtenerPoisDeRuta(idRuta);

      List<Marker> nuevosPines = puntos.map((poi) {
        int tipo = poi['idTipo']; // Leemos qué tipo de negocio es

        return Marker(
          point: LatLng(poi['latitud'], poi['longitud']),
          width: 45,
          height: 45,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: Icon(
              _obtenerIconoPoi(tipo), // Invoca el ícono exacto de tu diccionario
              color: _obtenerColorPoi(tipo), // Invoca el color exacto de tu diccionario
              size: 24,
            ),
          ),
        );
      }).toList();

      setState(() {
        // Asignamos los pines estilizados al mapa
        _marcadoresPoi = nuevosPines;
      });
    } catch (e) {
      debugPrint("Error cargando POIs de la ruta: $e");
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
    // BORRA ESTE BLOQUE:
    // const LocationSettings opcionesGps = LocationSettings(
    //   accuracy: LocationAccuracy.high,
    //   distanceFilter: 5,
    // );

    // Y REEMPLÁZALO POR ESTE NUEVO MOTOR:
    LocationSettings opcionesGps;

    if (defaultTargetPlatform == TargetPlatform.android) {
      opcionesGps = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: true,
        // 🛡️ AQUÍ ESTÁ LA MAGIA: El servicio de notificación permanente
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "El asistente de WayFinder está activo",
          notificationTitle: "Navegación en curso",
          enableWakeLock: true, // Evita que el procesador se duerma
        ),
      );
    } else {
      opcionesGps = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

    // Abrimos el canal de comunicación con la antena
// Abrimos el canal de comunicación con la antena
    _rastreadorGps = Geolocator.getPositionStream(locationSettings: opcionesGps).listen(
            (Position posicion) {
          if (mounted) {
            setState(() {
              _miUbicacion = LatLng(posicion.latitude, posicion.longitude);
              _velocidadActualKmH = (posicion.speed * 3.6).clamp(0.0, 999.0);

              // Calculamos los kilómetros faltantes en tiempo real
              if (_modoNavegacion && _puntosDeRuta.isNotEmpty) {
                final destinoFinal = _puntosDeRuta.last;
                const distanciaMatematica = Distance();

                _distanciaRestanteKm = distanciaMatematica.as(LengthUnit.Meter, _miUbicacion!, destinoFinal) / 1000.0;

                if (_distanciaRestanteKm < 0.05) {
                  _finalizarViajeConExito();
                } else {
                  // Comprobamos en cada paso si nos salimos de la ruta
                  _verificarDesvio();
                }

                // 🎥 SOLUCIÓN PASO 3: Solo movemos la cámara si NO estamos explorando
                if (_seguirUsuario) {
                  _animarCamara(_miUbicacion!, 17.0);
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
    _rastreadorGps?.cancel();
    _controladorCamara?.dispose(); // 🛑 NUEVO: Limpiamos la memoria del vuelo
    super.dispose();
  }
  // 5. Hacemos que esto se ejecute automáticamente al abrir esta pantalla
// ☁️ NUEVA FUNCIÓN: Trae las rutas de Spring Boot sin bloquear la pantalla
  Future<void> _cargarRutasNube() async {
    List<dynamic> rutas = await _mapService.obtenerRutas();
    if (mounted) {
      setState(() {
        _listaRutasNube = rutas;
        _cargandoRutasNube = false; // 👈 NUEVO: Apagamos el motor de carga
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _prepararMemoriaOffline();
    _obtenerUbicacionActual();
    _iniciarRastreoGps();
    _cargarReportes();
    _cargarVehiculoPrincipal();
    _cargarRutasNube(); // 👈 NUEVA LÍNEA: Descarga las rutas al abrir el mapa
  }

  // 💾 NUEVA FUNCIÓN: Crea una carpeta secreta en el teléfono para guardar el mapa
  Future<void> _prepararMemoriaOffline() async {
    final directorio = await getTemporaryDirectory();
    final rutaCarpeta = Directory('${directorio.path}/mapa_wayfinder_cache');

    if (!await rutaCarpeta.exists()) {
      await rutaCarpeta.create();
    }

    if (mounted) {
      setState(() {
        _almacenCache = HiveCacheStore(rutaCarpeta.path);
      });
    }
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
        backgroundColor: Colors.blueAccent, // Opcional: podrías cambiar esto a negro si _temaOscuro es true
        actions: [
          // 🎨 NUEVO BOTÓN: Modo Nocturno
          IconButton(
            icon: Icon(_temaOscuro ? Icons.light_mode : Icons.dark_mode, color: Colors.white),
            tooltip: 'Cambiar Tema',
            onPressed: () {
              setState(() {
                _temaOscuro = !_temaOscuro;
              });
            },
          ),

          // Selector de Vehículo Activo (el que ya tienes)
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
              minZoom: 5.0,
              maxZoom: 18.49,

              // 🎥 NUEVO: Detectamos si el usuario movió el mapa con el dedo
              // 🎥 NUEVO: Detectamos si el usuario movió el mapa con el dedo
              onPositionChanged: (posicion, tieneGesto) {
                if (tieneGesto) {
                  // 🛑 SI EL USUARIO TOCA EL MAPA, APAGAMOS EL PILOTO AUTOMÁTICO INMEDIATAMENTE
                  _controladorCamara?.stop();

                  // Si estamos navegando, desactivamos el seguimiento
                  if (_modoNavegacion && _seguirUsuario) {
                    setState(() => _seguirUsuario = false);
                  }
                }
              },
            ),
            children: [
              // Capa base: Gráficos de alta definición estilo Google Maps
              // Capa base: Gráficos de alta definición estilo Google Maps
              TileLayer(
                urlTemplate: _temaOscuro
                    ? 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/tiles/256/{z}/{x}/{y}@2x?access_token=$_mapboxToken'
                    : 'https://api.mapbox.com/styles/v1/mapbox/navigation-day-v1/tiles/256/{z}/{x}/{y}@2x?access_token=$_mapboxToken',
                userAgentPackageName: 'com.wayfinder.app',
                maxZoom: 19,
                maxNativeZoom: 19,
                // 💾 MAGIA OFFLINE: Si la memoria está lista, guarda y lee desde el celular
                tileProvider: _almacenCache != null
                    ? CachedTileProvider(store: _almacenCache!)
                    : null,
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
          // 4. NUEVO: PANEL DE ASISTENTE PASO A PASO (Turn-by-Turn)
          if (_modoNavegacion)
            Positioned(
              top: 120, // Lo ubicamos justo debajo de la telemetría negra
              left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green.shade800, // Verde característico de carretera
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.turn_right, color: Colors.white, size: 32),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        _instruccionActual,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 🚦 NUEVO: PANEL INFERIOR DE PRE-VISUALIZACIÓN (Resumen del Viaje)
          if (_modoPrevisualizacion)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 5)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Resumen del Viaje', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            const Icon(Icons.timer, color: Colors.blueAccent, size: 32),
                            const SizedBox(height: 5),
                            Text('$_tiempoEstimadoMin min', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Container(height: 40, width: 2, color: Colors.grey.shade300), // Divisor
                        Column(
                          children: [
                            const Icon(Icons.route, color: Colors.blueAccent, size: 32),
                            const SizedBox(height: 5),
                            Text('${_distanciaTotalKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 🛡️ ALERTA INTELIGENTE DE AUTONOMÍA
                    if (_autonomiaMiVehiculo > 0 && _distanciaTotalKm > _autonomiaMiVehiculo)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 15),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red),
                            const SizedBox(width: 10),
                            Expanded(child: Text('El destino supera la autonomía de tu vehículo (${_autonomiaMiVehiculo}km).', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13))),
                          ],
                        ),
                      ),

                    Row(
                      children: [
                        // Botón de Cancelar
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _modoPrevisualizacion = false;
                              _puntosDeRuta = [];
                              _marcadores = [];
                            });
                          },
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                              side: BorderSide(color: Colors.red.shade200, width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                          ),
                          child: const Icon(Icons.close, color: Colors.red),
                        ),
                        const SizedBox(width: 15),
                        // Botón de Iniciar
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _modoPrevisualizacion = false;
                                _modoNavegacion = true; // 🔥 ¡Arranca el viaje y enciende los paneles de navegación!
                              });
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                            ),
                            icon: const Icon(Icons.navigation, color: Colors.white),
                            label: const Text('INICIAR VIAJE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ) // Fin del ElevatedButton de Iniciar Viaje
                      ],
                    )
                  ],
                ),
              ),
            ),
// 📱 PANEL INFERIOR DESLIZANTE (Explorar)
          if (!_modoNavegacion && !_modoPrevisualizacion)
            DraggableScrollableSheet(
              initialChildSize: 0.08,
              minChildSize: 0.08,
              maxChildSize: 0.5,
              builder: (BuildContext context, ScrollController scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, -2))],
                  ),
                  child: ListView(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12, bottom: 20),
                          width: 40, height: 5,
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text("Explorar", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ),
                      const SizedBox(height: 15),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            _crearFiltroPoi("Gasolineras", Icons.local_gas_station, Colors.orange),
                            const SizedBox(width: 10),
                            _crearFiltroPoi("Restaurantes", Icons.restaurant, Colors.red),
                            const SizedBox(width: 10),
                            _crearFiltroPoi("Talleres", Icons.build, Colors.blueGrey),
                            const SizedBox(width: 10),
                            _crearFiltroPoi("Miradores", Icons.camera_alt, Colors.green),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text("Rutas Recomendadas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),

                      // 👇 NUEVA LÓGICA: Muestra carga, muestra texto vacío, o dibuja las tarjetas
                      if (_cargandoRutasNube)
                        const Center(child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(),
                        )),
                      if (!_cargandoRutasNube && _listaRutasNube.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text("No hay rutas disponibles por ahora.", style: TextStyle(color: Colors.grey)),
                        ),
                      if (!_cargandoRutasNube && _listaRutasNube.isNotEmpty)
                        ..._listaRutasNube.map((ruta) => _tarjetaRuta(ruta)),
                    ],
                  ),
                );
              },
            ),
        ], // <--- ESTE ES EL CORCHETE QUE CIERRA LOS CHILDREN DEL STACK
      ),
// Reemplaza desde "floatingActionButton:" hasta el final del Scaffold por esto:
      floatingActionButton: _modoNavegacion
      // 1. MODO CONDUCCIÓN: Solo mostramos el recentrado si el usuario soltó la cámara
          ? (!_seguirUsuario
          ? FloatingActionButton(
        heroTag: 'btn_recentrar',
        backgroundColor: Colors.white,
        elevation: 4,
        onPressed: () {
          setState(() => _seguirUsuario = true);
          if (_miUbicacion != null) {
            _animarCamara(_miUbicacion!, 17.0);
          }
        },
        child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 28),
      )
          : null) // Si ya está centrado, no mostramos ningún botón
      // 2. MODO EXPLORACIÓN: Mostramos tus botones clásicos
// 2. MODO EXPLORACIÓN: Mostramos el botón de GPS
          : FloatingActionButton(
        heroTag: "btnGPS",
        onPressed: _obtenerUbicacionActual,
        backgroundColor: Colors.white,
        child: const Icon(Icons.my_location, color: Colors.blueAccent),
      ),
    ); // <-- Fin del Scaffold
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

  // 🎨 WIDGET: Botón de filtro para Puntos de Interés
// 🎨 WIDGET: Botón de filtro dinámico
  Widget _crearFiltroPoi(String titulo, IconData icono, Color colorPrimario) {
    bool seleccionado = _filtroActivo == titulo; // ¿Soy el botón presionado?

    return ActionChip(
      elevation: seleccionado ? 4 : 2,
      pressElevation: 4,
      shadowColor: Colors.black12,
      backgroundColor: seleccionado ? colorPrimario.withOpacity(0.15) : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: seleccionado ? colorPrimario : Colors.grey.shade200,
            width: seleccionado ? 1.5 : 1.0,
          )
      ),
      avatar: Icon(icono, size: 18, color: colorPrimario),
      label: Text(
          titulo,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: seleccionado ? colorPrimario : Colors.black87
          )
      ),
      onPressed: () => _aplicarFiltroPoi(titulo),
    );
  }
  // 🎨 DISEÑO: Asigna un ícono específico según el ID de la base de datos
  IconData _obtenerIconoPoi(int idTipo) {
    switch (idTipo) {
      case 1: return Icons.local_gas_station; // Gasolineras
      case 2: return Icons.restaurant;        // Restaurantes
      case 3: return Icons.landscape;         // Miradores
      case 4: return Icons.build;             // Talleres
      default: return Icons.location_on;
    }
  }

  // 🎨 DISEÑO: Asigna un color corporativo a cada categoría
  Color _obtenerColorPoi(int idTipo) {
    switch (idTipo) {
      case 1: return Colors.orange.shade700;
      case 2: return Colors.red.shade600;
      case 3: return Colors.green.shade600;
      case 4: return Colors.blueGrey.shade700;
      default: return Colors.redAccent;
    }
  }
  // ⚙️ LÓGICA: Traer POIs del backend y dibujarlos
// ⚙️ LÓGICA (FASE 4): Radar Híbrido - Traer POIs de Spring Boot y del Mundo
  Future<void> _aplicarFiltroPoi(String categoria) async {
    if (_filtroActivo == categoria) {
      setState(() {
        _filtroActivo = "";
        _marcadoresPoi = [];
      });
      return;
    }

    setState(() {
      _filtroActivo = categoria;
      _cargando = true;
    });

    try {
      // 1. Buscamos tus lugares Premium (Spring Boot -> Supabase)
      List<dynamic> puntosLocales = await _mapService.obtenerPoisPorCategoria(categoria);

      // 2. Encendemos el Radar Global alrededor de tu ubicación (Overpass API)
      List<dynamic> puntosGlobales = [];
      if (_miUbicacion != null) {
        puntosGlobales = await _mapService.obtenerPoisGlobales(
            categoria,
            _miUbicacion!.latitude,
            _miUbicacion!.longitude
        );
      }

      // 3. Fusionamos ambas bases de datos
      List<dynamic> todosLosPuntos = [...puntosLocales, ...puntosGlobales];

      // 4. Dibujamos el mapa diferenciando los tuyos de los genéricos
      List<Marker> nuevosPines = todosLosPuntos.map((poi) {
        int tipo = poi['idTipo'];
        bool esGlobal = poi['esGlobal'] ?? false; // Buscamos la etiqueta secreta

        return Marker(
          point: LatLng(poi['latitud'], poi['longitud']),
          width: esGlobal ? 35 : 45, // Los tuyos son un poco más grandes
          height: esGlobal ? 35 : 45,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                // Borde grueso a color para los tuyos, borde gris fino para los globales
                color: esGlobal ? Colors.grey.shade400 : _obtenerColorPoi(tipo),
                width: esGlobal ? 1.0 : 2.5,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: Icon(
              _obtenerIconoPoi(tipo),
              // Ícono gris para los genéricos, color corporativo vibrante para los tuyos
              color: esGlobal ? Colors.grey.shade600 : _obtenerColorPoi(tipo),
              size: esGlobal ? 18 : 24,
            ),
          ),
        );
      }).toList();

      setState(() {
        _marcadoresPoi = nuevosPines;
        _cargando = false;
      });

    } catch (e) {
      debugPrint("Error cargando Radares Híbridos: $e");
      setState(() => _cargando = false);
    }
  }
  // 🎨 WIDGET: Tarjeta premium para cada ruta
// 🎨 WIDGET: Tarjeta premium conectada a la base de datos
  Widget _tarjetaRuta(Map<String, dynamic> ruta) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15, left: 20, right: 20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))]
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.motorcycle, color: Colors.blue),
        ),
        title: Text(ruta['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Icon(Icons.terrain, size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text(ruta['dificultad'], style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
              const SizedBox(width: 15),
              const Icon(Icons.straighten, size: 16, color: Colors.teal),
              const SizedBox(width: 4),
              Text('${ruta['distanciaKm']} km', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () async {
          // Cierra el panel deslizante (si estás usando un Draggable no es necesario el pop, pero lo mantenemos por si acaso)
          double distanciaRuta = double.parse(ruta['distanciaKm'].toString());

          if (_autonomiaMiVehiculo > 0 && distanciaRuta > _autonomiaMiVehiculo) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('⚠️ PRECAUCIÓN: Tu vehículo (${_autonomiaMiVehiculo}km) no tiene autonomía suficiente.'), backgroundColor: Colors.red.shade800),
            );
          }

          String? token = await _authService.obtenerToken();
          if (token != null) {
            _trazarRutaEnMapa(ruta);
            _cargarPoisDeRuta(ruta['idRuta']);
          }
        },
      ),
    );
  }
}