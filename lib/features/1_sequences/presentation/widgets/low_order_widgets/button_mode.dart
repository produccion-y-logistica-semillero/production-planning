import 'package:flutter/material.dart';

class ButtonMode extends StatelessWidget{

  final void Function() callback;
  final String labelText;
  final IconData icon;
  final double horizontalPadding;

  const ButtonMode({
    super.key,
    required this.callback,
    required this.labelText,
    required this.icon,
    required this.horizontalPadding,
  });



  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: callback,
      label: Text(
        labelText,
        style: TextStyle(color: Theme.of(context)
            .colorScheme
            .onSecondaryContainer, fontSize: 18),
      ),
      icon: Icon(
        icon,
        color: Theme.of(context)
            .colorScheme
            .onSecondaryContainer,
      ),
      style: TextButton.styleFrom(
        backgroundColor: Theme.of(context)
            .colorScheme
            .secondaryContainer,
        minimumSize: const Size(200, 60),
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}