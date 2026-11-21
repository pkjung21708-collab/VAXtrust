import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaxtrust/main.dart';
import 'package:vaxtrust/navigation/app_navigator.dart';
import 'package:vaxtrust/screens/login_screen.dart';
import 'package:vaxtrust/screens/shipment_setup_screen.dart';
import 'package:vaxtrust/screens/transporter_dashboard.dart';

void main() {
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget routedApp({required Widget home}) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      routes: <String, WidgetBuilder>{
        loginRouteName: (BuildContext context) => const LoginScreen(),
      },
      home: home,
    );
  }

  testWidgets('로그인 화면에서 빈 입력은 거절하고 회원가입으로 이동한다', (WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const VaxTrustApp());

    expect(find.text('VAXtrust 콜드체인 관리 시스템'), findsOneWidget);
    expect(find.text('운송자: courier / demo1234'), findsOneWidget);
    expect(find.text('역할을 선택하세요'), findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pump();
    expect(find.text('아이디와 비밀번호를 입력해 주세요.'), findsOneWidget);

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('가입하기'), findsOneWidget);
    expect(find.text('운송자'), findsOneWidget);
    expect(find.text('품질관리자'), findsOneWidget);
    expect(find.text('의료진'), findsOneWidget);

    await tester.ensureVisible(find.text('의료진'));
    await tester.tap(find.text('의료진'));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('뒤로가기'));
    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    expect(find.text('작성 중인 가입 정보'), findsOneWidget);

    await tester.tap(find.text('계속 작성'));
    await tester.pumpAndSettle();
    expect(find.text('가입하기'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('뒤로가기'));
    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그인 화면으로'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
  });

  testWidgets('빈 운송 등록 화면에서는 확인 없이 로그인으로 돌아간다', (WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(routedApp(home: const ShipmentSetupScreen()));

    await tester.tap(find.byTooltip('로그인 화면으로 돌아가기'));
    await tester.pumpAndSettle();

    expect(find.text('작성 중인 운송 정보'), findsNothing);
    expect(find.text('VAXtrust 콜드체인 관리 시스템'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  });

  testWidgets('작성 중인 운송 정보는 확인 후에만 로그인으로 돌아간다', (WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(routedApp(home: const ShipmentSetupScreen()));

    await tester.enterText(find.byType(TextField).first, 'Korea Vaccine');
    await tester.tap(find.byTooltip('로그인 화면으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('작성 중인 운송 정보'), findsOneWidget);

    await tester.tap(find.text('계속 작성'));
    await tester.pumpAndSettle();
    expect(find.text('새 배송 등록'), findsOneWidget);

    await tester.tap(find.byTooltip('로그인 화면으로 돌아가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그인 화면으로'));
    await tester.pumpAndSettle();

    expect(find.text('VAXtrust 콜드체인 관리 시스템'), findsOneWidget);
    expect(find.text('새 배송 등록'), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  });

  testWidgets('로그아웃하면 이전 대시보드로 돌아갈 수 없다', (WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(routedApp(home: const TransporterDashboard()));

    await tester.tap(find.byTooltip('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-logout')));
    await tester.pumpAndSettle();

    expect(find.text('VAXtrust 콜드체인 관리 시스템'), findsOneWidget);
    expect(find.text('운송자 대시보드'), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  });
}
