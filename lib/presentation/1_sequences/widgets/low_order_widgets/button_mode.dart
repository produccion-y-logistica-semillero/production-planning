import 'package:flutter/material.dart';

class ButtonMode extends StatelessWidget {
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
    final colorScheme = Theme.of(context).colorScheme;

    return TextButton.icon(
      onPressed: callback,
      label: Text(
        labelText,
        style: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icon(
        icon,
        color: colorScheme.onSecondaryContainer,
        size: 24,
      ),
      style: TextButton.styleFrom(
        backgroundColor: colorScheme.secondaryContainer,
        padding:
            EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
        minimumSize: const Size(220, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
            width: 1,
          ),
        ),
        elevation: 2, // Adds slight elevation for depth
      ),
    );
  }
}
