import 'package:flutter/material.dart';
import 'package:production_planning/features/1_sequences/domain/request_models/new_task_model.dart';

class TaskContainer extends StatelessWidget {
  final NewTaskModel task;
  final int number;
  final void Function() callback;
  final void Function() onDeleteCallback;

  const TaskContainer({
    super.key,
    required this.task,
    required this.number,
    required this.callback,
    required this.onDeleteCallback,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onDoubleTap: () => callback(),
      child: Container(
        width: 220,
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(2, 3),
            ),
          ],
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 0.8,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              onPressed: onDeleteCallback,
              icon: Icon(Icons.delete, color: colorScheme.error),
              tooltip: 'Eliminar Tarea',
            ),
            const SizedBox(height: 8),
            Text(
              'Tarea $number',
              style: TextStyle(
                fontSize: 18,
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              task.machineName,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Duración: ${task.processingUnit.inHours.toString().padLeft(2, '0')}:${(task.processingUnit.inMinutes - task.processingUnit.inHours * 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              task.description,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onPrimaryContainer.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
