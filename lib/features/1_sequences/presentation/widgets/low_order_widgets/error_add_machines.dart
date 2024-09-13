import 'package:flutter/material.dart';

class NoMachinesSelectedModal extends StatelessWidget {
  final VoidCallback onClose;

  const NoMachinesSelectedModal({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;

    return Stack(
      children: [
        GestureDetector(
          onTap: onClose, // Cerrar el modal si se toca fuera
          child: const SizedBox(
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            width: 300,
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "No están llenos todos los campos",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Por favor ingresa el nombre del trabajo y selecciona al menos una máquina.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onClose, // Cerrar modal
                  child: Text(
                    "Cerrar",
                    style: TextStyle(color: primaryColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
