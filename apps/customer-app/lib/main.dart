import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jolay_core/jolay_core.dart';

import 'src/router.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [requiredRoleProvider.overrideWithValue('CUSTOMER')],
      child: const JolayCustomerApp(),
    ),
  );
}

class JolayCustomerApp extends ConsumerWidget {
  const JolayCustomerApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'JOLAY',
      debugShowCheckedModeBanner: false,
      theme: jolayTheme(),
      darkTheme: jolayDarkTheme(),
      themeMode: ref.watch(themeModeProvider),
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
