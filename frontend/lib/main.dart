import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_routes.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'core/localization/app_localizations.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.body,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(ProviderScope(child: JanYukti()));
}

class JanYukti extends StatelessWidget {
  JanYukti({super.key});
  final LanguageController languageController = LanguageController();
  @override
  Widget build(BuildContext context) => LanguageScope(
    controller: languageController,
    child: MaterialApp(
      title: 'janYukti',
      debugShowCheckedModeBanner: false,
      builder: _withWhiteStatusBar,
      theme: AppTheme.light,
      initialRoute: Routes.welcome,
      onGenerateRoute: AppRoutes.generate,
    ),
  );
}

Widget _withWhiteStatusBar(BuildContext context, Widget? child) {
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: AppColors.white100,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
    child: Stack(
      children: [
        ?child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top,
          child: const IgnorePointer(child: ColoredBox(color: AppColors.body)),
        ),
      ],
    ),
  );
}
