import 'package:flutter/material.dart';
import '../services/vehiculo_service.dart';

class GarajeScreen extends StatefulWidget {
  const GarajeScreen({super.key});

  @override
  State<GarajeScreen> createState() => _GarajeScreenState();
}

class _GarajeScreenState extends State<GarajeScreen> {
  final VehiculoService _vehiculoService = VehiculoService();
  List<dynamic> _misVehiculos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarVehiculos();
  }

  Future<void> _cargarVehiculos() async {
    setState(() => _cargando = true);
    final vehiculos = await _vehiculoService.obtenerMisVehiculos();
    setState(() {
      _misVehiculos = vehiculos;
      _cargando = false;
    });
  }

  // Formulario en ventana emergente (Modal) para agregar un vehículo
// Formulario en ventana emergente (Modal) para agregar un vehículo
  void _mostrarFormularioNuevoVehiculo() {
    final TextEditingController marcaController = TextEditingController();
    final TextEditingController cilindrajeController = TextEditingController();
    final TextEditingController autonomiaController = TextEditingController();
    int categoriaSeleccionada = 1; // 1 = Moto, 3 = Carro

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // NUEVO: Permite redibujar el contenido del modal
          builder: (context, setStateModal) {
            return AlertDialog(
              title: const Text('Registrar Vehículo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: categoriaSeleccionada,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Motocicleta')),
                        DropdownMenuItem(value: 3, child: Text('Automóvil')),
                      ],
                      // Actualizamos el estado interno del modal
                      onChanged: (value) => setStateModal(() => categoriaSeleccionada = value!),
                      decoration: const InputDecoration(labelText: 'Tipo de Vehículo'),
                    ),
                    TextField(
                      controller: marcaController,
                      decoration: const InputDecoration(labelText: 'Marca / Modelo (Ej: Yamaha MT-09)'),
                    ),
                    TextField(
                      controller: cilindrajeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cilindraje (CC)'),
                    ),
                    TextField(
                      controller: autonomiaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Autonomía máxima (Km)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () async {
                    final marca = marcaController.text.trim();
                    final autonomiaRaw = autonomiaController.text.trim();

                    // 1. Evitamos el fallo silencioso de campos vacíos
                    if (marca.isEmpty || autonomiaRaw.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('La marca y autonomía son obligatorias.'), backgroundColor: Colors.orange),
                      );
                      return;
                    }

                    // 2. Limpieza inteligente: Extrae solo los números, borrando letras o espacios
                    final String stringCilindraje = cilindrajeController.text.replaceAll(RegExp(r'[^0-9]'), '');
                    final String stringAutonomia = autonomiaRaw.replaceAll(RegExp(r'[^0-9]'), '');

                    int cilindrajeLimpio = int.tryParse(stringCilindraje) ?? 0;
                    int autonomiaLimpia = int.tryParse(stringAutonomia) ?? 0;

                    bool exito = await _vehiculoService.agregarVehiculo(
                      categoriaSeleccionada,
                      marca,
                      cilindrajeLimpio,
                      autonomiaLimpia,
                    );

                    if (mounted) {
                      if (exito) {
                        Navigator.pop(context); // Cierra el pop-up
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vehículo guardado en el garaje'), backgroundColor: Colors.green),
                        );
                        _cargarVehiculos(); // Recargamos la lista visual
                      } else {
                        // 3. NUEVO: Si falla, avisamos al usuario
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error al guardar. Revisa la terminal.'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Garaje'),
        backgroundColor: Colors.blueAccent,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _misVehiculos.isEmpty
          ? _construirMensajeVacio()
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _misVehiculos.length,
        itemBuilder: (context, index) {
          final v = _misVehiculos[index];
          final esMoto = v['idCategoria'] == 1;

          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                radius: 30,
                child: Icon(esMoto ? Icons.two_wheeler : Icons.directions_car, color: Colors.blueAccent, size: 30),
              ),
              title: Text(v['marca'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cilindraje: ${v['cilindrajeCc']} CC'),
                    const SizedBox(height: 4),
                    Text('Autonomía: ${v['autonomiaKm']} Km', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormularioNuevoVehiculo,
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Añadir Vehículo', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _construirMensajeVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.garage_outlined, size: 100, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Tu garaje está vacío', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          const Text('Registra tu vehículo para medir la autonomía en tus rutas.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}