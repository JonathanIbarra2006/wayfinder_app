import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 🔐 NUEVA IMPORTACIÓN

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Asegura que Flutter esté listo
  await dotenv.load(fileName: ".env");       // 🔐 CARGAMOS LOS SECRETOS AQUÍ

  // CORRECCIÓN: Cambiamos MyApp por WayFinderApp
  runApp(const WayFinderApp());
}

class WayFinderApp extends StatelessWidget {
  const WayFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WayFinder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      // Configuramos las rutas nombradas para facilitar la navegación
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
      home: const PantallaDeArranque(),
    );
  }
}

// Esta pantalla es un "Splash Screen" invisible que toma la decisión de navegación
class PantallaDeArranque extends StatefulWidget {
  const PantallaDeArranque({super.key});

  @override
  State<PantallaDeArranque> createState() => _PantallaDeArranqueState();
}

class _PantallaDeArranqueState extends State<PantallaDeArranque> {
  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  void _verificarSesion() async {
    final token = await AuthService().obtenerToken();

    // Le damos una pequeña pausa visual para que no parpadee bruscamente
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      if (token != null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.blueAccent,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}