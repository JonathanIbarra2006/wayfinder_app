import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class VehiculoService {
  // Misma IP que utilizas para auth y reportes
  final String baseUrl = 'http://192.168.1.13:8080/api/vehiculos';
  final AuthService _authService = AuthService();

  // POST: Enviar un nuevo vehículo al servidor
  Future<bool> agregarVehiculo(int idCategoria, String marca, int cilindraje, int autonomia) async {
    String? token = await _authService.obtenerToken();
    if (token == null) return false;

    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'idCategoria': idCategoria,
          'marca': marca,
          'cilindrajeCc': cilindraje,
          'autonomiaKm': autonomia,
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      } else {
        print("Rechazo del backend: Código ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error de red al guardar vehículo: $e");
      return false;
    }
  }

  // GET: Descargar los vehículos registrados por el usuario
  Future<List<dynamic>> obtenerMisVehiculos() async {
    String? token = await _authService.obtenerToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      print("Error al obtener vehículos: $e");
    }
    return [];
  }
}