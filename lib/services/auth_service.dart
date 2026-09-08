import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  // Recuerda: 10.0.2.2 es el puente mágico entre el emulador y tu servidor en Spring Boot
  final String baseUrl = 'http://192.168.1.13:8080/api/auth';

  // La caja fuerte del celular donde guardaremos el Token
  final storage = const FlutterSecureStorage();

  Future<bool> login(String email, String password) async {
    try {
      // 1. Armamos la petición (igual que en Postman)
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      // 2. Si el servidor nos responde con un 200 OK
      if (response.statusCode == 200) {
        // Extraemos el Token gigantesco que nos mandó Spring Boot
        final token = response.body;

        // Lo guardamos en la caja fuerte del celular con el nombre 'jwt_token'
        await storage.write(key: 'jwt_token', value: token);
        print("¡Login exitoso! Token guardado.");
        return true;
      } else {
        print("Error en el login: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Error de conexión: $e");
      return false;
    }
  }

  // Herramienta extra: Para sacar el token de la caja fuerte cuando queramos pedir las rutas
  Future<String?> obtenerToken() async {
    return await storage.read(key: 'jwt_token');
  }
}