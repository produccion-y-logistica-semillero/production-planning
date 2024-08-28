import 'package:flutter/widgets.dart';
import 'package:production_planning/features/machines/presentation/widgets/low_order_widgets/hour_text_input.dart';

class NewMachineHourField extends StatelessWidget{
  final String text;

  NewMachineHourField({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 430,
                  child: Text(text, maxLines: 2,)
                ),
                const HourTextInput(),
              ],
            );
  }
}