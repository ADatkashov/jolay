import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

import 'src/router.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [requiredRoleProvider.overrideWithValue('DRIVER')],
      child: const JolayDriverApp(),
    ),
  );
}

class JolayDriverApp extends ConsumerWidget {
  const JolayDriverApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'JOLAY Driver',
    debugShowCheckedModeBanner: false,
    theme: jolayTheme(),
    darkTheme: jolayDarkTheme(),
    themeMode: ref.watch(themeModeProvider),
    locale: ref.watch(localeProvider),
    supportedLocales: supportedLocales,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: ref.watch(driverRouterProvider),
  );
}
