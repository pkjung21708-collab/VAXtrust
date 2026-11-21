import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/main.dart';
import 'package:vaxtrust/models/user_role.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;
  late AppDatabase original;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_flow_');
    databasePath = '${tempDir.path}${Platform.pathSeparator}vaxtrust.db';
    original = AppDatabase.instance;
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    await database.ensureDemoAccounts();
    await database.createUser(
      loginId: 'courier2',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    AppDatabase.instance = database;
  });

  tearDown(() async {
    await database.close();
    AppDatabase.instance = original;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool pressWidget(Element element) {
    switch (element.widget) {
      case ElevatedButton(:final onPressed):
        onPressed?.call();
        return true;
      case TextButton(:final onPressed):
        onPressed?.call();
        return true;
      case IconButton(:final onPressed):
        onPressed?.call();
        return true;
      case InkWell(:final onTap):
        onTap?.call();
        return true;
      default:
        var handled = false;
        element.visitChildren((Element child) {
          if (!handled) {
            handled = pressWidget(child);
          }
        });
        return handled;
    }
  }

  Future<void> invoke(WidgetTester tester, Finder finder) async {
    final Element element = finder.evaluate().single;
    expect(pressWidget(element), isTrue, reason: '누를 수 없는 위젯입니다.');
    await settle(tester);
  }

  Future<void> flushDatabase(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> reopenDatabase(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await database.close();
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      await database.open();
      await database.clearSession();
      AppDatabase.instance = database;
    });
    await tester.pumpWidget(const VaxTrustApp());
    await tester.pump();
  }

  String visibleText(WidgetTester tester) {
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => text.data)
        .whereType<String>()
        .where((String data) => data.trim().isNotEmpty)
        .take(24)
        .join(' | ');
  }

  Future<void> login(
    WidgetTester tester,
    String loginId,
    String password,
  ) async {
    final Finder loginScreen = find.ancestor(
      of: find.text('VAXtrust 콜드체인 관리 시스템'),
      matching: find.byType(Scaffold),
    );
    final Finder fields = find.descendant(
      of: loginScreen,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), loginId);
    await tester.enterText(fields.at(1), password);
    await invoke(
      tester,
      find.descendant(
        of: loginScreen,
        matching: find.widgetWithText(ElevatedButton, '로그인'),
      ),
    );
    for (var attempt = 0; attempt < 4; attempt++) {
      await flushDatabase(tester);
      final int dashboards = find.textContaining('대시보드').evaluate().length;
      final bool loginGone = find
          .text('VAXtrust 콜드체인 관리 시스템')
          .evaluate()
          .isEmpty;
      if (dashboards == 1 && loginGone) {
        break;
      }
    }
    expect(
      find.textContaining('대시보드'),
      findsOneWidget,
      reason: visibleText(tester),
    );
  }

  Future<void> logout(WidgetTester tester) async {
    await invoke(tester, find.byTooltip('로그아웃'));
    await invoke(tester, find.byKey(const Key('confirm-logout')));
    for (var attempt = 0; attempt < 4; attempt++) {
      await flushDatabase(tester);
      final bool loginVisible = find
          .text('VAXtrust 콜드체인 관리 시스템')
          .evaluate()
          .isNotEmpty;
      final bool dashboardGone = find.textContaining('대시보드').evaluate().isEmpty;
      if (loginVisible && dashboardGone) {
        break;
      }
    }
    expect(
      find.text('VAXtrust 콜드체인 관리 시스템'),
      findsOneWidget,
      reason: visibleText(tester),
    );
  }

  String textOf(WidgetTester tester, Key key) {
    return tester.widget<Text>(find.byKey(key)).data!;
  }

  Future<void> openDetail(WidgetTester tester) async {
    await invoke(
      tester,
      find.ancestor(
        of: find.text('LOT-PHASE2-77'),
        matching: find.byType(InkWell),
      ),
    );
    await flushDatabase(tester);
    expect(find.byKey(const Key('shipment-detail')), findsOneWidget);
  }

  testWidgets('운송 건 등록과 역할별 참여 코드 연결', (WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const VaxTrustApp());
    await login(tester, 'courier', 'demo1234');

    expect(find.text('운송자 대시보드'), findsOneWidget);
    expect(find.text('등록한 운송 건이 없습니다.'), findsOneWidget);
    expect(find.text('기존 배송 예시'), findsNothing);
    expect(find.text('VT-24031'), findsNothing);

    await invoke(tester, find.byKey(const Key('open-shipment-setup')));
    expect(find.text('새 배송 등록'), findsWidgets);

    Future<void> enterField(Key key, String value) async {
      final Finder field = find.byKey(key);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pump();
    }

    await enterField(const Key('field-manufacturer'), 'Korea Vaccine');
    await enterField(const Key('field-lot'), 'LOT-PHASE2-77');
    await enterField(const Key('field-origin'), 'Incheon Vaccine Center');
    await enterField(
      const Key('field-destination'),
      'Seoul National University Hospital',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    await tester.pump();
    await invoke(
      tester,
      find.ancestor(of: find.text('날짜 선택'), matching: find.byType(InkWell)),
    );
    await invoke(tester, find.widgetWithText(TextButton, '선택'));

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('register-shipment')));
    await invoke(tester, find.byKey(const Key('register-shipment')));
    await flushDatabase(tester);
    expect(find.byKey(const Key('shipment-detail')), findsOneWidget);

    final String shipmentId = textOf(tester, const Key('shipment-display-id'));
    final String code = textOf(tester, const Key('participation-code-value'));
    final Map<String, String> snapshot = <String, String>{
      'id': shipmentId,
      'vaccine': textOf(tester, const Key('shipment-vaccine')),
      'manufacturer': textOf(tester, const Key('shipment-manufacturer')),
      'lot': textOf(tester, const Key('shipment-lot')),
      'expiry': textOf(tester, const Key('shipment-expiry')),
      'quantity': textOf(tester, const Key('shipment-quantity')),
      'origin': textOf(tester, const Key('shipment-origin')),
      'destination': textOf(tester, const Key('shipment-destination')),
      'status': textOf(tester, const Key('shipment-status')),
    };

    expect(code, startsWith('VX-'));
    expect(shipmentId, startsWith('VT-'));
    expect(shipmentId, isNot(code));
    expect(snapshot['status'], '등록됨');
    expect(snapshot['lot'], 'LOT-PHASE2-77');
    expect(snapshot['origin'], 'Incheon Vaccine Center');
    expect(textOf(tester, const Key('shipment-temp-range')), '2 ~ 8°C');

    await invoke(tester, find.byTooltip('운송 건 목록'));
    expect(find.text('LOT-PHASE2-77'), findsWidgets);
    expect(find.text('등록됨'), findsWidgets);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          final Object? arguments = call.arguments;
          if (arguments is Map) {
            copied = arguments['text'] as String?;
          }
        }
        return null;
      },
    );
    await invoke(tester, find.widgetWithText(TextButton, '복사').first);
    await tester.pump();
    expect(find.text('참여 코드를 복사했습니다.'), findsOneWidget);
    expect(copied, code);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );

    await logout(tester);
    await reopenDatabase(tester);
    await login(tester, 'courier', 'demo1234');
    expect(find.text('LOT-PHASE2-77'), findsWidgets);
    await logout(tester);

    await login(tester, 'quality', 'demo1234');
    expect(find.text('품질관리자 대시보드'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('연결된 운송 건이 없습니다.'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('로트 감사'), findsNothing);
    expect(find.text('관리 운송 건'), findsOneWidget);
    expect(find.text('98%'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('participation-code-field')),
      '없음',
    );
    await invoke(tester, find.byKey(const Key('join-shipment')));
    await flushDatabase(tester);
    expect(find.text('존재하지 않는 참여 코드입니다.'), findsOneWidget);
    expect(find.text('LOT-PHASE2-77'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('participation-code-field')),
      code,
    );
    await invoke(tester, find.byKey(const Key('join-shipment')));
    await flushDatabase(tester);
    expect(find.text('운송 건이 연결되었습니다.'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('LOT-PHASE2-77'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('participation-code-field')),
      code.toLowerCase(),
    );
    await invoke(tester, find.byKey(const Key('join-shipment')));
    await flushDatabase(tester);
    expect(find.text('이미 연결된 운송 건입니다.'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('LOT-PHASE2-77'), findsWidgets);

    await openDetail(tester);
    expect(textOf(tester, const Key('shipment-display-id')), snapshot['id']);
    expect(textOf(tester, const Key('shipment-lot')), snapshot['lot']);
    expect(textOf(tester, const Key('shipment-origin')), snapshot['origin']);
    expect(
      textOf(tester, const Key('shipment-destination')),
      snapshot['destination'],
    );
    expect(textOf(tester, const Key('shipment-status')), '등록됨');
    expect(textOf(tester, const Key('shipment-temp-range')), '2 ~ 8°C');
    expect(find.text('2°C'), findsWidgets);
    expect(find.text('8°C'), findsWidgets);

    await invoke(tester, find.byTooltip('운송 건 목록'));
    await logout(tester);

    await login(tester, 'medical', 'demo1234');
    expect(find.text('의료진 대시보드'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('participation-code-field')),
      ' $code ',
    );
    await tester.ensureVisible(find.byKey(const Key('join-shipment')));
    await invoke(tester, find.byKey(const Key('join-shipment')));
    await flushDatabase(tester);
    expect(find.text('운송 건이 연결되었습니다.'), findsOneWidget);
    expect(find.text('LOT-PHASE2-77'), findsWidgets);

    await openDetail(tester);
    expect(textOf(tester, const Key('shipment-display-id')), snapshot['id']);
    expect(textOf(tester, const Key('shipment-vaccine')), snapshot['vaccine']);
    expect(textOf(tester, const Key('shipment-status')), '등록됨');
    expect(textOf(tester, const Key('quality-review-state')), '검토 전');
    expect(find.byKey(const Key('shipment-manufacturer')), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '운송 정보 자세히 보기'));
    await tester.pump();
    expect(
      textOf(tester, const Key('shipment-manufacturer')),
      snapshot['manufacturer'],
    );
    expect(textOf(tester, const Key('shipment-lot')), snapshot['lot']);
    expect(textOf(tester, const Key('shipment-expiry')), snapshot['expiry']);
    expect(
      textOf(tester, const Key('shipment-quantity')),
      snapshot['quantity'],
    );
    await tester.scrollUntilVisible(
      find.text('온도 그래프와 측정 기록'),
      200,
    );
    await tester.tap(find.widgetWithText(TextButton, '온도 그래프와 측정 기록'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('temperature-data-state')),
      200,
    );
    expect(textOf(tester, const Key('temperature-data-state')), '측정 전');
    expect(find.text('투여 가능'), findsNothing);
    expect(find.text('투여 불가'), findsNothing);

    await invoke(tester, find.byTooltip('운송 건 목록'));
    await logout(tester);

    await login(tester, 'courier2', 'demo1234');
    expect(find.text('운송자 대시보드'), findsOneWidget);
    expect(find.text('LOT-PHASE2-77'), findsNothing);
    expect(find.text(snapshot['id']!), findsNothing);
    expect(find.text('등록한 운송 건이 없습니다.'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
