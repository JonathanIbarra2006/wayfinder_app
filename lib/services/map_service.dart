import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'package:latlong2/latlong.dart';

class MapService {
  // Centralizamos la IP aquí. Si cambia, solo la modificas en este archivo.
  final String ipServidor = '192.168.1.17';
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
          Uri.parse('http://router.project-osrm.org/route/v1/driving/$puntosOSRM?geometries=geojson&overview=full')
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
  // 8. Motor OSRM Avanzado (Geometría + Instrucciones paso a paso en Español)
// 8. Motor OSRM Avanzado (Geometría + Instrucciones paso a paso)
  Future<Map<String, dynamic>?> obtenerRutaCompletaOSRM(String puntosOSRM) async {
    try {
      // ⚠️ CORRECCIÓN: Retiramos '&language=es' porque el servidor público lo bloquea
      // En tu función obtenerRutaCompletaOSRM:
      final url = Uri.parse('http://router.project-osrm.org/route/v1/driving/$puntosOSRM?geometries=geojson&steps=true&overview=full');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        var osrmData = jsonDecode(response.body);
        return osrmData['routes'][0];
      } else {
        print("Error OSRM: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Error con servidor OSRM Avanzado: $e");
    }
    return null;
  }
  // 7. Enviar el voto de la comunidad a Spring Boot
  Future<bool> votarAlerta(int idReporte, String accion) async {
    // 1. Obtenemos el token de seguridad
    String? token = await _authService.obtenerToken();
    if (token == null) return false;

    try {
      // 2. Usamos tu variable ipServidor dinámica
      final url = Uri.parse('http://$ipServidor:8080/api/reportes/$idReporte/votar?accion=$accion');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', // Descomentado y activado
        },
      );

      if (response.statusCode == 200) {
        print("Voto registrado: ${response.body}");
        return true;
      } else {
        print("Error al votar. Código: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Error de conexión al votar: $e");
      return false;
    }
  }
// NUEVO: Petición al servidor Spring Boot para traer los negocios por categoría
  Future<List<dynamic>> obtenerPoisPorCategoria(String categoria) async {
    try {
      final token = await _authService.obtenerToken();
      if (token == null) return [];

      // 🛠️ CORRECCIÓN AQUÍ: Usamos tu variable ipServidor armando la URL correctamente
      final url = Uri.parse('http://$ipServidor:8080/api/pois/categoria/$categoria');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        print("El servidor respondió con error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error en API de POIs: $e");
    }
    return [];
  }
  // 🌍 NUEVO (FASE 4): Radar Global en Tiempo Real (Overpass API)
// 🌍 NUEVO (FASE 4): Radar Global en Tiempo Real (Overpass API)
// 🌍 NUEVO (FASE 4): Radar Global en Tiempo Real (Overpass API)
  Future<List<dynamic>> obtenerPoisGlobales(String categoria, double lat, double lng) async {
    String tagOsm = "";
    switch (categoria) {
      case "Gasolineras": tagOsm = '"amenity"="fuel"'; break;
      case "Restaurantes": tagOsm = '"amenity"="restaurant"'; break;
      case "Miradores": tagOsm = '"tourism"="viewpoint"'; break;
      case "Talleres": tagOsm = '"shop"="motorcycle_repair"'; break;
      default: return [];
    }

    // 1. CORRECCIÓN: Subimos el timeout a 30 segundos para permitir el escaneo de 15km (700 km2)
    String query = '[out:json][timeout:30];(node[$tagOsm](around:15000,$lat,$lng);way[$tagOsm](around:15000,$lat,$lng);relation[$tagOsm](around:15000,$lat,$lng););out center;';
    String url = 'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}';

    try {
      final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'WayFinderApp/1.0'}
      );

      if (response.statusCode == 200) {
        var data = json.decode(utf8.decode(response.bodyBytes));

        // 2. CORRECCIÓN: Si el servidor mundial nos bloquea o se queda sin memoria, nos lo dirá aquí
        if (data['remark'] != null) {
          print("⚠️ Advertencia de Overpass (Radar Global): ${data['remark']}");
        }

        List<dynamic> elementos = data['elements'] ?? [];

        return elementos.map((nodo) {
          double latitud = nodo['lat'] ?? nodo['center']['lat'];
          double longitud = nodo['lon'] ?? nodo['center']['lon'];

          return {
            'idPoi': nodo['id'],
            'nombre': nodo['tags'] != null && nodo['tags']['name'] != null
                ? nodo['tags']['name']
                : '$categoria (Radar Global)',
            'idTipo': _traducirCategoriaAId(categoria),
            'latitud': latitud,
            'longitud': longitud,
            'esGlobal': true
          };
        }).toList();
      } else {
        print("El radar global falló con código HTTP: ${response.statusCode}");
      }
    } catch (e) {
      print("Error en Radar Global Overpass: $e");
    }
    return [];
  }

  // Traductor inverso para mantener la compatibilidad con tus diccionarios de diseño
  int _traducirCategoriaAId(String categoria) {
    switch (categoria) {
      case "Gasolineras": return 1;
      case "Restaurantes": return 2;
      case "Miradores": return 3;
      case "Talleres": return 4;
      default: return 0;
    }
  }
}
