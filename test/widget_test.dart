import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaxtrust/main.dart';

void main() {
  testWidgets('역할 선택 화면이 표시되고 대시보드로 이동한다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaxTrustApp());

    expect(find.textContaining('VAX'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('transporter')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('qualityManager')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('medicalStaff')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('transporter')));
    await tester.pumpAndSettle();
    expect(find.text('운송자 대시보드'), findsOneWidget);
  });
}
