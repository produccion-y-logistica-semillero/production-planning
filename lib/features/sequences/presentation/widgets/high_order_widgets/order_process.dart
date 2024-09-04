import 'package:flutter/material.dart';

class OrderProcess extends StatelessWidget {
  final String process;

  const OrderProcess({super.key, required this.process});

  @override
  Widget build(BuildContext context) {
    Color onSecondaryColor = Theme.of(context).colorScheme.onSecondaryContainer;
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Primer Row para el texto
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      process,
                      style: const TextStyle(fontSize: 18, color: Colors.black),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {},
                label: Text(
                  "Guardar",
                  style: TextStyle(color: primaryColor, fontSize: 15),
                ),
                icon: Icon(
                  Icons.save,
                  color: onSecondaryColor,
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.secondaryContainer),
                  minimumSize: WidgetStateProperty.all(const Size(120, 50)),
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () {},
                label: const Text(
                  "Nuevo",
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                icon: Icon(
                  Icons.add,
                  color: onSecondaryColor,
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.primaryContainer),
                  minimumSize: WidgetStateProperty.all(const Size(120, 50)),
                  shape: WidgetStateProperty.all(RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
