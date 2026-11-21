import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/response_manual.dart';
import 'package:vaxtrust/data/shipment_analytics.dart';
import 'package:vaxtrust/data/shipment_summary.dart';
import 'package:vaxtrust/models/excursion_action.dart';
import 'package:vaxtrust/models/quality_review.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_excursion.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/models/vaccine_product.dart';
import 'package:vaxtrust/screens/response_manual_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ShipmentRecord shipment({
    String vaccine = '인플루엔자 4가',
    String? stage,
    int? productId,
    double min = 2,
    double max = 8,
  }) {
    return ShipmentRecord(
      id: 1,
      ownerUserId: 1,
      assigneeUserId: 1,
      participationCode: 'VX-MANUAL',
      vaccine: vaccine,
      manufacturer: '직접 입력',
      lot: 'LOT',
      expiryDate: '2027-01-01',
      quantity: 1,
      origin: '인천',
      destination: '서울',
      targetRange: '$min ~ $max°C',
      tempMin: min,
      tempMax: max,
      status: ShipmentStatus.registered,
      createdAt: DateTime.utc(2026, 11, 20),
      source: ShipmentRecord.userInputSource,
      vaccineProductId: productId,
      selectedProductName: productId == null ? null : vaccine,
      selectedStorageStage: stage,
    );
  }

  test('보관 단계와 상황별로 대응 매뉴얼이 갈라진다', () {
    final ShipmentRecord frozen = shipment(
      vaccine: '코미나티제이엔원주',
      stage: '냉동 보관',
      productId: 1,
      min: -90,
      max: -60,
    );
    final ShipmentRecord thawed = shipment(
      vaccine: '코미나티제이엔원주',
      stage: '해동 후 냉장 보관',
      productId: 1,
    );
    final ShipmentRecord flu = shipment(
      vaccine: '스카이셀플루4가프리필드시린지',
      stage: '냉장 보관',
      productId: 2,
    );
    final ShipmentRecord legacy = shipment();

    final ResponseManualEntry highFrozen = ResponseManualCatalog.select(
      scenarioType: ManualScenario.aboveMax,
      shipment: frozen,
    );
    expect(highFrozen.applicableStorageStage, ManualStage.frozen);
    expect(highFrozen.immediateActions, hasLength(3));
    expect(highFrozen.detailedActions.join('\n'), contains('냉장 백신용 냉매'));
    expect(highFrozen.title, contains('냉동'));

    final ResponseManualEntry lowFrozen = ResponseManualCatalog.select(
      scenarioType: ManualScenario.belowMin,
      shipment: frozen,
    );
    expect(
      lowFrozen.handlingPrecautions.join('\n'),
      contains('동결 사고라고 표시하지 않습니다'),
    );
    expect(lowFrozen.detailedActions.join('\n'), contains('냉장 백신용 냉매'));

    final ResponseManualEntry highThawed = ResponseManualCatalog.select(
      scenarioType: ManualScenario.aboveMax,
      shipment: thawed,
    );
    expect(highThawed.applicableStorageStage, ManualStage.thawedRefrigerated);
    expect(highThawed.detailedActions.join('\n'), contains('다시 냉동하지 않습니다'));
    expect(highThawed.detailedActions.join('\n'), contains('남은 시간을 계산하지 않습니다'));

    final ResponseManualEntry lowFlu = ResponseManualCatalog.select(
      scenarioType: ManualScenario.belowMin,
      shipment: flu,
    );
    expect(lowFlu.applicableStorageStage, ManualStage.refrigerated);
    expect(lowFlu.handlingPrecautions.join('\n'), contains('동결 금지'));
    expect(lowFlu.handlingPrecautions.join('\n'), contains('차광'));

    final ResponseManualEntry legacyHigh = ResponseManualCatalog.select(
      scenarioType: ManualScenario.aboveMax,
      shipment: legacy,
    );
    expect(legacyHigh.applicableStorageStage, ManualStage.general);
    expect(
      legacyHigh.detailedActions.join('\n'),
      contains('다른 백신 제품으로 바꾸지 않습니다'),
    );
    expect(legacyHigh.title, isNot(contains('냉동')));

    final ResponseManualEntry fault = ResponseManualCatalog.select(
      scenarioType: ManualScenario.coolingFault,
      shipment: flu,
    );
    expect(fault.shortDescription, contains('실제 고장을 감지하지 않습니다'));
    expect(fault.detailedActions.join('\n'), contains('서로 다른 사건'));

    final ResponseManualEntry gap = ResponseManualCatalog.select(
      scenarioType: ManualScenario.dataGap,
      shipment: frozen,
    );
    expect(ManualScenario.isTemperatureExcursion(gap.scenarioType), isFalse);
    expect(gap.shortDescription, contains('같지 않습니다'));
    expect(gap.detailedActions.join('\n'), contains('추정하지 않습니다'));
    expect(gap.detailedActions.join('\n'), contains('판정하지 않습니다'));

    expect(
      ResponseManualCatalog.select(
        scenarioType: ManualScenario.transportDelay,
        shipment: legacy,
      ).title,
      contains('수송 지연'),
    );
    expect(
      ResponseManualCatalog.select(
        scenarioType: ManualScenario.physicalShock,
        shipment: legacy,
      ).detailedActions.join('\n'),
      contains('사진을 첨부하지 않습니다'),
    );
    expect(
      ResponseManualCatalog.select(
        scenarioType: ManualScenario.theftLoss,
        shipment: legacy,
      ).detailedActions.join('\n'),
      contains('자동으로 신고하지 않습니다'),
    );
    expect(ResponseManualCatalog.disclaimer, contains('기관별 SOP'));
  });

  testWidgets('매뉴얼 화면을 열어도 조치 완료로 표시하지 않는다', (tester) async {
    final ResponseManualEntry manual = ResponseManualCatalog.select(
      scenarioType: ManualScenario.aboveMax,
      shipment: shipment(
        vaccine: '스카이셀플루4가프리필드시린지',
        stage: '냉장 보관',
        productId: 2,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ResponseManualScreen(
          manual: manual,
          appliedRangeLabel: '2 ~ 8°C',
          canRecord: true,
          onRecord: () {},
        ),
      ),
    );
    expect(find.byKey(const Key('response-manual-step-1')), findsOneWidget);
    expect(find.byKey(const Key('response-manual-step-2')), findsOneWidget);
    expect(find.byKey(const Key('response-manual-step-3')), findsOneWidget);
    expect(find.text(ResponseManualCatalog.disclaimer), findsOneWidget);
    expect(find.text('조치 완료'), findsNothing);
    expect(find.text('사용 승인 완료'), findsNothing);
    expect(find.text('접종 가능'), findsNothing);
  });

  test('이탈과 조치와 검토 상태를 요약에 구분한다', () {
    final ShipmentRecord record = shipment();
    final ShipmentAnalytics analytics = const ShipmentAnalytics();
    final DateTime at = DateTime.utc(2026, 11, 20, 1);
    final TemperatureExcursion excursion = TemperatureExcursion(
      id: 4,
      shipmentId: 1,
      direction: TemperatureExcursion.aboveMax,
      startedAt: at,
      lastOutOfRangeAt: at,
      recoveredAt: null,
      minTemperature: 9,
      maxTemperature: 9,
      dataGapDetected: false,
      status: TemperatureExcursion.openStatus,
      createdAt: at,
      updatedAt: at,
    );
    final ShipmentInsight open = analytics.inspect(
      shipment: record,
      readings: <TemperatureReading>[
        TemperatureReading(
          id: 1,
          shipmentId: 1,
          celsius: 9,
          measuredAt: at,
          recordedAt: at,
          source: TemperatureReading.demoVirtualSource,
          assigneeUserId: 1,
        ),
      ],
      excursions: <TemperatureExcursion>[excursion],
    );
    final String missing = buildShipmentNarrative(
      shipment: record,
      insight: open,
    );
    expect(missing, contains('조치 기록은 확인되지 않았습니다'));
    expect(missing, contains('품질관리자의 확인이 필요합니다'));

    final ExcursionAction action = ExcursionAction(
      id: 1,
      shipmentId: 1,
      excursionId: 4,
      authorUserId: 1,
      authorLoginId: 'courier',
      causeCategory: 'other',
      causeCertainty: ExcursionAction.suspected,
      description: '문 열림',
      discoveredAt: null,
      responseStartedAt: null,
      actionTaken: '문을 닫음',
      reportedTo: null,
      reportedAt: null,
      note: null,
      createdAt: at,
      situationType: ManualScenario.aboveMax,
      responsibleContacted: true,
      holdGuidanceGiven: true,
      holdActionCompleted: false,
    );
    final ShipmentInsight recorded = analytics.inspect(
      shipment: record,
      readings: <TemperatureReading>[
        TemperatureReading(
          id: 1,
          shipmentId: 1,
          celsius: 9,
          measuredAt: at,
          recordedAt: at,
          source: TemperatureReading.demoVirtualSource,
          assigneeUserId: 1,
        ),
      ],
      excursions: <TemperatureExcursion>[excursion],
      actionRecorded: <int, bool>{4: true},
    );
    final String withAction = buildShipmentNarrative(
      shipment: record,
      insight: recorded,
      actions: <ExcursionAction>[action],
      latestReview: QualityReview(
        id: 1,
        shipmentId: 1,
        reviewerUserId: 2,
        reviewerLoginId: 'quality',
        status: QualityReviewStatus.reviewCompleted,
        comment: '',
        createdAt: at,
        updatedAt: at,
      ),
    );
    expect(withAction, contains('조치 내용을 기록했습니다'));
    expect(withAction, contains('책임자 연락이 기록되어 있습니다'));
    expect(withAction, contains('안내만으로 격리 완료를 의미하지 않습니다'));
    expect(withAction, contains('접종 적합성 승인을 의미하지 않습니다'));
    expect(withAction, isNot(contains('사용 승인 완료')));
    expect(withAction, isNot(contains('폐기 확정')));
    expect(recorded.risk.level, open.risk.level);
  });

  group('조치 기록 저장', () {
    late Directory tempDir;
    late AppDatabase database;
    late AppDatabase original;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vaxtrust_manual_');
      original = AppDatabase.instance;
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: '${tempDir.path}${Platform.pathSeparator}vaxtrust.db',
      );
      await database.open();
      AppDatabase.instance = database;
    });

    tearDown(() async {
      await database.close();
      AppDatabase.instance = original;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('이벤트별로 연락과 보류를 구분하고 재실행 후에도 남긴다', () async {
      expect(await database.vaccineProducts(), hasLength(2));
      expect(await database.allVaccineProducts(), hasLength(6));
      final courier = await database.createUser(
        loginId: 'courier',
        password: 'demo1234',
        role: UserRole.transporter,
      );
      final quality = await database.createUser(
        loginId: 'quality',
        password: 'demo1234',
        role: UserRole.qualityManager,
      );
      final products = await database.vaccineProducts();
      final VaccineProduct flu = products.firstWhere(
        (VaccineProduct product) => product.productName == '스카이셀플루4가프리필드시린지',
      );
      final profile = (await database.storageProfilesFor(flu.id)).single;
      final ShipmentRecord created = await database.createShipment(
        ownerUserId: courier.id,
        draft: NewShipment(
          vaccine: flu.productName,
          manufacturer: flu.manufacturer!,
          lot: 'LOT-MANUAL',
          expiryDate: '2027-11-20',
          quantity: 1,
          origin: '인천',
          destination: '서울',
          targetRange: '2 ~ 8°C',
          tempMin: 2,
          tempMax: 8,
          vaccineProductId: flu.id,
          storageProfileId: profile.id,
        ),
      );
      await database.joinByParticipationCode(
        userId: quality.id,
        code: created.participationCode,
      );
      final ShipmentRecord started = await database.startTransport(
        actorUserId: courier.id,
        shipmentId: created.id,
      );
      final DateTime firstAt = DateTime.utc(2026, 11, 20, 2);
      await database.recordMeasuredSample(
        shipmentId: started.id,
        at: firstAt,
        celsius: 9,
      );
      await database.recordMeasuredSample(
        shipmentId: started.id,
        at: firstAt.add(const Duration(seconds: 5)),
        celsius: 5,
      );
      await database.recordMeasuredSample(
        shipmentId: started.id,
        at: firstAt.add(const Duration(seconds: 10)),
        celsius: 1,
      );
      final List<TemperatureExcursion> events = await database.excursionsFor(
        userId: courier.id,
        shipmentId: started.id,
      );
      expect(events, hasLength(2));
      final TemperatureExcursion high = events.firstWhere(
        (TemperatureExcursion event) => event.isAbove,
      );
      final TemperatureExcursion low = events.firstWhere(
        (TemperatureExcursion event) => !event.isAbove,
      );
      final ExcursionAction highAction = await database.saveExcursionAction(
        actorUserId: courier.id,
        excursionId: high.id,
        causeCategory: 'cooling_fault',
        causeCertainty: ExcursionAction.suspected,
        description: '냉각이 약했다',
        actionTaken: '문을 닫았다',
        situationType: ManualScenario.aboveMax,
        responsibleContacted: true,
        holdGuidanceGiven: true,
        holdActionCompleted: false,
      );
      final ExcursionAction lowAction = await database.saveExcursionAction(
        actorUserId: courier.id,
        excursionId: low.id,
        causeCategory: 'environment',
        causeCertainty: ExcursionAction.suspected,
        description: '냉매가 가까웠다',
        actionTaken: '냉매를 떨어뜨려 두었다',
        situationType: ManualScenario.belowMin,
        responsibleContacted: false,
        holdGuidanceGiven: false,
        holdActionCompleted: false,
      );
      expect(highAction.excursionId, isNot(lowAction.excursionId));
      expect(highAction.responsibleContacted, isTrue);
      expect(highAction.holdGuidanceGiven, isTrue);
      expect(highAction.holdActionCompleted, isFalse);
      expect(lowAction.responsibleContacted, isFalse);

      final before = await database.actionsForShipment(
        userId: quality.id,
        shipmentId: started.id,
      );
      final ExcursionAction report = await database.saveSituationReport(
        actorUserId: courier.id,
        shipmentId: started.id,
        situationType: ManualScenario.theftLoss,
        description: '차량 문을 열었을 때 상자 하나가 없었다',
        actionTaken: '책임자에게 전화했다',
        responsibleContacted: true,
        holdGuidanceGiven: false,
        holdActionCompleted: false,
      );
      expect(report.excursionId, isNull);
      expect(
        await database.excursionsFor(
          userId: courier.id,
          shipmentId: started.id,
        ),
        hasLength(2),
      );
      final List<ExcursionAction> qualityView = await database
          .actionsForShipment(userId: quality.id, shipmentId: started.id);
      expect(qualityView, hasLength(before.length + 1));
      expect(
        qualityView.map((ExcursionAction action) => action.excursionId),
        containsAll(<int?>[high.id, low.id, null]),
      );

      final String path = '${tempDir.path}${Platform.pathSeparator}vaxtrust.db';
      await database.close();
      database = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
      await database.open();
      final List<ExcursionAction> restored = await database.actionsForShipment(
        userId: courier.id,
        shipmentId: started.id,
      );
      expect(restored, hasLength(3));
      expect(restored.first.actionTaken, '문을 닫았다');
      expect(await database.vaccineProducts(), hasLength(2));
      expect(
        (await database.allVaccineProducts()).where(
          (VaccineProduct product) => !product.isActive,
        ),
        hasLength(4),
      );
    });
  });

  test('버전 7 조치 기록은 남고 연락 여부는 비워 둔다', () async {
    sqfliteFfiInit();
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'vaxtrust_manual_v7_',
    );
    final String path = '${tempDir.path}${Platform.pathSeparator}legacy.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await db.execute(
            'CREATE TABLE users (id INTEGER PRIMARY KEY, login_id TEXT NOT NULL)',
          );
          await db.execute('CREATE TABLE shipments (id INTEGER PRIMARY KEY)');
          await db.execute('''
            CREATE TABLE temperature_excursions (
              id INTEGER PRIMARY KEY,
              shipment_id INTEGER NOT NULL,
              direction TEXT NOT NULL,
              started_at TEXT NOT NULL,
              last_out_of_range_at TEXT NOT NULL,
              min_temperature REAL NOT NULL,
              max_temperature REAL NOT NULL,
              data_gap_detected INTEGER NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE excursion_actions (
              id INTEGER PRIMARY KEY,
              excursion_id INTEGER NOT NULL,
              author_user_id INTEGER NOT NULL,
              cause_category TEXT NOT NULL,
              cause_certainty TEXT NOT NULL,
              description TEXT NOT NULL,
              action_taken TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE quality_reviews (
              id INTEGER PRIMARY KEY,
              shipment_id INTEGER NOT NULL,
              reviewer_user_id INTEGER NOT NULL,
              review_status TEXT NOT NULL,
              review_comment TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE temperature_readings (
              id INTEGER PRIMARY KEY,
              shipment_id INTEGER NOT NULL,
              temperature_c REAL NOT NULL,
              measured_at TEXT NOT NULL,
              recorded_at TEXT NOT NULL,
              source TEXT NOT NULL,
              assignee_user_id INTEGER NOT NULL
            )
          ''');
          await db.insert('users', <String, Object?>{
            'id': 1,
            'login_id': 'courier',
          });
          await db.insert('shipments', <String, Object?>{'id': 3});
          await db.insert('temperature_excursions', <String, Object?>{
            'id': 9,
            'shipment_id': 3,
            'direction': 'above_max',
            'started_at': '2026-11-16T00:00:00.000Z',
            'last_out_of_range_at': '2026-11-16T00:00:05.000Z',
            'min_temperature': 9,
            'max_temperature': 9.4,
            'data_gap_detected': 0,
            'status': 'open',
            'created_at': '2026-11-16T00:00:00.000Z',
            'updated_at': '2026-11-16T00:00:00.000Z',
          });
          await db.insert('excursion_actions', <String, Object?>{
            'id': 4,
            'excursion_id': 9,
            'author_user_id': 1,
            'cause_category': 'door_open',
            'cause_certainty': 'suspected',
            'description': '기존 원인',
            'action_taken': '기존 조치',
            'created_at': '2026-11-16T00:01:00.000Z',
          });
          await db.insert('quality_reviews', <String, Object?>{
            'id': 2,
            'shipment_id': 3,
            'reviewer_user_id': 1,
            'review_status': 'needs_information',
            'review_comment': '기존 검토',
            'created_at': '2026-11-16T00:02:00.000Z',
            'updated_at': '2026-11-16T00:02:00.000Z',
          });
          await db.insert('temperature_readings', <String, Object?>{
            'id': 8,
            'shipment_id': 3,
            'temperature_c': 9.4,
            'measured_at': '2026-11-16T00:00:05.000Z',
            'recorded_at': '2026-11-16T00:00:05.000Z',
            'source': 'demo_virtual',
            'assignee_user_id': 1,
          });
        },
      ),
    );
    await legacy.close();
    final AppDatabase upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    await upgraded.open();
    expect(await upgraded.userVersion(), 11);
    final List<Map<String, Object?>> actions = await upgraded.tableRows(
      'excursion_actions',
    );
    expect(actions, hasLength(1));
    expect(actions.single['id'], 4);
    expect(actions.single['excursion_id'], 9);
    expect(actions.single['action_taken'], '기존 조치');
    expect(actions.single['responsible_contacted'], isNull);
    expect(actions.single['hold_action_completed'], isNull);
    expect(
      (await upgraded.tableRows('temperature_excursions')).single['id'],
      9,
    );
    expect(
      (await upgraded.tableRows('temperature_readings'))
          .single['temperature_c'],
      9.4,
    );
    expect(
      (await upgraded.tableRows('quality_reviews')).single['review_comment'],
      '기존 검토',
    );
    await upgraded.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
}
