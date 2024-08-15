import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class NewMachineInputField extends StatelessWidget{

  final double sizedBoxWidth;
  final int maxLines;
  final String title;
  final String hintText;
  final TextEditingController controller;

  const NewMachineInputField({required this.sizedBoxWidth, required this.maxLines, required this.title, required this.hintText, required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
              margin: EdgeInsets.symmetric(horizontal: 50),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  SizedBox(width: sizedBoxWidth,),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLines: maxLines,
                      decoration: InputDecoration(
                        hintText: hintText,
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        )
                      ),
                    ),
                  )
                ],
              ),
            );
  }
}