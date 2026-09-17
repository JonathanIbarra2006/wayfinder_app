import 'package:flutter/material.dart';
import '../services/vehiculo_service.dart';

class GarajeScreen extends StatefulWidget {
  const GarajeScreen({super.key});

  @override
  State<GarajeScreen> createState() => _GarajeScreenState();
}

class _GarajeScreenState extends State<GarajeScreen> {
  final VehiculoService _vehiculoService = VehiculoService();
  List<dynamic> _vehiculos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarVehiculos();
  }

  Future<void> _cargarVehiculos() async {
    setState(() => _cargando = true);
    final datos = await _vehiculoService.obtenerMisVehiculos();
    setState(() {
      _vehiculos = datos;
      _cargando = false;
    });
  }

  void _mostrarFormularioNuevoVehiculo() {
    final formKey = GlobalKey<FormState>();
    final marcaCtrl = TextEditingController();
    final cilindrajeCtrl = TextEditingController();
    final autonomiaCtrl = TextEditingController();
    int categoriaSeleccionada = 1; // 1 = Moto, 3 = Auto (según tu DB)
    bool guardando = false;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true, // Crucial para que el teclado del móvil no oculte los campos
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom, // Evita colisiones con el teclado
                    left: 24, right: 24, top: 24,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Registrar Vehículo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: categoriaSeleccionada,
                          decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Moto de Calle')),
                            DropdownMenuItem(value: 2, child: Text('Moto Adventure')),
                            DropdownMenuItem(value: 3, child: Text('Automóvil')),
                          ],
                          onChanged: (val) => setModalState(() => categoriaSeleccionada = val!),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: marcaCtrl,
                          decoration: const InputDecoration(labelText: 'Marca y Modelo', border: OutlineInputBorder()),
                          validator: (v) => v!.isEmpty ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: cilindrajeCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Cilindraje (CC)', border: OutlineInputBorder()),
                                validator: (v) => v!.isEmpty ? '*' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: autonomiaCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Autonomía (Km)', border: OutlineInputBorder()),
                                validator: (v) => v!.isEmpty ? '*' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                            onPressed: guardando ? null : () async {
                              if (formKey.currentState!.validate()) {
                                setModalState(() => guardando = true);

                                bool exito = await _vehiculoService.agregarVehiculo(
                                  categoriaSeleccionada,
                                  marcaCtrl.text.trim(),
                                  int.parse(cilindrajeCtrl.text.trim()),
                                  int.parse(autonomiaCtrl.text.trim()),
                                );

                                setModalState(() => guardando = false);

                                if (exito && context.mounted) {
                                  Navigator.pop(context); // Cierra el modal
                                  _cargarVehiculos(); // Recarga la lista de fondo
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Vehículo guardado en el garaje'), backgroundColor: Colors.green),
                                  );
                                }
                              }
                            },
                            child: guardando
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('GUARDAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi Garaje'), backgroundColor: Colors.blueAccent),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _vehiculos.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.two_wheeler, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Aún no tienes vehículos registrados.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vehiculos.length,
        itemBuilder: (context, index) {
          var v = _vehiculos[index];
          // Asignamos icono dependiendo si es moto o carro
          IconData icono = v['idCategoria'] == 3 ? Icons.directions_car : Icons.two_wheeler;
          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Colors.blueAccent.withOpacity(0.1), child: Icon(icono, color: Colors.blueAccent)),
              title: Text(v['marca'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${v['cilindrajeCc']} CC • Autonomía: ${v['autonomiaKm']} Km'),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormularioNuevoVehiculo,
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}