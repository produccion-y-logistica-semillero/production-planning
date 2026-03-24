# production_planning

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## THIS readme is not structured by now...

## IMPORTANT
-   the navigator that controls what's shown in the main page, its on features/main_page/presentation/widgets/main_navigator.dart, there's
    where the providers of each page are provided

-   State management and events can be handled either in pages or in high order widgets, I made this explicit disctintion between 
    High and low order widgets, so that it's easy to understand that high level are the ones used in pages, but that can also have
    logic of events and state inside them, they can also inject functionality, and the low level ones are the ones that are purely decorative
    and should not have any logic or own implementations, they have all injected