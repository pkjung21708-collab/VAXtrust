import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/demo_risk_settings.dart';
import 'package:vaxtrust/data/demo_scenario_policy.dart';
import 'package:vaxtrust/data/shipment_analytics.dart';
import 'package:vaxtrust/data/shipment_summary.dart';
import 'package:vaxtrust/data/temperature_policy.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/demo_scenario.dart';
import 'package:vaxtrust/models/quality_review.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_excursion.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/widgets/quality_review_panel.dart';

void main() {
  const ShipmentAnalytics analytics = ShipmentAnalytics();
  final DateTime start = DateTime.utc(2026, 11, 18, 5);

  ShipmentRecord sample({int id = 1}) {
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
      status: ShipmentStatus.inTransit,
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

  test('측정이 없으면 분석을 만들지 않고 검토 완료라고 하지 않는다', () {
    final String text = buildShipmentNarrative(
      shipment: sample(),
      insight: analytics.inspect(
        shipment: sample(),
        readings: const <TemperatureReading>[],
        excursions: const <TemperatureExcursion>[],
      ),
    );
    expect(text, contains('현재 분석 가능한 온도 기록이 없습니다.'));
    expect(text, contains('평가 불가'));
    expect(text, contains('검토 기록이 없습니다'));
    expect(text, contains('접종 가능 여부를 의미하지 않습니다'));
    expect(text, isNot(contains('검토 완료')));
    expect(text, isNot(contains('품질이 안전')));
  });

  test('이탈이 없으면 정상 유지로 단정하지 않는다', () {
    final String text = buildShipmentNarrative(
      shipment: sample(),
      insight: analytics.inspect(
        shipment: sample(),
        readings: <TemperatureReading>[
          reading(1, start, 4),
          reading(2, start.add(const Duration(seconds: 5)), 5),
          reading(3, start.add(const Duration(seconds: 10)), 5),
        ],
        excursions: const <TemperatureExcursion>[],
      ),
    );
    expect(text, contains('설정 범위를 벗어난 온도 이탈은 확인되지 않았습니다'));
    expect(text, contains('운영 위험 수준은 낮음'));
    expect(text, isNot(contains('원인 및 조치 기록이 등록')));
    expect(text, contains('접종 가능 여부를 의미하지 않습니다'));
    expect(text, isNot(contains('접종 가능하다')));
  });

  test('이탈과 공백과 미작성 조치를 저장된 값으로만 말한다', () {
    final String text = buildShipmentNarrative(
      shipment: sample(),
      insight: analytics.inspect(
        shipment: sample(),
        readings: <TemperatureReading>[
          reading(1, start, 8.4),
          reading(2, start.add(const Duration(seconds: 20)), 8.4),
          reading(3, start.add(const Duration(minutes: 5)), 4),
        ],
        excursions: <TemperatureExcursion>[
          TemperatureExcursion(
            id: 1,
            shipmentId: 1,
            direction: TemperatureExcursion.aboveMax,
            startedAt: start,
            lastOutOfRangeAt: start.add(const Duration(seconds: 20)),
            recoveredAt: start.add(const Duration(seconds: 25)),
            minTemperature: 8.4,
            maxTemperature: 8.4,
            dataGapDetected: true,
            status: TemperatureExcursion.recoveredStatus,
            createdAt: start,
            updatedAt: start,
          ),
        ],
      ),
    );
    expect(text, contains('상한을 초과한 기록이 1회'));
    expect(text, contains('0.4°C'));
    expect(text, contains('이탈 지속시간 확인 필요'));
    expect(text, contains('원인 및 조치 기록은 없습니다'));
    expect(text, contains('측정 데이터가 누락된 구간이 있어'));
    expect(text, contains('운영 위험 수준은 주의'));
    expect(text, contains('접종 가능 여부를 의미하지 않습니다'));
    expect(text, isNot(contains('접종 가능하다')));
    expect(text, isNot(contains('조치가 완료')));
  });

  test('검토 상태가 있어도 위험 수준 문장을 품질 적합성으로 바꾸지 않는다', () {
    final ShipmentInsight insight = analytics.inspect(
      shipment: sample(),
      readings: <TemperatureReading>[
        reading(1, start, 4),
        reading(2, start.add(const Duration(seconds: 5)), 4),
        reading(3, start.add(const Duration(seconds: 10)), 4),
      ],
      excursions: const <TemperatureExcursion>[],
    );
    final String text = buildShipmentNarrative(
      shipment: sample(),
      insight: insight,
      latestReview: QualityReview(
        id: 3,
        shipmentId: 1,
        reviewerUserId: 2,
        reviewerLoginId: 'quality',
        status: QualityReviewStatus.reviewCompleted,
        comment: '기록 확인',
        createdAt: start,
        updatedAt: start,
      ),
    );
    expect(insight.risk.level, OperationalRiskLevel.low);
    expect(text, contains('품질 검토 상태는 검토 완료'));
    expect(text, contains('접종 가능 여부를 의미하지 않습니다'));
  });

  testWidgets('의료진 화면에는 저장 버튼이 없고 요약이 있다', (tester) async {
    final ShipmentRecord shipment = sample();
    final ShipmentInsight insight = analytics.inspect(
      shipment: shipment,
      readings: const <TemperatureReading>[],
      excursions: const <TemperatureExcursion>[],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QualityReviewPanel(
            user: AppUser(
              id: 3,
              loginId: 'medical',
              role: UserRole.medicalStaff,
              createdAt: start,
            ),
            shipment: shipment,
            insight: insight,
            latest: null,
            reviews: const <QualityReview>[],
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('quality-review-save')), findsNothing);
    expect(find.byKey(const Key('medical-shipment-summary')), findsOneWidget);
    expect(find.text('품질관리자의 검토 기록이 없습니다.'), findsWidgets);
  });

  group('저장', () {
    late Directory tempDir;
    late AppDatabase database;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vaxtrust_review_');
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

    const NewShipment draft = NewShipment(
      vaccine: '인플루엔자 4가',
      manufacturer: 'Korea Vaccine',
      lot: 'LOT-REV',
      expiryDate: '2027-11-16',
      quantity: 10,
      origin: '인천',
      destination: '서울',
      targetRange: '2 ~ 8°C',
      tempMin: 2,
      tempMax: 8,
    );

    Future<AppUser> user(String loginId, UserRole role) {
      return database.createUser(
        loginId: loginId,
        password: 'demo1234',
        role: role,
      );
    }

    test('버전 5 파일의 계정을 유지한 채 검토 표를 추가한다', () async {
      final String legacyPath =
          '${tempDir.path}${Platform.pathSeparator}legacy.db';
      final Database legacy = await databaseFactoryFfi.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 5,
          onConfigure: (Database db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (Database db, int version) async {
            await db.execute('''
              CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                login_id TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                password_salt TEXT NOT NULL,
                password_iterations INTEGER NOT NULL,
                role TEXT NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE shipments (
                id INTEGER PRIMARY KEY AUTOINCREMENT
              )
            ''');
            await db.insert('users', <String, Object?>{
              'login_id': 'kept',
              'password_hash': 'hash',
              'password_salt': 'salt',
              'password_iterations': 1,
              'role': 'transporter',
              'created_at': '2026-11-15T00:00:00.000Z',
            });
          },
        ),
      );
      await legacy.close();
      final AppDatabase upgraded = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: legacyPath,
      );
      await upgraded.open();
      expect(AppDatabase.schemaVersion, 11);
      expect(await upgraded.userVersion(), 11);
      expect(
        await upgraded.columnNames('quality_reviews'),
        containsAll(<String>[
          'shipment_id',
          'reviewer_user_id',
          'review_status',
          'review_comment',
          'created_at',
        ]),
      );
      expect(
        () => upgraded.createUser(
          loginId: 'kept',
          password: 'demo1234',
          role: UserRole.transporter,
        ),
        throwsA(isA<DuplicateLoginIdException>()),
      );
      await upgraded.close();
    });

    test('검토 이력은 누적되고 권한 밖 저장은 거절된다', () async {
      final AppUser courier = await user('courier', UserRole.transporter);
      final AppUser quality = await user('quality', UserRole.qualityManager);
      final AppUser other = await user('other', UserRole.qualityManager);
      final AppUser medical = await user('medical', UserRole.medicalStaff);
      final ShipmentRecord created = await database.createShipment(
        ownerUserId: courier.id,
        draft: draft,
      );
      await database.joinByParticipationCode(
        userId: quality.id,
        code: created.participationCode,
      );
      await database.joinByParticipationCode(
        userId: medical.id,
        code: created.participationCode,
      );

      expect(
        () => database.saveQualityReview(
          actorUserId: courier.id,
          shipmentId: created.id,
          status: QualityReviewStatus.inReview,
          comment: '운송자 수정',
        ),
        throwsA(
          isA<QualityReviewException>().having(
            (QualityReviewException error) => error.message,
            'message',
            contains('품질관리자만'),
          ),
        ),
      );
      expect(
        () => database.saveQualityReview(
          actorUserId: medical.id,
          shipmentId: created.id,
          status: QualityReviewStatus.inReview,
          comment: '의료진 수정',
        ),
        throwsA(
          isA<QualityReviewException>().having(
            (QualityReviewException error) => error.message,
            'message',
            contains('품질관리자만'),
          ),
        ),
      );
      expect(
        () => database.saveQualityReview(
          actorUserId: other.id,
          shipmentId: created.id,
          status: QualityReviewStatus.inReview,
          comment: '미참여',
        ),
        throwsA(
          isA<QualityReviewException>().having(
            (QualityReviewException error) => error.message,
            'message',
            contains('참여한 운송 건만'),
          ),
        ),
      );

      await database.saveQualityReview(
        actorUserId: quality.id,
        shipmentId: created.id,
        status: QualityReviewStatus.inReview,
        comment: '기록 확인 중',
      );
      await database.saveQualityReview(
        actorUserId: quality.id,
        shipmentId: created.id,
        status: QualityReviewStatus.needsInformation,
        comment: '온도 이탈 원인 확인 요청',
      );
      final QualityReview completed = await database.saveQualityReview(
        actorUserId: quality.id,
        shipmentId: created.id,
        status: QualityReviewStatus.reviewCompleted,
        comment: '운송 기록 및 조치 내역 검토 완료',
      );

      final List<QualityReview> history = await database.qualityReviewsFor(
        userId: medical.id,
        shipmentId: created.id,
      );
      expect(history, hasLength(3));
      expect(
        history.map((QualityReview review) => review.status).toList(),
        <QualityReviewStatus>[
          QualityReviewStatus.inReview,
          QualityReviewStatus.needsInformation,
          QualityReviewStatus.reviewCompleted,
        ],
      );
      expect(history[1].comment, '온도 이탈 원인 확인 요청');
      expect(history.last.reviewerLoginId, 'quality');
      expect(history.last.createdAt.isBefore(history.first.createdAt), isFalse);
      expect(completed.id, history.last.id);
      final QualityReviewCounts counts = QualityReviewCounts.fromLatest(<int>[
        created.id,
      ], await database.latestQualityReviews(<int>[created.id]));
      expect(counts.completed, 1);
      expect(counts.notReviewed, 0);

      final List<QualityReview> transporterView = await database
          .qualityReviewsFor(userId: courier.id, shipmentId: created.id);
      expect(transporterView, hasLength(3));

      final String path = '${tempDir.path}${Platform.pathSeparator}vaxtrust.db';
      await database.close();
      database = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
      await database.open();
      final List<QualityReview> restored = await database.qualityReviewsFor(
        userId: quality.id,
        shipmentId: created.id,
      );
      expect(restored, hasLength(3));
      expect(restored.last.comment, '운송 기록 및 조치 내역 검토 완료');
      expect(await database.userVersion(), 11);
    });

    test('검토 완료 뒤에도 이탈 기록과 위험도 계산은 그대로다', () async {
      final AppUser courier = await user('courier', UserRole.transporter);
      final AppUser quality = await user('quality', UserRole.qualityManager);
      final ShipmentRecord created = await database.createShipment(
        ownerUserId: courier.id,
        draft: draft,
      );
      await database.joinByParticipationCode(
        userId: quality.id,
        code: created.participationCode,
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
      DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
      List<TemperatureExcursion> events = const <TemperatureExcursion>[];
      for (int index = 0; index < 30 && events.isEmpty; index++) {
        await database.recordDemoSample(
          shipmentId: created.id,
          at: at,
          policy: InRangeTemperaturePolicy(random: Random(3)),
          scenarioSettings: const DemoScenarioSettings(
            stepCelsius: 1,
            holdSamples: 2,
            breachMargin: 0.4,
          ),
        );
        at = at.add(const Duration(seconds: 5));
        events = await database.excursionsFor(
          userId: courier.id,
          shipmentId: created.id,
        );
      }
      expect(events, isNotEmpty);
      final int readingCount = await database.temperatureCount(created.id);
      final ShipmentRecord? before = await database.shipmentVisibleTo(
        userId: quality.id,
        shipmentId: created.id,
      );
      final ShipmentInsight beforeRisk = analytics.inspect(
        shipment: before!,
        readings: await database.temperaturesForShipment(created.id),
        excursions: events,
      );
      await database.saveQualityReview(
        actorUserId: quality.id,
        shipmentId: created.id,
        status: QualityReviewStatus.reviewCompleted,
        comment: '기록 확인',
      );
      final List<TemperatureExcursion> after = await database.excursionsFor(
        userId: quality.id,
        shipmentId: created.id,
      );
      final ShipmentInsight afterRisk = analytics.inspect(
        shipment: before,
        readings: await database.temperaturesForShipment(created.id),
        excursions: after,
      );
      expect(after, hasLength(events.length));
      expect(after.first.id, events.first.id);
      expect(await database.temperatureCount(created.id), readingCount);
      expect(afterRisk.risk.level, beforeRisk.risk.level);
      expect(afterRisk.excursions.count, beforeRisk.excursions.count);
      expect(
        (await database.latestQualityReviews(<int>[
          created.id,
        ]))[created.id]!.status,
        QualityReviewStatus.reviewCompleted,
      );
    });
  });
}
