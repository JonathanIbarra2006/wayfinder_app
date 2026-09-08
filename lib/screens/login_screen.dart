import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Estos "controladores" son como ganchos que nos permiten extraer el texto que el usuario escribe
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Llamamos a nuestro mensajero
  final AuthService _authService = AuthService();

  // Esta variable nos ayudará a mostrar un circulito de carga mientras el servidor responde
  bool _isLoading = false;

  void _iniciarSesion() async {
    // 1. Mostramos el estado de carga
    setState(() {
      _isLoading = true;
    });

    // 2. Le decimos al mensajero que intente hacer login
    bool exito = await _authService.login(
      _emailController.text.trim(), // .trim() borra espacios vacíos accidentales
      _passwordController.text,
    );

    // 3. Ocultamos el estado de carga
    setState(() {
      _isLoading = false;
    });

    // 4. Verificamos la respuesta
    if (exito) {
      // Mensaje de éxito
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Bienvenido a WayFinder!'),
          backgroundColor: Colors.green,
        ),
      );

      // Hacemos el salto a la pantalla principal.
      // Usamos pushReplacement para que el usuario no pueda presionar el botón "Atrás" y volver al Login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      // ... el resto del código de error se queda igual
      // Si hubo error, mostramos un mensaje rojo
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Credenciales incorrectas o falla del servidor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // La "cabeza" de la aplicación
      appBar: AppBar(
        title: const Text('WayFinder - Ingreso'),
        backgroundColor: Colors.blueAccent,
      ),
      // El cuerpo principal
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, size: 100, color: Colors.blueAccent),
            const SizedBox(height: 30),

            // Caja de texto del Correo
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 16),

            // Caja de texto de la Contraseña
            TextField(
              controller: _passwordController,
              obscureText: true, // Esto oculta la contraseña con puntitos
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),

            // El Botón de Ingresar
            SizedBox(
              width: double.infinity, // Hace que el botón ocupe todo el ancho
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _iniciarSesion, // Si está cargando, bloquea el botón
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white) // Ruedita de carga
                    : const Text('Ingresar', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}