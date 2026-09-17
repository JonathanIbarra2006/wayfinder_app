import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class MapService {
  // Centralizamos la IP aquí. Si cambia, solo la modificas en este archivo.
  final String ipServidor = '192.168.1.13';
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