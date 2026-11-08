import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

/// 앱이 시작되는 입구입니다. 모든 Flutter 앱은 main()부터 실행됩니다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 이번 시연의 저장소는 iOS 로컬 SQLite입니다. 웹용 데이터베이스는 열지 않습니다.
  if (!kIsWeb) {
    await AppDatabase.instance.open();
  }
  runApp(const VaxTrustApp());
}

/// 앱 이름, 테마, 첫 화면을 정하는 최상위 위젯입니다.
class VaxTrustApp extends StatelessWidget {
  const VaxTrustApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAXtrust',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const LoginScreen(),
    );
  }
}
