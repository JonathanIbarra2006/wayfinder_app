import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class MenuDrawer extends StatelessWidget {
  const MenuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService(); // Instanciamos el servicio aquí

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blueAccent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.account_circle, size: 60, color: Colors.white),
                SizedBox(height: 10),
                Text('Mi Perfil', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.blueGrey),
            title: const Text('Configuración'),
            onTap: () {
              Navigator.pop(context); // Cierra el menú
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Módulo en construcción...')),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () async {
              Navigator.pop(context); // Cierra el menú visualmente primero
              await authService.logout(); // Destruye el token en la caja fuerte

              if (context.mounted) {
                // Navegamos al login limpiando el historial
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
    );
  }
}