import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/demo_risk_settings.dart';
import 'package:vaxtrust/data/demo_scenario_policy.dart';
import 'package:vaxtrust/data/shipment_analytics.dart';
import 'package:vaxtrust/data/temperature_chart_model.dart';
import 'package:vaxtrust/data/temperature_policy.dart';
import 'package:vaxtrust/models/demo_scenario.dart';
import 'package:vaxtrust/models/excursion_action.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_excursion.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/widgets/temperature_chart_view.dart';

void main() {
  const ShipmentAnalytics analytics = ShipmentAnalytics();
  final DateTime start = DateTime.utc(2026, 11, 17, 5);

  ShipmentRecord shipment({
    int id = 1,
    ShipmentStatus status = ShipmentStatus.inTransit,
  }) {
    return ShipmentRecord(
      id: id,
      ownerUserId: 1,
      assigneeUserId: 1,
      participationCode: 'VX-TEST',
      vaccine: '인플루엔자 4가',
      manufacturer: 'Korea Vaccine',
      lot: 'LOT-$id',
      expiryDate: '2027-11-16',
      quantity: 10,
      origin: '인천',
      destination: '서울',
      targetRange: '2 ~ 8°C',
      tempMin: 2,
      tempMax: 8,
      status: status,
      createdAt: start,
      source: ShipmentRecord.userInputSource,
    );
  }

  TemperatureReading reading(int id, DateTime at, double celsius) {
    return TemperatureReading(
      id: id,
      shipmentId: 1,
      celsius: celsius,
      measuredAt: at,
      recordedAt: at,
      source: TemperatureReading.demoVirtualSource,
      assigneeUserId: 1,
    );
  }

  TemperatureExcursion excursion({
    required int id,
    required String direction,
    required DateTime startedAt,
    DateTime? last,
    DateTime? recoveredAt,
    required double min,
    required double max,
    bool gap = false,
    bool open = false,
  }) {
    final DateTime end = last ?? startedAt;
    return TemperatureExcursion(
      id: id,
      shipmentId: 1,
      direction: direction,
      startedAt: startedAt,
      lastOutOfRangeAt: end,
      recoveredAt: recoveredAt,
      minTemperature: min,
      maxTemperature: max,
      dataGapDetected: gap,
      status: open
          ? TemperatureExcursion.openStatus
          : TemperatureExcursion.recoveredStatus,
      createdAt: startedAt,
      updatedAt: end,
    );
  }

  List<TemperatureReading> steadyReadings() {
    return <TemperatureReading>[
      reading(1, start, 4),
      reading(2, start.add(const Duration(seconds: 5)), 4.5),
      reading(3, start.add(const Duration(seconds: 10)), 5),
    ];
  }

  test('이탈이 없고 측정이 충분하면 낮음이고 검토 전이다', () {
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment(),
      readings: steadyReadings(),
      excursions: const <TemperatureExcursion>[],
    );
    expect(insight.risk.level, OperationalRiskLevel.low);
    expect(insight.review, QualityReviewState.notStarted);
    expect(insight.temperature, TemperatureCondition.inRange);
    expect(insight.risk.reasons.join(' '), contains('이탈 기록이 없습니다'));
    expect(DemoRiskSettings.limitation, contains('접종 가능 여부를 의미하지 않습니다'));
    expect(DemoRiskSettings.durationBasis, contains('60초'));
    expect(DemoRiskSettings.durationBasis, contains('품질 판정 기준이 아닙니다'));
  });

  test('측정이 없으면 평가 불가고 임의의 위험도를 만들지 않는다', () {
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment(),
      readings: const <TemperatureReading>[],
      excursions: const <TemperatureExcursion>[],
    );
    expect(insight.risk.level, OperationalRiskLevel.unknown);
    expect(insight.temperature, TemperatureCondition.none);
    expect(insight.review, QualityReviewState.notStarted);
    expect(insight.readingCount, 0);
  });

  test('데이터 공백만 있으면 낮음으로 내리지 않는다', () {
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment(),
      readings: <TemperatureReading>[
        reading(1, start, 4),
        reading(2, start.add(const Duration(hours: 1)), 5),
        reading(3, start.add(const Duration(hours: 1, seconds: 5)), 5),
      ],
      excursions: const <TemperatureExcursion>[],
    );
    expect(insight.readingGap, isTrue);
    expect(insight.risk.level, OperationalRiskLevel.unknown);
    expect(insight.risk.gapLimitsJudgement, isTrue);
    expect(insight.review, QualityReviewState.notStarted);
  });

  test('경미한 이탈은 주의이고 품질 검토는 위험도와 따로 필요하다', () {
    final DateTime outAt = start.add(const Duration(seconds: 15));
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment(),
      readings: <TemperatureReading>[
        ...steadyReadings(),
        reading(4, outAt, 8.4),
        reading(5, outAt.add(const Duration(seconds: 5)), 4),
      ],
      excursions: <TemperatureExcursion>[
        excursion(
          id: 7,
          direction: TemperatureExcursion.aboveMax,
          startedAt: outAt,
          recoveredAt: outAt.add(const Duration(seconds: 5)),
          min: 8.4,
          max: 8.4,
        ),
      ],
    );
    expect(insight.excursions.maxAboveExcess, closeTo(0.4, 0.001));
    expect(insight.excursions.durationLabel, '관측된 이탈 지속시간 0초');
    expect(insight.risk.reasons, contains('원인 및 조치 기록: 미작성'));
    expect(insight.risk.reasons, contains('데이터 공백 없음'));
    expect(insight.risk.level, OperationalRiskLevel.caution);
    expect(insight.review, QualityReviewState.needed);
    expect(insight.temperature, TemperatureCondition.recovered);
    expect(insight.risk.reasons.join('\n'), isNot(contains('접종 가능')));
  });

  test('반복 상한 이탈과 1.5도 초과는 높음이고 공백 지속시간은 단정하지 않는다', () {
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment(),
      readings: <TemperatureReading>[
        reading(1, start, 9.5),
        reading(2, start.add(const Duration(hours: 1)), 4),
      ],
      excursions: <TemperatureExcursion>[
        excursion(
          id: 1,
          direction: TemperatureExcursion.aboveMax,
          startedAt: start,
          recoveredAt: start.add(const Duration(hours: 1)),
          min: 9.5,
          max: 9.5,
          gap: true,
        ),
        excursion(
          id: 2,
          direction: TemperatureExcursion.aboveMax,
          startedAt: start.add(const Duration(hours: 2)),
          min: 9.2,
          max: 9.2,
          open: true,
          gap: true,
        ),
      ],
    );
    expect(insight.excursions.aboveCount, 2);
    expect(insight.excursions.maxAboveExcess, closeTo(1.5, 0.001));
    expect(insight.excursions.durationLabel, '이탈 지속시간 확인 필요');
    expect(insight.excursions.observedDuration, isNull);
    expect(insight.risk.level, OperationalRiskLevel.high);
    expect(insight.risk.gapLimitsJudgement, isTrue);
    expect(insight.review, QualityReviewState.needed);
    expect(insight.excursions.open, isTrue);
    final String reasons = insight.risk.reasons.join('\n');
    expect(reasons, contains('상한 이탈 2회'));
    expect(reasons, contains('1.5°C'));
    expect(reasons, contains('데이터 공백'));
  });

  test('하한 미달 정도를 계산하고 이벤트 수와 운송 건수를 구분한다', () {
    final ShipmentRecord warm = shipment(
      id: 2,
      status: ShipmentStatus.completed,
    );
    final ShipmentInsight first = analytics.inspect(
      shipment: shipment(),
      readings: steadyReadings(),
      excursions: <TemperatureExcursion>[
        excursion(
          id: 1,
          direction: TemperatureExcursion.belowMin,
          startedAt: start,
          last: start.add(const Duration(seconds: 10)),
          recoveredAt: start.add(const Duration(seconds: 15)),
          min: 0.5,
          max: 1.9,
        ),
        excursion(
          id: 2,
          direction: TemperatureExcursion.belowMin,
          startedAt: start.add(const Duration(minutes: 5)),
          last: start.add(const Duration(minutes: 5, seconds: 5)),
          recoveredAt: start.add(const Duration(minutes: 5, seconds: 10)),
          min: 1.2,
          max: 1.8,
        ),
      ],
    );
    expect(first.excursions.maxBelowShortfall, closeTo(1.5, 0.001));
    expect(first.excursions.observedDuration?.inSeconds, 15);
    expect(first.excursions.durationLabel, contains('15초'));
    final ShipmentInsight second = analytics.inspect(
      shipment: warm,
      readings: const <TemperatureReading>[],
      excursions: const <TemperatureExcursion>[],
    );
    final FleetSummary summary = analytics.summarize(
      shipments: <ShipmentRecord>[shipment(), warm],
      insights: <ShipmentInsight>[first, second],
    );
    expect(summary.shipmentCount, 2);
    expect(summary.inTransitCount, 1);
    expect(summary.completedCount, 1);
    expect(summary.excursionEventCount, 2);
    expect(summary.shipmentsWithExcursion, 1);
    expect(summary.reviewNeededCount, 1);
  });

  test('59초는 주의이고 60초는 시연 기준의 높음이다', () {
    ShipmentInsight at(int seconds) {
      final DateTime outAt = start.add(const Duration(seconds: 15));
      return analytics.inspect(
        shipment: shipment(),
        readings: <TemperatureReading>[
          ...steadyReadings(),
          reading(4, outAt, 8.4),
          reading(5, outAt.add(Duration(seconds: seconds)), 8.4),
          reading(6, outAt.add(Duration(seconds: seconds + 5)), 4),
        ],
        excursions: <TemperatureExcursion>[
          excursion(
            id: 4,
            direction: TemperatureExcursion.aboveMax,
            startedAt: outAt,
            last: outAt.add(Duration(seconds: seconds)),
            recoveredAt: outAt.add(Duration(seconds: seconds + 5)),
            min: 8.4,
            max: 8.4,
          ),
        ],
        actionRecorded: const <int, bool>{4: true},
      );
    }

    final ShipmentInsight short = at(59);
    final ShipmentInsight boundary = at(60);
    expect(short.excursions.observedDuration?.inSeconds, 59);
    expect(short.risk.level, OperationalRiskLevel.caution);
    expect(short.risk.reasons, contains('관측된 이탈 지속시간 59초'));
    expect(boundary.excursions.observedDuration?.inSeconds, 60);
    expect(boundary.risk.level, OperationalRiskLevel.high);
    expect(
      boundary.risk.reasons,
      contains('시연용 기준에서 관측된 이탈 지속시간이 60초 이상입니다'),
    );
    expect(boundary.risk.reasons, contains('원인 및 조치 기록: 작성 완료'));
    expect(boundary.review, QualityReviewState.needed);
  });

  test('공백이 있는 이탈은 시간을 더하지 않고 확인된 편차만 반영한다', () {
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment(),
      readings: <TemperatureReading>[
        reading(1, start, 8.4),
        reading(2, start.add(const Duration(hours: 2)), 4),
        reading(3, start.add(const Duration(hours: 2, seconds: 5)), 4),
      ],
      excursions: <TemperatureExcursion>[
        excursion(
          id: 8,
          direction: TemperatureExcursion.aboveMax,
          startedAt: start,
          last: start.add(const Duration(hours: 2)),
          recoveredAt: start.add(const Duration(hours: 2)),
          min: 8.4,
          max: 8.4,
          gap: true,
        ),
      ],
    );
    expect(insight.excursions.observedDuration, isNull);
    expect(insight.excursions.durationLabel, '이탈 지속시간 확인 필요');
    expect(insight.risk.level, OperationalRiskLevel.caution);
    expect(insight.risk.gapLimitsJudgement, isTrue);
    expect(insight.risk.reasons.join('\n'), contains('관측되지 않은 구간'));
    expect(insight.risk.reasons.join('\n'), contains('확인되지 않은 시간은 위험도에 더하지 않습니다'));
    expect(insight.risk.level, isNot(OperationalRiskLevel.low));
  });

  test('진행 중 이탈은 마지막 이탈 시각까지만 계산하고 겹치는 구간은 한 번만 더한다', () {
    final ShipmentInsight open = analytics.inspect(
      shipment: shipment(),
      readings: steadyReadings(),
      excursions: <TemperatureExcursion>[
        excursion(
          id: 1,
          direction: TemperatureExcursion.aboveMax,
          startedAt: start,
          last: start.add(const Duration(seconds: 20)),
          recoveredAt: start.add(const Duration(minutes: 30)),
          min: 8.2,
          max: 8.2,
          open: true,
        ),
      ],
    );
    expect(open.excursions.observedDuration?.inSeconds, 20);
    expect(open.risk.level, OperationalRiskLevel.caution);

    final ShipmentInsight overlapped = analytics.inspect(
      shipment: shipment(),
      readings: steadyReadings(),
      excursions: <TemperatureExcursion>[
        excursion(
          id: 1,
          direction: TemperatureExcursion.aboveMax,
          startedAt: start,
          last: start.add(const Duration(seconds: 50)),
          min: 8.2,
          max: 8.2,
        ),
        excursion(
          id: 2,
          direction: TemperatureExcursion.belowMin,
          startedAt: start.add(const Duration(seconds: 40)),
          last: start.add(const Duration(seconds: 70)),
          min: 1.5,
          max: 1.8,
        ),
      ],
    );
    expect(overlapped.excursions.observedDuration?.inSeconds, 70);
    expect(overlapped.risk.level, OperationalRiskLevel.high);
  });

  test('목록과 상세는 같은 조치 기록으로 같은 수준과 근거를 만든다', () {
    final List<TemperatureExcursion> events = <TemperatureExcursion>[
      excursion(
        id: 7,
        direction: TemperatureExcursion.aboveMax,
        startedAt: start,
        last: start.add(const Duration(seconds: 10)),
        min: 8.5,
        max: 8.5,
      ),
    ];
    final ShipmentInsight detail = analytics.inspect(
      shipment: shipment(),
      readings: steadyReadings(),
      excursions: events,
      actionRecorded: const <int, bool>{7: true},
    );
    final ShipmentInsight listed = analytics
        .inspectAll(
          shipments: <ShipmentRecord>[shipment()],
          readings: steadyReadings(),
          excursions: <int, List<TemperatureExcursion>>{1: events},
          actionRecorded: const <int, bool>{7: true},
        )
        .values
        .single;
    expect(listed.risk.level, detail.risk.level);
    expect(listed.risk.reasons, detail.risk.reasons);
    expect(detail.risk.reasons, contains('원인 및 조치 기록: 작성 완료'));
    final ShipmentInsight missing = analytics.inspect(
      shipment: shipment(),
      readings: steadyReadings(),
      excursions: events,
    );
    expect(missing.risk.level, detail.risk.level);
    expect(missing.risk.reasons, contains('원인 및 조치 기록: 미작성'));
  });

  test('같은 입력이면 위험 수준이 같다', () {
    ShipmentInsight once() {
      return analytics.inspect(
        shipment: shipment(),
        readings: steadyReadings(),
        excursions: <TemperatureExcursion>[
          excursion(
            id: 1,
            direction: TemperatureExcursion.aboveMax,
            startedAt: start,
            min: 10,
            max: 10,
            open: true,
          ),
        ],
      );
    }

    expect(once().risk.level, once().risk.level);
    expect(once().risk.reasons, once().risk.reasons);
  });

  test('그래프는 공백을 끊고 축소해도 최고 온도를 남긴다', () {
    final List<TemperatureReading> readings = <TemperatureReading>[
      for (int index = 0; index < 100; index++)
        reading(
          index + 1,
          start.add(Duration(seconds: 5 * index)),
          index == 40 ? 12 : 4,
        ),
      reading(200, start.add(const Duration(seconds: 5 * 100 + 30)), 4),
    ];
    final TemperatureChartModel model = buildTemperatureChart(
      readings: readings,
      minBound: 2,
      maxBound: 8,
      maxPoints: 20,
    );
    expect(model.sourceCount, 101);
    expect(model.gaps, hasLength(1));
    expect(model.segments.length, 2);
    expect(model.displayCount, lessThan(model.sourceCount));
    expect(
      model.points.map((TemperatureChartPoint point) => point.celsius),
      contains(12),
    );
    expect(
      model.points.map((TemperatureChartPoint point) => point.celsius),
      contains(4),
    );
    expect(model.segments.first.last.measuredAt, isNot(model.segments.last.first.measuredAt));
  });

  test('축소해도 이탈 시작, 복귀, 최고, 최저를 남긴다', () {
    final List<TemperatureReading> readings = <TemperatureReading>[
      for (int index = 0; index <= 80; index++)
        reading(
          index + 1,
          start.add(Duration(seconds: 5 * index)),
          switch (index) {
            0 => 4.2,
            10 => 1.2,
            40 => 9.2,
            41 => 12,
            42 => 6.5,
            80 => 4.8,
            _ => 4,
          },
        ),
    ];
    final DateTime startedAt = start.add(const Duration(seconds: 5 * 40));
    final TemperatureChartModel model = buildTemperatureChart(
      readings: readings,
      minBound: 2,
      maxBound: 8,
      maxPoints: 8,
      excursions: <TemperatureExcursion>[
        excursion(
          id: 9,
          direction: TemperatureExcursion.aboveMax,
          startedAt: startedAt,
          last: start.add(const Duration(seconds: 5 * 41)),
          recoveredAt: start.add(const Duration(seconds: 5 * 42)),
          min: 9.2,
          max: 12,
        ),
      ],
    );
    final List<double> values = model.points
        .map((TemperatureChartPoint point) => point.celsius)
        .toList();
    expect(values, containsAll(<double>[4.2, 1.2, 9.2, 12, 6.5, 4.8]));
    expect(model.gaps, isEmpty);
  });

  testWidgets('그래프에 기준선, 이탈, 공백, 초 단위 시각을 표시한다', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final List<TemperatureReading> readings = <TemperatureReading>[
      reading(1, start, 4),
      reading(2, start.add(const Duration(seconds: 5)), 9.5),
      reading(3, start.add(const Duration(seconds: 10)), 4),
      reading(4, start.add(const Duration(seconds: 40)), 4),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemperatureChartView(
            readings: readings,
            minBound: 2,
            maxBound: 8,
            excursions: <TemperatureExcursion>[
              excursion(
                id: 3,
                direction: TemperatureExcursion.aboveMax,
                startedAt: start.add(const Duration(seconds: 5)),
                recoveredAt: start.add(const Duration(seconds: 10)),
                min: 9.5,
                max: 9.5,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('설정 하한 2.0°C'), findsOneWidget);
    expect(find.text('설정 상한 8.0°C'), findsOneWidget);
    expect(find.text('상한 이탈 구간'), findsOneWidget);
    expect(find.text('데이터 공백 구간'), findsOneWidget);
    expect(
      find.byKey(const Key('temperature-chart-selection')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('temperature-chart-selection')))
          .data,
      contains(':'),
    );
    expect(find.text('확대'), findsOneWidget);
    await tester.tap(find.text('확대'));
    await tester.pump();
    expect(find.byKey(const Key('temperature-chart')), findsOneWidget);
  });

  group('역할별 집계', () {
    late Directory tempDir;
    late AppDatabase database;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vaxtrust_analytics_');
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: '${tempDir.path}${Platform.pathSeparator}vaxtrust.db',
      );
      await database.open();
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('품질관리자와 의료진은 연결한 운송 건만 집계한다', () async {
      final AppUser courier = await database.createUser(
        loginId: 'courier',
        password: 'demo1234',
        role: UserRole.transporter,
      );
      final AppUser quality = await database.createUser(
        loginId: 'quality',
        password: 'demo1234',
        role: UserRole.qualityManager,
      );
      final AppUser medical = await database.createUser(
        loginId: 'medical',
        password: 'demo1234',
        role: UserRole.medicalStaff,
      );
      const NewShipment draft = NewShipment(
        vaccine: '인플루엔자 4가',
        manufacturer: 'Korea Vaccine',
        lot: 'LOT-A',
        expiryDate: '2027-11-16',
        quantity: 10,
        origin: '인천',
        destination: '서울',
        targetRange: '2 ~ 8°C',
        tempMin: 2,
        tempMax: 8,
      );
      final ShipmentRecord first = await database.createShipment(
        ownerUserId: courier.id,
        draft: draft,
      );
      await database.createShipment(
        ownerUserId: courier.id,
        draft: NewShipment(
          vaccine: draft.vaccine,
          manufacturer: draft.manufacturer,
          lot: 'LOT-B',
          expiryDate: draft.expiryDate,
          quantity: draft.quantity,
          origin: draft.origin,
          destination: draft.destination,
          targetRange: draft.targetRange,
          tempMin: draft.tempMin,
          tempMax: draft.tempMax,
        ),
      );
      await database.joinByParticipationCode(
        userId: quality.id,
        code: first.participationCode,
      );
      await database.joinByParticipationCode(
        userId: medical.id,
        code: first.participationCode,
      );
      final List<ShipmentRecord> qualityShipments = await database
          .shipmentsJoinedBy(quality.id);
      final List<ShipmentRecord> medicalShipments = await database
          .shipmentsJoinedBy(medical.id);
      expect(qualityShipments, hasLength(1));
      expect(medicalShipments.single.id, first.id);
      final FleetSummary summary = analytics.summarize(
        shipments: qualityShipments,
        insights: analytics
            .inspectAll(
              shipments: qualityShipments,
              readings: await database.temperaturesForShipments(
                qualityShipments.map((ShipmentRecord item) => item.id).toList(),
              ),
              excursions: await database.excursionsByShipment(
                qualityShipments.map((ShipmentRecord item) => item.id).toList(),
              ),
            )
            .values
            .toList(),
      );
      expect(summary.shipmentCount, 1);
      expect(summary.readingCount, 0);
    });

    test('조치 기록은 인수인계 뒤에도 목록과 상세가 같이 작성 완료로 본다', () async {
      final AppUser courier = await database.createUser(
        loginId: 'courier',
        password: 'demo1234',
        role: UserRole.transporter,
      );
      final AppUser next = await database.createUser(
        loginId: 'courier2',
        password: 'demo1234',
        role: UserRole.transporter,
      );
      final AppUser quality = await database.createUser(
        loginId: 'quality',
        password: 'demo1234',
        role: UserRole.qualityManager,
      );
      final ShipmentRecord created = await database.createShipment(
        ownerUserId: courier.id,
        draft: const NewShipment(
          vaccine: '인플루엔자 4가',
          manufacturer: 'Korea Vaccine',
          lot: 'LOT-HAND',
          expiryDate: '2027-11-16',
          quantity: 10,
          origin: '인천',
          destination: '서울',
          targetRange: '2 ~ 8°C',
          tempMin: 2,
          tempMax: 8,
        ),
      );
      await database.startTransport(
        actorUserId: courier.id,
        shipmentId: created.id,
      );
      await database.startDemoScenario(
        actorUserId: courier.id,
        shipmentId: created.id,
        type: DemoScenario.doorOpen,
      );
      const DemoScenarioSettings settings = DemoScenarioSettings(
        stepCelsius: 1,
        holdSamples: 2,
        breachMargin: 0.4,
      );
      DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
      List<TemperatureExcursion> events = const <TemperatureExcursion>[];
      for (int index = 0; index < 30 && events.isEmpty; index++) {
        await database.recordDemoSample(
          shipmentId: created.id,
          at: at,
          policy: InRangeTemperaturePolicy(random: Random(1)),
          scenarioSettings: settings,
        );
        at = at.add(const Duration(seconds: 5));
        events = await database.excursionsFor(
          userId: courier.id,
          shipmentId: created.id,
        );
      }
      expect(events, isNotEmpty);
      await database.saveExcursionAction(
        actorUserId: courier.id,
        excursionId: events.first.id,
        causeCategory: 'door_open',
        causeCertainty: ExcursionAction.confirmed,
        description: '문이 열려 있었습니다.',
        actionTaken: '문을 닫았습니다.',
      );
      final transfer = await database.requestHandover(
        actorUserId: courier.id,
        shipmentId: created.id,
        toLoginId: next.loginId,
        location: '서울역',
      );
      await database.acceptHandover(actorUserId: next.id, transferId: transfer.id);
      await database.joinByParticipationCode(
        userId: quality.id,
        code: created.participationCode,
      );

      Future<ShipmentInsight> insightFor(List<ShipmentRecord> visible) async {
        final List<int> ids = visible
            .map((ShipmentRecord item) => item.id)
            .toList();
        final Map<int, ShipmentInsight> insights = analytics.inspectAll(
          shipments: visible,
          readings: await database.temperaturesForShipments(ids),
          excursions: await database.excursionsByShipment(ids),
          actionRecorded: await database.recordedExcursionActions(ids),
        );
        return insights[created.id]!;
      }

      final List<ShipmentRecord> qualityShipments = await database
          .shipmentsJoinedBy(quality.id);
      final List<ShipmentRecord> transporterShipments = await database
          .shipmentsAssignedTo(next.id);
      final ShipmentInsight qualityInsight = await insightFor(qualityShipments);
      final ShipmentInsight transporterInsight = await insightFor(
        transporterShipments,
      );
      final Map<int, bool> detailActions = <int, bool>{
        for (final int id
            in (await database.latestActionsForShipment(created.id)).keys)
          id: true,
      };
      final ShipmentRecord? visible = await database.shipmentVisibleTo(
        userId: quality.id,
        shipmentId: created.id,
      );
      final ShipmentInsight detail = analytics.inspect(
        shipment: visible!,
        readings: await database.temperaturesForShipment(created.id),
        excursions: await database.excursionsFor(
          userId: quality.id,
          shipmentId: created.id,
        ),
        actionRecorded: detailActions,
      );
      expect(qualityInsight.risk.level, transporterInsight.risk.level);
      expect(qualityInsight.risk.reasons, transporterInsight.risk.reasons);
      expect(detail.risk.level, qualityInsight.risk.level);
      expect(detail.risk.reasons, qualityInsight.risk.reasons);
      expect(detail.risk.reasons, contains('원인 및 조치 기록: 작성 완료'));
      expect(
        await database.recordedExcursionActions(<int>[created.id]),
        containsPair(events.first.id, true),
      );
    });
  });
}
