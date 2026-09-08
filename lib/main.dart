import 'package:flutter/material.dart';
import 'screens/login_screen.dart'; // Importamos nuestra pantalla

void main() {
  runApp(const WayFinderApp());
}

class WayFinderApp extends StatelessWidget {
  const WayFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Quitamos la etiqueta roja de "DEBUG"
      title: 'WayFinder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginScreen(), // ¡Le decimos que inicie en el Login!
    );
  }
}
