import 'package:flutter/material.dart';

import 'gcode_example_page.dart';

class GcodeCoreExampleApp extends StatelessWidget {
  const GcodeCoreExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'G-code Core Example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
      useMaterial3: true,
    ),
    home: const GcodeExamplePage(),
  );
}
