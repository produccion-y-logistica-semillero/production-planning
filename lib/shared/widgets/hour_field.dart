import 'package:flutter/widgets.dart';
import 'package:production_planning/shared/widgets/hour_text_input.dart';

class HourField extends StatelessWidget {
  final String text;
  final TextEditingController controller;

  const HourField({super.key, required this.text, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
            width: 430,
            child: Text(
              text,
              maxLines: 2,
            )),
        HourTextInput(
          controller: controller,
        ),
      ],
    );
  }
}
