import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'data/demo_temperature_session.dart';
import 'navigation/app_navigator.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

/// 앱이 시작되는 입구입니다. 모든 Flutter 앱은 main()부터 실행됩니다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 이번 시연의 저장소는 iOS 로컬 SQLite입니다. 웹용 데이터베이스는 열지 않습니다.
  if (!kIsWeb) {
    await AppDatabase.instance.open();
    // 계정은 유지하고, 이전 실행의 로그인 세션만 지웁니다.
    // 앱을 다시 열면 항상 로그인 화면에서 시작합니다.
    // 이미 운송 중인 건의 상태를 등록으로 되돌리거나, 꺼져 있던 시간의 온도를 만들지 않습니다.
    await AppDatabase.instance.clearSession();
    await AppDatabase.instance.ensureDemoAccounts();
    DemoTemperatureSession.instance.attach();
    await DemoTemperatureSession.instance.restore();
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
      navigatorKey: appNavigatorKey,
      title: 'VAXtrust',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routes: <String, WidgetBuilder>{
        loginRouteName: (BuildContext context) => const LoginScreen(),
      },
      home: const LoginScreen(),
    );
  }
}
