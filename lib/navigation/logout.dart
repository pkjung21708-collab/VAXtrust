import 'package:flutter/material.dart';

import '../data/app_database.dart';
import 'app_navigator.dart';

/// 로그인 세션만 지우고 로그인 화면을 루트로 둡니다.
/// 계정, 운송 건, 온도 기록은 지우지 않습니다.
/// 시연용 온도 타이머는 로그인 세션이 아니라 앱 실행에 속하므로 여기서 멈추지 않습니다.
Future<void> endSessionAndShowLogin() async {
  try {
    await AppDatabase.instance.clearSession();
  } on StateError {
    // 저장소를 열지 않은 상태에서도 로그인 화면으로 돌아갑니다.
  }
  final NavigatorState? navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    return;
  }
  navigator.pushNamedAndRemoveUntil(
    loginRouteName,
    (Route<dynamic> route) => false,
  );
}

Future<void> confirmLogout(BuildContext context) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃하면 로그인 화면으로 돌아갑니다. 이 기기에 저장된 계정은 유지됩니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const Key('confirm-logout'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) {
    return;
  }
  await endSessionAndShowLogin();
}

class LogoutAction extends StatelessWidget {
  const LogoutAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '로그아웃',
      onPressed: () => confirmLogout(context),
      icon: const Icon(Icons.logout),
    );
  }
}
