import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/app_database.dart';
import 'data/demo_temperature_session.dart';
import 'navigation/app_navigator.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

/// 데스크톱 웹에서 대시보드가 창 너비까지 늘어나지 않게 하는 한계입니다.
/// 휴대폰 폭보다 넓어서 좁은 화면의 기존 배치는 그대로입니다.
const double webContentMaxWidth = 960;

/// 앱이 시작되는 입구입니다. 모든 Flutter 앱은 main()부터 실행됩니다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 웹만 브라우저 IndexedDB를 엽니다. iOS는 기존 sqflite 파일 저장소를 유지합니다.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  await AppDatabase.instance.open();
  // 계정은 유지하고, 이전 실행의 로그인 세션만 지웁니다.
  // 앱을 다시 열면 항상 로그인 화면에서 시작합니다.
  // 이미 운송 중인 건의 상태를 등록으로 되돌리거나, 꺼져 있던 시간의 온도를 만들지 않습니다.
  await AppDatabase.instance.clearSession();
  await AppDatabase.instance.ensureDemoAccounts();
  DemoTemperatureSession.instance.attach();
  await DemoTemperatureSession.instance.restore();
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
      builder: (BuildContext context, Widget? child) {
        final Widget content = child ?? const SizedBox.shrink();
        if (!kIsWeb) {
          return content;
        }
        return ColoredBox(
          color: AppColors.ice,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
              child: content,
            ),
          ),
        );
      },
      routes: <String, WidgetBuilder>{
        loginRouteName: (BuildContext context) => const LoginScreen(),
      },
      home: const LoginScreen(),
    );
  }
}
