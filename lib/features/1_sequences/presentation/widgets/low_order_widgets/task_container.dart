import 'package:flutter/material.dart';
import 'package:production_planning/features/1_sequences/domain/request_models/new_task_model.dart';

class TaskContainer extends StatelessWidget{

  final NewTaskModel task;
  final int number;
  final void Function() callback;
  final void Function() onDeleteCallback;

  const TaskContainer({
    super.key,
    required this.task,
    required this.number,
    required this.callback,
    required this.onDeleteCallback
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: ()=>callback(),
      child: Container(
              width: 200,
              margin: const EdgeInsets.symmetric(vertical: 80, horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(onPressed: ()=>onDeleteCallback(), icon: Icon(Icons.delete, color: Colors.red,)),
                  Text(
                    'Tarea ${number}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    task.machineName,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Duración: ${task.processingUnit.inHours.toString().padLeft(2, '0')}:${(task.processingUnit.inMinutes - task.processingUnit.inHours*60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    task.description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  )
                ],
              ),
            ),
    );
  }
}