import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  // Recuerda: 192.168.1.13 es el puente entre el emulador y tu servidor
  final String baseUrl = 'http://192.168.1.13:8080/api/auth';

  // La caja fuerte del celular donde guardaremos el Token
  final storage = const FlutterSecureStorage();

  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final token = response.body;
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

  // Función para registrar un usuario nuevo
  Future<bool> registrarUsuario(String nombre, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/registro'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'nombreCompleto': nombre,
          'email': email,
          'password': password,
        }),
      );

      // Spring Boot devuelve 201 (CREATED) si todo sale bien
      if (response.statusCode == 201) {
        return true;
      } else {
        print("Error del servidor: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error de conexión al registrar: $e");
      return false;
    }
  }

  // Herramienta extra: Para sacar el token de la caja fuerte cuando queramos pedir las rutas
  Future<String?> obtenerToken() async {
    return await storage.read(key: 'jwt_token');
  }
  // Función para cerrar sesión destruyendo el token
  Future<void> logout() async {
    await storage.delete(key: 'jwt_token');
    print("Sesión cerrada. Token eliminado.");
  }
}