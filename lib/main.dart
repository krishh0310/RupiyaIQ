import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo-day hardening: portrait only (also set in AndroidManifest).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Last-resort safety net: any async error that slipped past a try/catch is
  // logged instead of surfacing as a crash/red screen during the demo.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled async error: $error');
    return true;
  };
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runApp(const ProviderScope(child: RupiyaApp()));
}

class RupiyaApp extends ConsumerWidget {
  const RupiyaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'RupiyaIQ',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
        home: const AppShell(),
      );
}
