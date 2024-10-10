//for this case I decided to use provider instead of bloc since it's pretty basic only
//to have state for the menu, but nothing more, so it would be overkill to implement it with Bloc

import 'package:flutter/material.dart';

class SideMenuProvider extends ChangeNotifier{
  int selectedOption = 0;
  bool expanded = true;

  void changeOption(int index){
    selectedOption = index;
    notifyListeners();
  }

  void changeExpansion(){
    expanded = !expanded;
    notifyListeners();
  }
}