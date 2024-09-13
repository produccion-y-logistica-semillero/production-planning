import 'package:flutter/material.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/low_order_widgets/add_machines_successful.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/low_order_widgets/error_add_machines.dart';

class AddOrderForm extends StatefulWidget {
  final List<MachineTypeEntity> selectedMachines;
  final void Function(String, List<MachineTypeEntity>) onSave;

  const AddOrderForm({
    super.key,
    required this.selectedMachines,
    required this.onSave,
  });

  @override
  AddOrderFormState createState() => AddOrderFormState();
}

class AddOrderFormState extends State<AddOrderForm> {
  final TextEditingController _nameOrder = TextEditingController();
  bool _isNoMachinesModalVisible = false;
  bool _isSuccessModalVisible = false;

  @override
  Widget build(BuildContext context) {
    Color onSecondaryColor = Theme.of(context).colorScheme.onSecondaryContainer;
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Campo para el nombre del trabajo
              Container(
                height: 60,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5),
                margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _nameOrder,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del trabajo',
                    labelStyle: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Contenedor para las máquinas seleccionadas
              Container(
                constraints: const BoxConstraints(maxHeight: 500),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildMachineList(
                        widget.selectedMachines, primaryColor),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Botón Guardar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _saveOrder(_nameOrder.text, widget.selectedMachines);
                    },
                    label: const Text(
                      "Guardar",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    icon: Icon(
                      Icons.save,
                      color: onSecondaryColor,
                    ),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(
                        Theme.of(context).colorScheme.primaryContainer,
                      ),
                      minimumSize: WidgetStateProperty.all(const Size(120, 50)),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isNoMachinesModalVisible)
          _buildOverlay(
            NoMachinesSelectedModal(
              onClose: () {
                setState(() {
                  _isNoMachinesModalVisible = false; // Cerrar el modal
                });
              },
            ),
          ),
        if (_isSuccessModalVisible)
          _buildOverlay(
            SuccessModal(
              onClose: () {
                setState(() {
                  _isSuccessModalVisible = false; // Cerrar el modal
                });
              },
            ),
          ),
      ],
    );
  }

  // Función para construir la lista de máquinas con flechas intercaladas
  List<Widget> _buildMachineList(
      List<MachineTypeEntity> machines, Color primaryColor) {
    List<Widget> machineWidgets = [];

    // Si no hay máquinas seleccionadas, muestra un contenedor vacío
    if (machines.isEmpty) {
      machineWidgets.add(
        const SizedBox(
          height: 500,
        ),
      );
    } else {
      for (int i = 0; i < machines.length; i++) {
        machineWidgets.add(
          Container(
            width: 200,
            margin: const EdgeInsets.symmetric(vertical: 80, horizontal: 10),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Tarea ${i + 1}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  machines[i].name,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'ID: ${machines[i].id}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

        // Si no es el ultimo elemento lo elimina
        if (i < machines.length - 1) {
          machineWidgets.add(
            const Icon(
              Icons.arrow_forward,
              size: 30,
              color: Colors.grey,
            ),
          );
        }
      }
    }

    return machineWidgets;
  }

  // Función para guardar la orden
  _saveOrder(String name, List<MachineTypeEntity> selectedMachines) {
    if (name.isNotEmpty && selectedMachines.isNotEmpty) {
      widget.onSave(name, selectedMachines);
      setState(() {
        _isSuccessModalVisible = true;
      });
    } else {
      setState(() {
        _isNoMachinesModalVisible = true;
      });
    }
  }

  // Función para mostrar los modales sobre toda la pantalla
  Widget _buildOverlay(Widget modal) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isNoMachinesModalVisible = false;
                _isSuccessModalVisible = false;
              });
            },
            child: const SizedBox(
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Center(child: modal),
        ],
      ),
    );
  }
}
