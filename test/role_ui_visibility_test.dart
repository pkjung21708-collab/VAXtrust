import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaxtrust/data/shipment_analytics.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_excursion.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/widgets/quality_review_panel.dart';
import 'package:vaxtrust/widgets/shipment_custody_panels.dart';
import 'package:vaxtrust/widgets/temperature_status_card.dart';

void main() {
  final DateTime at = DateTime.utc(2026, 11, 21, 1);

  ShipmentRecord shipment({
    required ShipmentStatus status,
    int assigneeUserId = 1,
  }) {
    return ShipmentRecord(
      id: 7,
      ownerUserId: 1,
      assigneeUserId: assigneeUserId,
      participationCode: 'VX-ROLE',
      vaccine: '스카이셀플루',
      manufacturer: '제조사',
      lot: 'LOT-ROLE',
      expiryDate: '2027-11-21',
      quantity: 4,
      origin: '창고',
      destination: '병원',
      targetRange: '2 ~ 8°C',
      tempMin: 2,
      tempMax: 8,
      status: status,
      createdAt: at,
      source: ShipmentRecord.userInputSource,
    );
  }

  AppUser user(UserRole role) {
    return AppUser(
      id: switch (role) {
        UserRole.transporter => 1,
        UserRole.qualityManager => 2,
        UserRole.medicalStaff => 3,
      },
      loginId: role.name,
      role: role,
      createdAt: at,
    );
  }

  Future<void> pumpCard(WidgetTester tester, UserRole role) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemperatureStatusCard(
            user: user(role),
            shipment: shipment(status: ShipmentStatus.inTransit),
            latest: null,
            excursions: const [],
            latestActions: const {},
            scenario: null,
            onChanged: () async {},
          ),
        ),
      ),
    );
  }

  testWidgets('운송자는 대응 매뉴얼과 대응 기록에 들어갈 수 있다', (tester) async {
    await pumpCard(tester, UserRole.transporter);
    expect(find.byKey(const Key('response-manual-button')), findsOneWidget);
    expect(find.byKey(const Key('record-response-button')), findsOneWidget);
    expect(find.textContaining('운전 중'), findsNothing);
    expect(find.byKey(const Key('quality-review-save')), findsNothing);
    expect(find.byKey(const Key('confirm-receipt')), findsNothing);
  });

  testWidgets('품질관리자 카드에는 대응 매뉴얼 버튼과 기록 작성 버튼이 없다', (tester) async {
    await pumpCard(tester, UserRole.qualityManager);
    expect(find.byKey(const Key('response-manual-button')), findsNothing);
    expect(find.byKey(const Key('record-response-button')), findsNothing);
    expect(find.text('대응 매뉴얼'), findsOneWidget);
  });

  testWidgets('의료진 카드에는 대응 매뉴얼과 기록 작성 버튼이 없다', (tester) async {
    await pumpCard(tester, UserRole.medicalStaff);
    expect(find.byKey(const Key('response-manual-button')), findsNothing);
    expect(find.byKey(const Key('record-response-button')), findsNothing);
    expect(find.text('대응 매뉴얼'), findsNothing);
    expect(find.text('매뉴얼 열기'), findsNothing);
    expect(find.text('온도 이탈: 없음'), findsOneWidget);
    expect(find.text('온도 상세'), findsOneWidget);
    expect(find.textContaining('운영 위험'), findsNothing);
  });

  testWidgets('품질 검토 작성과 인수는 해당 역할만 본다', (tester) async {
    final ShipmentRecord item = shipment(status: ShipmentStatus.completed);
    final ShipmentInsight insight = const ShipmentAnalytics().inspect(
      shipment: item,
      readings: const [],
      excursions: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              QualityReviewPanel(
                user: user(UserRole.qualityManager),
                shipment: item,
                insight: insight,
                latest: null,
                reviews: const [],
                onChanged: () async {},
              ),
              ShipmentReceiptPanel(
                user: user(UserRole.medicalStaff),
                shipment: item,
                receipt: null,
                reviews: const [],
                excursions: const [],
                actions: const [],
                onChanged: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('quality-review-save')), findsOneWidget);
    expect(find.byKey(const Key('confirm-receipt')), findsOneWidget);
    expect(find.byKey(const Key('medical-shipment-summary')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QualityReviewPanel(
            user: user(UserRole.medicalStaff),
            shipment: item,
            insight: insight,
            latest: null,
            reviews: const [],
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('quality-review-save')), findsNothing);
    expect(find.byKey(const Key('medical-shipment-summary')), findsOneWidget);
    expect(find.text('운송자 조치 기록: 없음'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShipmentReceiptPanel(
            user: user(UserRole.transporter),
            shipment: item,
            receipt: null,
            reviews: const [],
            excursions: const [],
            actions: const [],
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('confirm-receipt')), findsNothing);
  });

  TemperatureExcursion excursion(int id, DateTime started) {
    return TemperatureExcursion(
      id: id,
      shipmentId: 7,
      direction: TemperatureExcursion.aboveMax,
      startedAt: started,
      lastOutOfRangeAt: started.add(const Duration(seconds: 5)),
      recoveredAt: started.add(const Duration(seconds: 10)),
      minTemperature: 9,
      maxTemperature: 12,
      dataGapDetected: false,
      status: TemperatureExcursion.recoveredStatus,
      createdAt: started,
      updatedAt: started,
    );
  }

  test('이탈 기록은 발생 시각과 기록 ID 순으로 정렬한다', () {
    final DateTime same = at.add(const Duration(minutes: 10));
    final List<TemperatureExcursion> sorted = excursionsNewestFirst([
      excursion(1, at),
      excursion(10, same),
      excursion(4, at.add(const Duration(minutes: 30))),
      excursion(11, same),
    ]);
    expect(sorted.map((TemperatureExcursion item) => item.id), [4, 11, 10, 1]);
  });

  testWidgets('현재 온도와 누적 위험도를 구분하고 이탈 기록은 3건만 먼저 보여 준다', (
    tester,
  ) async {
    final ShipmentRecord item = shipment(status: ShipmentStatus.inTransit);
    final DateTime same = at.add(const Duration(minutes: 10));
    final List<TemperatureExcursion> events = [
      excursion(1, at),
      excursion(10, same),
      excursion(4, at.add(const Duration(minutes: 30))),
      excursion(11, same),
    ];
    final TemperatureReading current = TemperatureReading(
      id: 1,
      shipmentId: 7,
      celsius: 5.8,
      measuredAt: at.add(const Duration(hours: 1)),
      recordedAt: at.add(const Duration(hours: 1)),
      source: TemperatureReading.demoVirtualSource,
      assigneeUserId: 1,
    );
    final ShipmentInsight insight = const ShipmentAnalytics().inspect(
      shipment: item,
      readings: [current],
      excursions: events,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TemperatureStatusCard(
              user: user(UserRole.qualityManager),
              shipment: item,
              latest: current,
              excursions: events,
              latestActions: const {},
              scenario: null,
              insight: insight,
              onChanged: () async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('현재 온도 상태: 정상 (5.8°C)'), findsOneWidget);
    expect(find.text('누적 운송 위험도: 높음'), findsOneWidget);
    expect(
      find.text('현재 온도는 정상 범위이지만, 과거 온도 이탈 기록으로 인해 추가 품질 검토가 필요합니다.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('excursion-row-4')), findsOneWidget);
    expect(find.byKey(const Key('excursion-row-11')), findsOneWidget);
    expect(find.byKey(const Key('excursion-row-10')), findsOneWidget);
    expect(find.byKey(const Key('excursion-row-1')), findsNothing);
    expect(find.byKey(const Key('record-response-button')), findsNothing);
    await tester.tap(find.byKey(const Key('show-all-excursions')));
    await tester.pump();
    expect(find.byKey(const Key('excursion-row-1')), findsOneWidget);
  });
}
