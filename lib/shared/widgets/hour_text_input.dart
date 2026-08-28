import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HourTextInput extends StatefulWidget {

  final TextEditingController controller;

  const HourTextInput({super.key, required this.controller});

  @override
  State<HourTextInput> createState() => _HourTextInputState();
}

class _HourTextInputState extends State<HourTextInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Without this, tapping into a pre-filled field places the cursor
    // instead of selecting the existing text. Since the field is capped at
    // 4 digits (LengthLimitingTextInputFormatter), typing a new value
    // without first clearing the old one gets rejected once the cap is
    // hit, so the old value silently "wins" and editing looks broken.
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        widget.controller.selection = TextSelection(
            baseOffset: 0, extentOffset: widget.controller.text.length);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,

          LengthLimitingTextInputFormatter(
              4), //Only up to 4 digits HH:MM, it ignores the ':' in the counting because we already tell that it's .digitsOnly, if we hadn't that, then it would be up to 5, because it would count the ':'
          TimeInputFormatter(),
        ],
        decoration: const InputDecoration(
          isDense:
              true, //this attribute is the one that removes the extra padding between the text and the input
          contentPadding: EdgeInsets.all(10),
          labelText: 'Tiempo (HH:MM)',
          hintText: '01:30',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}


class TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    //If there are more than 2 digits (which means, the hour is written, and now the minutes are being written)
    //then it adds the ':' in between
    if (text.length > 2 && !text.contains(':')) {
      return TextEditingValue(
          text: '${text.substring(0, 2)}:${text.substring(2)}',
          selection: TextSelection.collapsed(offset: text.length + 1));
    }
    return newValue;
  }
}

