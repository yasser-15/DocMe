import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'home_shell.dart';

/// Root widget.
///
/// `CupertinoApp`, not `MaterialApp`: `liquid_glass_widgets` is Material-free
/// by design. The `Navigator` is wrapped in `GlassNavigationShell`, which is
/// what produces the iOS 26 gel-morph transition where the navigation capsule
/// swells and cross-fades between routes.
class PatientApp extends StatelessWidget {
  const PatientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'DocMe',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(brightness: Brightness.dark),
      home: const HomeShell(),
      builder: (context, child) => GlassNavigationShell(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}