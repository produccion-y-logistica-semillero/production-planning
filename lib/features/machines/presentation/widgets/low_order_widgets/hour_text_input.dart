import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HourTextInput extends StatelessWidget{

  const HourTextInput({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      child: TextField(
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),  //Only up to 4 digits HH:MM
          TimeInputFormatter(),
        ],
        decoration: const InputDecoration(
          isDense: true, //this attribute is the one that removes the extra padding between the text and the input
          contentPadding: EdgeInsets.all(10),
          labelText: 'Tiempo (HH:MM)',
          hintText: '01:30',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

class TimeInputFormatter extends TextInputFormatter{

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    //If there are more than 2 digits (which means, the hour is written, and now the minutes are being written)
    //then it adds the ':' in between
    if(text.length > 2 &&  !text.contains(':') ){
      return TextEditingValue(
        text: text.substring(0, 2) + ':' +  text.substring(2),
        selection:  TextSelection.collapsed(offset: text.length +1)
      );
    }
    return newValue;
  }
}