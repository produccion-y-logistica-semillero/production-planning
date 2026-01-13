import 'package:flutter/material.dart';

class InputFieldCustom extends StatelessWidget{


  final double sizedBoxWidth;
  final int maxLines;
  final String title;
  final String hintText;
  final TextEditingController controller;

  const InputFieldCustom({required this.sizedBoxWidth, required this.maxLines, required this.title, required this.hintText, required this.controller, super.key});


  @override
  Widget build(BuildContext context) {
    return Container(

      margin: const EdgeInsets.symmetric(horizontal: 50),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          SizedBox(
            width: sizedBoxWidth,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              decoration: InputDecoration(
                  hintText: hintText,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  isDense:
                      true, //this attribute is the one that removes the extra padding between the text and the input
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  )),
            ),
          )
        ],
      ),
    );
  }
}

