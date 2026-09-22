import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'package:latlong2/latlong.dart';

class MapService {
  // Centralizamos la IP aquí. Si cambia, solo la modificas en este archivo.
  final String ipServidor = '192.168.1.15';
  final AuthService _authService = AuthService();

  // 1. Descarga la lista de rutas
  Future<List<dynamic>> obtenerRutas() async {
    String? token = await _authService.obtenerToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('http://$ipServidor:8080/api/rutas'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Error en MapService (Rutas): $e");
    }
    return [];
  }

  // 6. Convierte un texto en coordenadas exactas usando OpenStreetMap
// 6. Convierte un texto en coordenadas exactas usando OpenStreetMap (Calibrado para Colombia)
// 6. Geocodificación de Alta Precisión (Filtro Urbano para Colombia)
// 6. Geocodificación de Alta Precisión (Ordenamiento por Importancia Urbana)
// 6. Geocodificación de Precisión Absoluta (Filtro de Casco Urbano vs Polígono)
// 6. Geocodificación Definitiva (Filtro en Cascada para Centros Geométricos)
  Future<LatLng?> buscarCoordenadasDestino(String busqueda) async {
    try {
      final busquedaSegura = Uri.encodeComponent(busqueda);
      // Aumentamos a 15 resultados para no perder el nodo urbano entre la maleza de datos
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$busquedaSegura&format=json&limit=15&countrycodes=co&accept-language=es');

      final response = await http.get(url, headers: {'User-Agent': 'WayFinderApp/1.0'});

      if (response.statusCode == 200) {
        List<dynamic> datos = jsonDecode(response.body);

        if (datos.isNotEmpty) {
          // Ordenamos por importancia de mayor a menor
          datos.sort((a, b) => (b['importance'] ?? 0.0).compareTo(a['importance'] ?? 0.0));

          // FILTRO 1 (El Ideal): Un punto exacto (node) que sea ciudad, pueblo o lugar habitado (place)
          var resultadoIdeal = datos.where((l) => l['osm_type'] == 'node' && l['class'] == 'place').toList();

          // FILTRO 2 (Secundario): Cualquier resultado etiquetado como lugar habitado, aunque no sea un nodo
          var resultadoSecundario = datos.where((l) => l['class'] == 'place').toList();

          var mejorResultado;

          // Ejecutamos la cascada de decisiones
          if (resultadoIdeal.isNotEmpty) {
            mejorResultado = resultadoIdeal.first; // Toma el centro de la ciudad real
          } else if (resultadoSecundario.isNotEmpty) {
            mejorResultado = resultadoSecundario.first;
          } else {
            mejorResultado = datos.first; // Respaldo final
          }

          return LatLng(double.parse(mejorResultado['lat']), double.parse(mejorResultado['lon']));
        }
      }
    } catch (e) {
      print("Error en Geocodificación: $e");
    }
    return null;
  }

  // 2. Descarga los reportes de la comunidad
  Future<List<dynamic>> obtenerReportes() async {
    String? token = await _authService.obtenerToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('http://$ipServidor:8080/api/reportes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      print("Error en MapService (Reportes): $e");
    }
    return [];
  }
  // 3. Enviar un nuevo reporte al backend
  Future<bool> enviarReporte(String tipoAlerta, double lat, double lng) async {
    String? token = await _authService.obtenerToken();
    if (token == null) return false;

    try {
      final response = await http.post(
        Uri.parse('http://$ipServidor:8080/api/reportes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'tipoAlerta': tipoAlerta,
          'latitud': lat,
          'longitud': lng,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Error enviando reporte: $e");
      return false;
    }
  }

  // 4. Descargar los POIs de una ruta específica
  Future<List<dynamic>> obtenerPoisDeRuta(int idRuta) async {
    String? token = await _authService.obtenerToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('http://$ipServidor:8080/api/pois/ruta/$idRuta'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      print("Error obteniendo POIs: $e");
    }
    return [];
  }

  // 5. Conectar con el motor público de OSRM para trazar las calles
  Future<List<dynamic>> obtenerGeometriaOSRM(String puntosOSRM) async {
    try {
      final response = await http.get(
          Uri.parse('http://router.project-osrm.org/route/v1/driving/$puntosOSRM?geometries=geojson')
      );
      if (response.statusCode == 200) {
        var osrmData = jsonDecode(response.body);
        return osrmData['routes'][0]['geometry']['coordinates'];
      }
    } catch (e) {
      print("Error con servidor OSRM: $e");
    }
    return [];
  }
}