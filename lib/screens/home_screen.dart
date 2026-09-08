import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();

  List<LatLng> _puntosDeRuta = [];
  List<Marker> _marcadores = []; // NUEVO: Aquí guardaremos los "Pines"
  bool _cargando = false;

  void _obtenerRutasYPois() async {
    setState(() { _cargando = true; });

    String? token = await _authService.obtenerToken();

    if (token != null) {
      try {
        // 1. Pedimos la ruta principal a tu Backend
        final response = await http.get(
          Uri.parse('http://192.168.1.13:8080/api/rutas'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (response.statusCode == 200) {
          List<dynamic> rutasExtraidas = jsonDecode(response.body);

          if (rutasExtraidas.isNotEmpty) {
            var miRuta = rutasExtraidas[0];
            int idRuta = miRuta['idRuta']; // Extraemos el ID para buscar sus POIs
            List<dynamic> coordenadasJson = miRuta['coordenadas'];

            // 2. Trazado curvo con OSRM (Lo que hicimos la sesión anterior)
            String puntosOSRM = coordenadasJson.map((p) => '${p[0]},${p[1]}').join(';');
            final osrmResponse = await http.get(
                Uri.parse('http://router.project-osrm.org/route/v1/driving/$puntosOSRM?geometries=geojson')
            );

            List<LatLng> rutaPorCarretera = [];
            if (osrmResponse.statusCode == 200) {
              var osrmData = jsonDecode(osrmResponse.body);
              List<dynamic> geometria = osrmData['routes'][0]['geometry']['coordinates'];
              rutaPorCarretera = geometria.map((punto) => LatLng(punto[1], punto[0])).toList();
            }

            // 3. NUEVO: Pedimos los Puntos de Interés de esta ruta específica a tu Backend
            final poiResponse = await http.get(
              Uri.parse('http://192.168.1.13:8080/api/pois/ruta/$idRuta'),
              headers: {'Authorization': 'Bearer $token'},
            );

            List<Marker> pines = [];
            if (poiResponse.statusCode == 200) {
              List<dynamic> poisJson = jsonDecode(poiResponse.body);

              // Transformamos el JSON en Marcadores visuales de Flutter
              pines = poisJson.map((poi) {
                // Si el idTipo es 1 (Estación de Servicio), mostramos un icono de gasolina
                IconData icono = poi['idTipo'] == 1 ? Icons.local_gas_station : Icons.location_on;
                Color colorPin = poi['idTipo'] == 1 ? Colors.orange : Colors.blue;

                return Marker(
                  width: 80.0,  // Ampliamos el ancho
                  height: 80.0, // Ampliamos el alto para que quepa el texto
                  point: LatLng(poi['latitud'], poi['longitud']),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Le dice a la columna que ocupe solo el espacio necesario
                    children: [
                      Icon(icono, color: colorPin, size: 35.0),
                      Flexible(
                        child: Text(
                          poi['nombre'].toString().split(' ')[0],
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis, // Si el texto es muy largo, pone "..." en lugar de romperse
                        ),
                      )
                    ],
                  ),
                );
              }).toList();
            }

            // 4. Actualizamos la pantalla con la línea y los pines
            setState(() {
              _puntosDeRuta = rutaPorCarretera;
              _marcadores = pines;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ruta y Puntos de Interés cargados'), backgroundColor: Colors.green),
            );
          }
        }
      } catch (e) {
        print("Error de red: $e");
      }
    }

    setState(() { _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WayFinder - Mapa'),
        backgroundColor: Colors.blueAccent,
      ),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(7.9275, -72.5977),
          initialZoom: 13.0,
          minZoom: 4.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.wayfinder.app',
          ),
          PolylineLayer(
            polylines: [
              if (_puntosDeRuta.isNotEmpty)
                Polyline(
                  points: _puntosDeRuta,
                  color: Colors.red,
                  strokeWidth: 5.0,
                ),
            ],
          ),
          // NUEVO: La capa que dibuja los marcadores (POIs) por encima de las líneas
          MarkerLayer(
            markers: _marcadores,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _cargando ? null : _obtenerRutasYPois,
        backgroundColor: Colors.blueAccent,
        child: _cargando
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.alt_route, color: Colors.white),
      ),
    );
  }
}