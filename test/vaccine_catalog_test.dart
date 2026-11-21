import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/demo_risk_settings.dart';
import 'package:vaxtrust/data/shipment_analytics.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/models/vaccine_product.dart';
import 'package:vaxtrust/screens/shipment_setup_screen.dart';
import 'package:vaxtrust/theme/app_theme.dart';
import 'package:vaxtrust/widgets/storage_condition_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase database;
  late AppDatabase original;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_vaccine_');
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

  test('백신 6종은 남고 신규 등록은 2종만 가능하다', () async {
    final List<VaccineProduct> catalog = await database.allVaccineProducts();
    expect(catalog, hasLength(6));
    expect(
      catalog.map((VaccineProduct product) => product.productName),
      containsAll(<String>[
        '코미나티제이엔원주',
        '스카이셀플루4가프리필드시린지',
        '싱그릭스주',
        '프리베나프리필드시린지',
        '스카이조스터주',
        '로타릭스액',
      ]),
    );
    final List<VaccineProduct> selectable = await database.vaccineProducts();
    expect(
      selectable.map((VaccineProduct product) => product.productName).toList(),
      <String>['코미나티제이엔원주', '스카이셀플루4가프리필드시린지'],
    );
    expect(
      selectable.every((VaccineProduct product) => product.isActive),
      isTrue,
    );
    expect(
      catalog
          .where((VaccineProduct product) => !product.isActive)
          .map((VaccineProduct product) => product.productName)
          .toList(),
      <String>['싱그릭스주', '프리베나프리필드시린지', '스카이조스터주', '로타릭스액'],
    );
    for (final VaccineProduct inactive in catalog.where(
      (VaccineProduct product) => !product.isActive,
    )) {
      expect(await database.storageProfilesFor(inactive.id), isNotEmpty);
    }
    expect(
      catalog.every((VaccineProduct product) => product.manufacturer != 'MSD'),
      isTrue,
    );

    final VaccineProduct comirnaty = selectable.firstWhere(
      (VaccineProduct product) => product.productName == '코미나티제이엔원주',
    );
    expect(comirnaty.manufacturer, '한국화이자제약(주)');
    expect(comirnaty.authorizationItemCode, '202402096');
    expect(comirnaty.verificationStatus, StorageVerificationStatus.verified);
    final List<VaccineStorageProfile> profiles = await database
        .storageProfilesFor(comirnaty.id);
    expect(profiles, hasLength(2));
    expect(profiles.first.storageStage, 'frozen');
    expect(profiles.first.minTemperature, -90);
    expect(profiles.first.maxTemperature, -60);
    expect(profiles.last.storageStage, 'thawed_refrigerated');
    expect(profiles.last.minTemperature, 2);
    expect(profiles.last.maxTemperature, 8);
    expect(profiles.last.refreezingProhibited, isTrue);
    expect(profiles.last.timeLimitNotes, contains('최대 10주'));
    expect(profiles.last.timeLimitNotes, contains('12시간'));
    expect(profiles.last.timeLimitNotes, contains('운송 온도 범위로 쓰지 않습니다'));

    final VaccineProduct skyCellflu = selectable.firstWhere(
      (VaccineProduct product) => product.productName == '스카이셀플루4가프리필드시린지',
    );
    expect(skyCellflu.manufacturer, '에스케이바이오사이언스(주)');
    expect(skyCellflu.authorizationItemCode, '201508425');
    expect(skyCellflu.verificationStatus, StorageVerificationStatus.verified);
    final VaccineStorageProfile refrigerated =
        (await database.storageProfilesFor(skyCellflu.id)).single;
    expect(refrigerated.storageStage, 'refrigerated');
    expect(refrigerated.minTemperature, 2);
    expect(refrigerated.maxTemperature, 8);
    expect(refrigerated.freezingProhibited, isTrue);
    expect(refrigerated.lightProtectionRequired, isTrue);

    final VaccineProduct prevnar = catalog.firstWhere(
      (VaccineProduct product) => product.productName == '프리베나프리필드시린지',
    );
    expect(prevnar.isActive, isFalse);
    expect(prevnar.manufacturer, isNull);
    expect(prevnar.authorizationItemCode, isNull);
    expect(prevnar.sourceUrl, isNull);
    expect(
      prevnar.verificationStatus,
      StorageVerificationStatus.verificationRequired,
    );
    expect(prevnar.sourceDocument, contains('대체하지 않습니다'));
    final VaccineStorageProfile prevnarProfile =
        (await database.storageProfilesFor(prevnar.id)).single;
    expect(
      prevnarProfile.verificationStatus,
      StorageVerificationStatus.verificationRequired,
    );

    final VaccineProduct zoster = catalog.firstWhere(
      (VaccineProduct product) => product.productName == '스카이조스터주',
    );
    final VaccineStorageProfile zosterProfile =
        (await database.storageProfilesFor(zoster.id)).single;
    expect(zosterProfile.timeLimitNotes, contains('30분'));
    expect(zosterProfile.timeLimitNotes, contains('운송 시간 제한이 아닙니다'));

    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: '${tempDir.path}${Platform.pathSeparator}vaxtrust.db',
    );
    await database.open();
    expect(await database.allVaccineProducts(), hasLength(6));
    expect(await database.vaccineProducts(), hasLength(2));
    expect(await database.storageProfilesFor(comirnaty.id), hasLength(2));
    expect(
      (await database.allVaccineProducts()).where(
        (VaccineProduct product) => !product.isActive,
      ),
      hasLength(4),
    );
  });

  test('버전 6 운송 건의 온도와 검토 기록은 유지되고 자동 매칭하지 않는다', () async {
    final String legacyPath =
        '${tempDir.path}${Platform.pathSeparator}legacy-v6.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 6,
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
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              owner_user_id INTEGER NOT NULL,
              assignee_user_id INTEGER NOT NULL,
              participation_code TEXT NOT NULL,
              vaccine TEXT NOT NULL,
              manufacturer TEXT NOT NULL,
              lot TEXT NOT NULL,
              expiry_date TEXT NOT NULL,
              quantity INTEGER NOT NULL,
              origin TEXT NOT NULL,
              destination TEXT NOT NULL,
              target_range TEXT NOT NULL,
              temp_min REAL NOT NULL,
              temp_max REAL NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              source TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE quality_reviews (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
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
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              shipment_id INTEGER NOT NULL,
              temperature_c REAL NOT NULL,
              measured_at TEXT NOT NULL,
              recorded_at TEXT NOT NULL,
              source TEXT NOT NULL,
              assignee_user_id INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE temperature_excursions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
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
          await db.insert('users', <String, Object?>{
            'login_id': 'kept',
            'password_hash': 'hash',
            'password_salt': 'salt',
            'password_iterations': 1,
            'role': 'transporter',
            'created_at': '2026-11-15T00:00:00.000Z',
          });
          await db.insert('shipments', <String, Object?>{
            'owner_user_id': 1,
            'assignee_user_id': 1,
            'participation_code': 'VX-KEEP01',
            'vaccine': '스카이셀플루4가프리필드시린지',
            'manufacturer': '직접 입력',
            'lot': 'LOT-KEEP',
            'expiry_date': '2027-01-01',
            'quantity': 4,
            'origin': '인천',
            'destination': '서울',
            'target_range': '3 ~ 9°C',
            'temp_min': 3,
            'temp_max': 9,
            'status': 'registered',
            'created_at': '2026-11-16T00:00:00.000Z',
            'source': 'user_input',
          });
          await db.insert('quality_reviews', <String, Object?>{
            'shipment_id': 1,
            'reviewer_user_id': 1,
            'review_status': 'review_completed',
            'review_comment': '기존 검토',
            'created_at': '2026-11-16T01:00:00.000Z',
            'updated_at': '2026-11-16T01:00:00.000Z',
          });
          await db.insert('temperature_readings', <String, Object?>{
            'shipment_id': 1,
            'temperature_c': 5,
            'measured_at': '2026-11-16T02:00:00.000Z',
            'recorded_at': '2026-11-16T02:00:00.000Z',
            'source': 'demo_virtual',
            'assignee_user_id': 1,
          });
          await db.insert('temperature_excursions', <String, Object?>{
            'shipment_id': 1,
            'direction': 'above_max',
            'started_at': '2026-11-16T02:00:00.000Z',
            'last_out_of_range_at': '2026-11-16T02:00:05.000Z',
            'min_temperature': 9.4,
            'max_temperature': 9.4,
            'data_gap_detected': 0,
            'status': 'open',
            'created_at': '2026-11-16T02:00:00.000Z',
            'updated_at': '2026-11-16T02:00:00.000Z',
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
    expect(await upgraded.userVersion(), 11);
    expect(await upgraded.allVaccineProducts(), hasLength(6));
    expect(await upgraded.vaccineProducts(), hasLength(2));
    final List<Map<String, Object?>> shipments = await upgraded.tableRows(
      'shipments',
    );
    expect(shipments.single['vaccine'], '스카이셀플루4가프리필드시린지');
    expect(shipments.single['temp_min'], 3);
    expect(shipments.single['temp_max'], 9);
    expect(shipments.single['target_range'], '3 ~ 9°C');
    expect(shipments.single['vaccine_product_id'], isNull);
    expect(shipments.single['status'], 'registered');
    expect(shipments.single['demo_mode'], isNull);
    final List<Map<String, Object?>> reviews = await upgraded.tableRows(
      'quality_reviews',
    );
    expect(reviews.single['review_comment'], '기존 검토');
    expect(await upgraded.tableRows('temperature_readings'), hasLength(1));
    expect(await upgraded.tableRows('temperature_excursions'), hasLength(1));
    expect(await upgraded.tableRows('users'), hasLength(1));
    await upgraded.close();

    final AppDatabase reopened = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    await reopened.open();
    expect(await reopened.allVaccineProducts(), hasLength(6));
    expect(await reopened.vaccineProducts(), hasLength(2));
    expect((await reopened.tableRows('shipments')).single['temp_min'], 3);
    await reopened.close();
  });

  test('적용 범위와 권장 범위를 따로 저장하고 이탈 감지는 적용 범위를 본다', () async {
    final AppUser courier = await database.createUser(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final List<VaccineProduct> products = await database.vaccineProducts();
    final VaccineProduct comirnaty = products.firstWhere(
      (VaccineProduct product) => product.productName == '코미나티제이엔원주',
    );
    final VaccineStorageProfile frozen =
        (await database.storageProfilesFor(comirnaty.id)).firstWhere(
          (VaccineStorageProfile profile) => profile.storageStage == 'frozen',
        );
    final ShipmentRecord created = await database.createShipment(
      ownerUserId: courier.id,
      draft: NewShipment(
        vaccine: comirnaty.productName,
        manufacturer: comirnaty.manufacturer!,
        lot: 'LOT-SNAP',
        expiryDate: '2027-11-19',
        quantity: 2,
        origin: '인천',
        destination: '서울',
        targetRange: '2 ~ 8°C',
        tempMin: 2,
        tempMax: 8,
        vaccineProductId: comirnaty.id,
        storageProfileId: frozen.id,
      ),
    );
    expect(created.recommendedMin, -90);
    expect(created.recommendedMax, -60);
    expect(created.tempMin, 2);
    expect(created.tempMax, 8);
    expect(created.actualMin, 2);
    expect(created.actualMax, 8);
    expect(created.appliedRangeDiffersFromRecommendation, isTrue);
    expect(created.selectedStorageStage, '냉동 보관');
    expect(created.storageProfileReference, contains('202402096'));

    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final DateTime at = DateTime.utc(2026, 11, 19, 1);
    await database.recordMeasuredSample(
      shipmentId: created.id,
      at: at,
      celsius: 5,
    );
    expect(
      await database.excursionsFor(userId: courier.id, shipmentId: created.id),
      isEmpty,
    );
    await database.recordMeasuredSample(
      shipmentId: created.id,
      at: at.add(const Duration(seconds: 5)),
      celsius: -70,
    );
    expect(
      await database.excursionsFor(userId: courier.id, shipmentId: created.id),
      hasLength(1),
    );
    final ShipmentRecord stored = (await database.shipmentVisibleTo(
      userId: courier.id,
      shipmentId: created.id,
    ))!;
    final ShipmentInsight insight = const ShipmentAnalytics().inspect(
      shipment: stored,
      readings: await database.temperaturesForShipment(created.id),
      excursions: await database.excursionsFor(
        userId: courier.id,
        shipmentId: created.id,
      ),
    );
    expect(insight.excursions.count, 1);
    expect(insight.risk.level, OperationalRiskLevel.high);

    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: '${tempDir.path}${Platform.pathSeparator}vaxtrust.db',
    );
    await database.open();
    final ShipmentRecord restored = (await database.shipmentVisibleTo(
      userId: courier.id,
      shipmentId: created.id,
    ))!;
    expect(restored.selectedProductName, '코미나티제이엔원주');
    expect(restored.recommendedMin, -90);
    expect(restored.tempMin, 2);
    expect(restored.tempMax, 8);
  });

  test('비활성 제품과 다른 제품의 보관 단계는 신규 등록을 거절한다', () async {
    final AppUser courier = await database.createUser(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final List<VaccineProduct> catalog = await database.allVaccineProducts();
    final VaccineProduct shingrix = catalog.firstWhere(
      (VaccineProduct product) => product.productName == '싱그릭스주',
    );
    final VaccineProduct comirnaty = catalog.firstWhere(
      (VaccineProduct product) => product.productName == '코미나티제이엔원주',
    );
    final VaccineStorageProfile shingrixProfile =
        (await database.storageProfilesFor(shingrix.id)).single;
    final VaccineStorageProfile frozen =
        (await database.storageProfilesFor(comirnaty.id)).firstWhere(
          (VaccineStorageProfile profile) => profile.storageStage == 'frozen',
        );

    NewShipment draft({
      required int? productId,
      required int? profileId,
      required String lot,
    }) {
      return NewShipment(
        vaccine: '시도',
        manufacturer: '시도',
        lot: lot,
        expiryDate: '2027-11-20',
        quantity: 1,
        origin: '인천',
        destination: '서울',
        targetRange: '2 ~ 8°C',
        tempMin: 2,
        tempMax: 8,
        vaccineProductId: productId,
        storageProfileId: profileId,
      );
    }

    await expectLater(
      () => database.createShipment(
        ownerUserId: courier.id,
        draft: draft(
          productId: shingrix.id,
          profileId: shingrixProfile.id,
          lot: 'LOT-INACTIVE',
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message,
          'message',
          '사용 중지된 백신은 선택할 수 없습니다.',
        ),
      ),
    );
    await expectLater(
      () => database.createShipment(
        ownerUserId: courier.id,
        draft: draft(
          productId: comirnaty.id,
          profileId: shingrixProfile.id,
          lot: 'LOT-MISMATCH',
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message,
          'message',
          '선택한 백신의 보관 단계가 아닙니다.',
        ),
      ),
    );
    await expectLater(
      () => database.createShipment(
        ownerUserId: courier.id,
        draft: draft(productId: 9999, profileId: frozen.id, lot: 'LOT-MISSING'),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message,
          'message',
          '등록된 백신을 찾을 수 없습니다.',
        ),
      ),
    );
    expect(await database.tableRows('shipments'), isEmpty);
    expect(shingrix.isActive, isFalse);
    expect(
      (await database.allVaccineProducts()).any(
        (VaccineProduct product) => product.id == shingrix.id,
      ),
      isTrue,
    );
  });

  testWidgets('보관 단계에 따라 온도가 바뀌고 다른 값에는 경고가 나온다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ShipmentSetupScreen()),
    );
    await tester.pump();

    expect(find.byKey(const Key('vaccine-product')), findsOneWidget);
    expect(database.loadedVaccineProducts, hasLength(2));
    expect(
      database.loadedVaccineProducts
          .map((VaccineProduct product) => product.productName)
          .toList(),
      <String>['코미나티제이엔원주', '스카이셀플루4가프리필드시린지'],
    );
    expect(find.text('참고 보관 온도 2 ~ 8°C'), findsOneWidget);
    expect(find.byKey(const Key('handling-notes')), findsOneWidget);
    expect(find.byKey(const Key('temperature-range-warning')), findsNothing);

    final VaccineProduct comirnaty = database.loadedVaccineProducts.firstWhere(
      (VaccineProduct product) => product.productName == '코미나티제이엔원주',
    );
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const Key('vaccine-product')),
        )
        .onChanged!(comirnaty.id);
    await tester.pump();
    expect(find.text('참고 보관 온도 -90 ~ -60°C'), findsOneWidget);

    final VaccineStorageProfile thawed = database
        .loadedProfilesFor(comirnaty.id)
        .firstWhere(
          (VaccineStorageProfile profile) =>
              profile.storageStage == 'thawed_refrigerated',
        );
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const Key('storage-profile')),
        )
        .onChanged!(thawed.id);
    await tester.pump();
    expect(find.text('참고 보관 온도 2 ~ 8°C'), findsOneWidget);
    expect(
      find.text('해동 후 재냉동 금지. 차광. 제품별 해동 및 사용 전 취급 조건을 확인합니다.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('actual-temp-min')), '3');
    await tester.pump();
    expect(find.byKey(const Key('temperature-range-warning')), findsOneWidget);
    expect(find.text(temperatureRangeMismatchWarning), findsOneWidget);
  });

  testWidgets('역할별로 보관 조건 스냅샷을 읽기만 한다', (WidgetTester tester) async {
    final ShipmentRecord shipment = ShipmentRecord(
      id: 8,
      ownerUserId: 1,
      assigneeUserId: 1,
      participationCode: 'VX-ROLE',
      vaccine: '프리베나프리필드시린지',
      manufacturer: '입력값',
      lot: 'LOT',
      expiryDate: '2027-01-01',
      quantity: 1,
      origin: '인천',
      destination: '서울',
      targetRange: '2 ~ 8°C',
      tempMin: 2,
      tempMax: 8,
      status: ShipmentStatus.registered,
      createdAt: DateTime.utc(2026, 11, 19),
      source: ShipmentRecord.userInputSource,
      vaccineProductId: 4,
      storageProfileId: 4,
      selectedProductName: '프리베나프리필드시린지',
      selectedStorageStage: '냉장 보관',
      recommendedMin: 2,
      recommendedMax: 8,
      actualMin: 2,
      actualMax: 8,
      storageProfileReference: '검증 상태: 추가 확인 필요',
      handlingNotesSnapshot: '동결 금지. 차광.',
    );
    AppUser user(UserRole role) {
      return AppUser(
        id: 1,
        loginId: role.name,
        role: role,
        createdAt: DateTime.utc(2026, 11, 19),
      );
    }

    Future<void> show(UserRole role) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageConditionPanel(
              user: user(role),
              shipment: shipment,
              initiallyExpanded: true,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(UserRole.transporter);
    expect(find.byKey(const Key('storage-handling')), findsOneWidget);
    expect(find.byKey(const Key('storage-source')), findsNothing);
    expect(find.text('동결 금지. 차광.'), findsOneWidget);

    await show(UserRole.qualityManager);
    expect(find.byKey(const Key('storage-source')), findsOneWidget);
    expect(find.textContaining('추가 확인 필요'), findsOneWidget);
    expect(find.text('참고 범위와 실제 적용 범위가 같습니다.'), findsOneWidget);
    expect(find.text('제조사 미확인'), findsOneWidget);

    await show(UserRole.medicalStaff);
    expect(find.byKey(const Key('storage-handling')), findsOneWidget);
    expect(find.byKey(const Key('storage-review-pointer')), findsOneWidget);
    expect(find.byKey(const Key('storage-source')), findsNothing);

    final ShipmentRecord legacy = ShipmentRecord(
      id: 1,
      ownerUserId: 1,
      assigneeUserId: 1,
      participationCode: 'VX-OLD',
      vaccine: '인플루엔자 4가',
      manufacturer: '직접 입력',
      lot: 'OLD',
      expiryDate: '2027-01-01',
      quantity: 1,
      origin: '인천',
      destination: '서울',
      targetRange: '3 ~ 9°C',
      tempMin: 3,
      tempMax: 9,
      status: ShipmentStatus.registered,
      createdAt: DateTime.utc(2026, 11, 16),
      source: ShipmentRecord.userInputSource,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageConditionPanel(
            user: user(UserRole.qualityManager),
            shipment: legacy,
            initiallyExpanded: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('storage-legacy')), findsOneWidget);
    expect(find.text('3 ~ 9°C'), findsOneWidget);
  });
}
