import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/patient_app.dart';

const _qualityKey = 'docme.glass_quality';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore the previously settled quality tier. GlassAdaptiveScope runs a
  // ~3s warmup benchmark on first launch; without persistence that benchmark
  // repeats on every cold start and the user sees degraded glass each time.
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_qualityKey);
  final initialQuality = saved != null
      ? GlassQuality.values.where((q) => q.name == saved).firstOrNull
      : null;

  // Pre-warm the fragment shaders. This is non-blocking disk-to-RAM I/O with
  // zero GPU draw calls, and it prevents the white first-frame flash.
  await LiquidGlassWidgets.initialize();

  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      respectSystemAccessibility: true,
      theme: buildDocMeGlassTheme(),
      adaptiveConfig: GlassAdaptiveScopeConfig(
        initialQuality: initialQuality,
        allowStepUp: true,
        onQualityChanged: (_, quality) =>
            prefs.setString(_qualityKey, quality.name),
      ),
      child: const PatientApp(),
    ),
  );
}