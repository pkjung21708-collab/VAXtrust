import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/demo_scenario_policy.dart';
import 'package:vaxtrust/data/temperature_policy.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/demo_scenario.dart';
import 'package:vaxtrust/models/excursion_action.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_excursion.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_excursion_');
    databasePath = '${tempDir.path}${Platform.pathSeparator}vaxtrust.db';
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
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
    lot: 'LOT-EX',
    expiryDate: '2027-11-16',
    quantity: 40,
    origin: 'Incheon Vaccine Center',
    destination: 'Seoul National University Hospital',
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

  Future<ShipmentRecord> createOwned(
    AppUser owner, {
    String lot = 'LOT-EX',
    double tempMin = 2,
    double tempMax = 8,
    String targetRange = '2 ~ 8°C',
  }) {
    return database.createShipment(
      ownerUserId: owner.id,
      draft: NewShipment(
        vaccine: draft.vaccine,
        manufacturer: draft.manufacturer,
        lot: lot,
        expiryDate: draft.expiryDate,
        quantity: draft.quantity,
        origin: draft.origin,
        destination: draft.destination,
        targetRange: targetRange,
        tempMin: tempMin,
        tempMax: tempMax,
      ),
    );
  }

  Future<void> measure(int shipmentId, DateTime at, double celsius) async {
    final TemperatureReading? reading = await database.recordMeasuredSample(
      shipmentId: shipmentId,
      at: at,
      celsius: celsius,
    );
    expect(reading, isNotNull);
  }

  Future<List<TemperatureExcursion>> events(AppUser actor, int shipmentId) {
    return database.excursionsFor(userId: actor.id, shipmentId: shipmentId);
  }

  test('정상 온도와 경계값은 이탈을 만들지 않고 상한과 하한은 구분한다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier);
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final DateTime start = DateTime.now().toUtc().add(
      const Duration(seconds: 5),
    );
    await measure(created.id, start, 4.5);
    await measure(created.id, start.add(const Duration(seconds: 5)), 8.0);
    await measure(created.id, start.add(const Duration(seconds: 10)), 2.0);
    expect(await events(courier, created.id), isEmpty);

    await measure(created.id, start.add(const Duration(seconds: 15)), 8.1);
    await measure(created.id, start.add(const Duration(seconds: 20)), 9.2);
    List<TemperatureExcursion> rows = await events(courier, created.id);
    expect(rows, hasLength(1));
    expect(rows.single.direction, TemperatureExcursion.aboveMax);
    expect(rows.single.isOpen, isTrue);
    expect(rows.single.id, (await events(courier, created.id)).single.id);
    expect(rows.single.maxTemperature, 9.2);
    expect(rows.single.minTemperature, 8.1);
    expect(rows.single.dataGapDetected, isFalse);

    await measure(created.id, start.add(const Duration(seconds: 25)), 4.5);
    rows = await events(courier, created.id);
    expect(rows.single.status, TemperatureExcursion.recoveredStatus);
    expect(rows.single.recoveredAt, isNotNull);
    expect(rows.single.maxTemperature, 9.2);
    expect(rows.single.durationLabel, isNot('지속시간 확인 필요'));

    await measure(created.id, start.add(const Duration(seconds: 30)), 1.9);
    rows = await events(courier, created.id);
    expect(rows, hasLength(2));
    expect(rows.last.direction, TemperatureExcursion.belowMin);
    expect(rows.last.isOpen, isTrue);
    expect(rows.first.status, TemperatureExcursion.recoveredStatus);
  });

  test('다른 운송 건의 범위로 이탈을 판정한다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(
      courier,
      lot: 'LOT-WARM',
      tempMin: 15,
      tempMax: 25,
      targetRange: '15 ~ 25°C',
    );
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final DateTime start = DateTime.now().toUtc().add(
      const Duration(seconds: 5),
    );
    await measure(created.id, start, 16);
    await measure(created.id, start.add(const Duration(seconds: 5)), 25);
    expect(await events(courier, created.id), isEmpty);
    await measure(created.id, start.add(const Duration(seconds: 10)), 25.1);
    final TemperatureExcursion row = (await events(courier, created.id)).single;
    expect(row.direction, TemperatureExcursion.aboveMax);
  });

  test('측정이 비면 이탈이 한 시간 지속됐다고 단정하지 않는다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-GAP');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final DateTime outAt = DateTime.now().toUtc().add(
      const Duration(minutes: 1),
    );
    final DateTime backAt = outAt.add(const Duration(hours: 1));
    await measure(created.id, outAt, 9);
    await measure(created.id, backAt, 4);
    final TemperatureExcursion row = (await events(courier, created.id)).single;
    expect(row.dataGapDetected, isTrue);
    expect(row.durationLabel, '지속시간 확인 필요');
    expect(row.recoveredAt, isNotNull);
    expect(row.lastOutOfRangeAt.difference(row.startedAt).inSeconds, 0);
    expect(
      row.recoveredAt!.difference(row.startedAt).inMinutes,
      greaterThan(30),
    );
  });

  test('문 열림 시연은 천천히 벗어났다가 돌아오고 원인 기록을 만들지 않는다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-DOOR');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final DemoScenario started = await database.startDemoScenario(
      actorUserId: courier.id,
      shipmentId: created.id,
      type: DemoScenario.doorOpen,
    );
    expect(started.phase, DemoScenario.rising);
    expect(await events(courier, created.id), isEmpty);

    const DemoScenarioSettings settings = DemoScenarioSettings(
      stepCelsius: 1,
      holdSamples: 2,
      breachMargin: 0.4,
    );
    DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    final List<double> values = <double>[];
    DemoScenario? active = started;
    for (int index = 0; index < 30 && active != null; index++) {
      final TemperatureReading? reading = await database.recordDemoSample(
        shipmentId: created.id,
        at: at,
        policy: InRangeTemperaturePolicy(random: Random(1)),
        scenarioSettings: settings,
      );
      expect(reading, isNotNull);
      values.add(reading!.celsius);
      at = at.add(const Duration(seconds: 5));
      active = await database.activeScenarioFor(
        userId: courier.id,
        shipmentId: created.id,
      );
    }
    expect(active, isNull);
    expect(values.length, greaterThan(2));
    for (int index = 1; index < values.length; index++) {
      expect(
        (values[index] - values[index - 1]).abs(),
        lessThanOrEqualTo(1 + 1e-9),
      );
    }
    expect(values.any((double value) => value > 8), isTrue);
    expect(values.last, inInclusiveRange(2, 8));
    final List<TemperatureExcursion> rows = await events(courier, created.id);
    expect(rows, hasLength(1));
    expect(rows.single.direction, TemperatureExcursion.aboveMax);
    expect(rows.single.status, TemperatureExcursion.recoveredStatus);
    expect(
      await database.actionsForExcursion(
        userId: courier.id,
        excursionId: rows.single.id,
      ),
      isEmpty,
    );
  });

  test('냉각 장치 이상은 종료할 때까지 이탈을 유지한다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-COOL');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    await database.startDemoScenario(
      actorUserId: courier.id,
      shipmentId: created.id,
      type: DemoScenario.coolingFault,
    );
    const DemoScenarioSettings settings = DemoScenarioSettings(
      stepCelsius: 1,
      holdSamples: 2,
      breachMargin: 0.4,
    );
    DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    TemperatureExcursion? open;
    for (int index = 0; index < 20 && open == null; index++) {
      await database.recordDemoSample(
        shipmentId: created.id,
        at: at,
        policy: InRangeTemperaturePolicy(random: Random(1)),
        scenarioSettings: settings,
      );
      at = at.add(const Duration(seconds: 5));
      final List<TemperatureExcursion> rows = await events(courier, created.id);
      open = rows.where((TemperatureExcursion row) => row.isOpen).firstOrNull;
    }
    expect(open, isNotNull);
    expect(
      (await database.activeScenarioFor(
        userId: courier.id,
        shipmentId: created.id,
      ))?.phase,
      DemoScenario.holding,
    );
    final DemoScenario ending = await database.endDemoScenario(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    expect(ending.phase, DemoScenario.recovering);
    expect((await events(courier, created.id)).single.isOpen, isTrue);

    DemoScenario? active = ending;
    for (int index = 0; index < 20 && active != null; index++) {
      await database.recordDemoSample(
        shipmentId: created.id,
        at: at,
        policy: InRangeTemperaturePolicy(random: Random(1)),
        scenarioSettings: settings,
      );
      at = at.add(const Duration(seconds: 5));
      active = await database.activeScenarioFor(
        userId: courier.id,
        shipmentId: created.id,
      );
    }
    expect(active, isNull);
    expect((await events(courier, created.id)).single.isOpen, isFalse);
  });

  test('과냉각 시연은 하한 아래로 내려갔다가 돌아온다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-COLD');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    await database.startDemoScenario(
      actorUserId: courier.id,
      shipmentId: created.id,
      type: DemoScenario.overcool,
    );
    const DemoScenarioSettings settings = DemoScenarioSettings(
      stepCelsius: 1,
      holdSamples: 2,
      breachMargin: 0.4,
    );
    DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    DemoScenario? active = await database.activeScenarioFor(
      userId: courier.id,
      shipmentId: created.id,
    );
    final List<double> values = <double>[];
    for (int index = 0; index < 30 && active != null; index++) {
      final TemperatureReading? reading = await database.recordDemoSample(
        shipmentId: created.id,
        at: at,
        policy: InRangeTemperaturePolicy(random: Random(1)),
        scenarioSettings: settings,
      );
      values.add(reading!.celsius);
      at = at.add(const Duration(seconds: 5));
      active = await database.activeScenarioFor(
        userId: courier.id,
        shipmentId: created.id,
      );
    }
    expect(values.any((double value) => value < 2), isTrue);
    expect(values.last, inInclusiveRange(2, 8));
    final TemperatureExcursion row = (await events(courier, created.id)).single;
    expect(row.direction, TemperatureExcursion.belowMin);
    expect(row.isOpen, isFalse);
  });

  test('시나리오는 하나만 진행되고 앱을 다시 열어도 유지 단계를 건너뛰지 않는다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-ONE');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    await database.startDemoScenario(
      actorUserId: courier.id,
      shipmentId: created.id,
      type: DemoScenario.coolingFault,
    );
    expect(
      () => database.startDemoScenario(
        actorUserId: courier.id,
        shipmentId: created.id,
        type: DemoScenario.overcool,
      ),
      throwsA(isA<ExcursionException>()),
    );
    const DemoScenarioSettings settings = DemoScenarioSettings(
      stepCelsius: 1,
      holdSamples: 4,
      breachMargin: 0.4,
    );
    DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    DemoScenario? active;
    for (int index = 0; index < 20; index++) {
      await database.recordDemoSample(
        shipmentId: created.id,
        at: at,
        policy: InRangeTemperaturePolicy(random: Random(1)),
        scenarioSettings: settings,
      );
      at = at.add(const Duration(seconds: 5));
      active = await database.activeScenarioFor(
        userId: courier.id,
        shipmentId: created.id,
      );
      if (active?.phase == DemoScenario.holding) {
        break;
      }
    }
    expect(active?.phase, DemoScenario.holding);
    final int held = active!.holdSamples;
    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    final DemoScenario? restored = await database.activeScenarioFor(
      userId: courier.id,
      shipmentId: created.id,
    );
    expect(restored?.holdSamples, held);
    expect(restored?.phase, DemoScenario.holding);
    await database.recordDemoSample(
      shipmentId: created.id,
      at: at.add(const Duration(minutes: 30)),
      policy: InRangeTemperaturePolicy(random: Random(1)),
      scenarioSettings: settings,
    );
    final DemoScenario? next = await database.activeScenarioFor(
      userId: courier.id,
      shipmentId: created.id,
    );
    expect(next?.phase, DemoScenario.holding);
    expect(next?.holdSamples, held + 1);
    final TemperatureExcursion row = (await events(courier, created.id)).single;
    expect(row.dataGapDetected, isTrue);
    expect(row.durationLabel, '지속시간 확인 필요');
  });

  test('원인과 조치는 추가만 되고 이탈 기록은 남는다', () async {
    final AppUser courierA = await user('courierA', UserRole.transporter);
    final AppUser courierB = await user('courierB', UserRole.transporter);
    final AppUser quality = await user('quality', UserRole.qualityManager);
    final AppUser medical = await user('medical', UserRole.medicalStaff);
    final AppUser stranger = await user('outsider', UserRole.qualityManager);
    final ShipmentRecord created = await createOwned(courierA, lot: 'LOT-ACT');
    final ShipmentRecord started = await database.startTransport(
      actorUserId: courierA.id,
      shipmentId: created.id,
    );
    final DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    await measure(created.id, at, 9);
    final TemperatureExcursion excursion = (await events(
      courierA,
      created.id,
    )).single;

    final ExcursionAction first = await database.saveExcursionAction(
      actorUserId: courierA.id,
      excursionId: excursion.id,
      causeCategory: 'door_open',
      causeCertainty: ExcursionAction.suspected,
      description: '용기 문을 열었을 수 있다',
      actionTaken: '문을 닫고 온도를 다시 확인했다',
      reportedTo: '품질관리자',
    );
    final ExcursionAction revised = await database.saveExcursionAction(
      actorUserId: courierA.id,
      excursionId: excursion.id,
      causeCategory: 'loading',
      causeCertainty: ExcursionAction.confirmed,
      description: '상하차 중에 문이 열려 있었다',
      actionTaken: '상하차 후 문을 닫았다',
    );
    List<ExcursionAction> history = await database.actionsForExcursion(
      userId: courierA.id,
      excursionId: excursion.id,
    );
    expect(history, hasLength(2));
    expect(history.first.id, first.id);
    expect(history.first.description, '용기 문을 열었을 수 있다');
    expect(history.last.id, revised.id);
    expect(history.last.authorLoginId, 'courierA');
    expect((await events(courierA, created.id)).single.id, excursion.id);

    expect(
      () => database.saveExcursionAction(
        actorUserId: quality.id,
        excursionId: excursion.id,
        causeCategory: 'other',
        causeCertainty: ExcursionAction.suspected,
        description: '품질 계정은 수정할 수 없다',
        actionTaken: '없음',
      ),
      throwsA(isA<ExcursionException>()),
    );
    expect(
      () => database.saveExcursionAction(
        actorUserId: courierB.id,
        excursionId: excursion.id,
        causeCategory: 'other',
        causeCertainty: ExcursionAction.suspected,
        description: '다른 운송자는 수정할 수 없다',
        actionTaken: '없음',
      ),
      throwsA(isA<ExcursionException>()),
    );

    await database.requestHandover(
      actorUserId: courierA.id,
      shipmentId: created.id,
      toLoginId: 'courierB',
      location: '서울역',
    );
    final transfer = (await database.incomingHandovers(courierB.id)).single;
    await database.acceptHandover(
      actorUserId: courierB.id,
      transferId: transfer.id,
    );
    expect((await events(courierB, created.id)).single.id, excursion.id);
    history = await database.actionsForExcursion(
      userId: courierB.id,
      excursionId: excursion.id,
    );
    expect(history.first.authorLoginId, 'courierA');
    await database.saveExcursionAction(
      actorUserId: courierB.id,
      excursionId: excursion.id,
      causeCategory: 'environment',
      causeCertainty: ExcursionAction.suspected,
      description: '인계 후 추가로 확인했다',
      actionTaken: '용기를 그늘로 옮겼다',
    );
    history = await database.actionsForExcursion(
      userId: courierB.id,
      excursionId: excursion.id,
    );
    expect(history, hasLength(3));
    expect(history.first.authorLoginId, 'courierA');
    expect(history.last.authorLoginId, 'courierB');

    await database.joinByParticipationCode(
      userId: quality.id,
      code: started.participationCode,
    );
    await database.joinByParticipationCode(
      userId: medical.id,
      code: started.participationCode,
    );
    expect(await events(quality, created.id), hasLength(1));
    expect(
      await database.actionsForExcursion(
        userId: medical.id,
        excursionId: excursion.id,
      ),
      hasLength(3),
    );
    expect(
      () => database.excursionsFor(userId: stranger.id, shipmentId: created.id),
      throwsA(isA<ExcursionException>()),
    );
    final Map<int, ExcursionSummary> summary = await database
        .excursionSummaries(<int>[created.id]);
    expect(summary[created.id]?.count, 1);
    expect(summary[created.id]?.open, isTrue);

    await database.saveSession(courierB.id);
    await database.clearSession();
    expect(await database.currentSessionUser(), isNull);
    expect(await database.temperatureCount(created.id), greaterThan(1));
    expect((await events(courierB, created.id)).single.id, excursion.id);
  });

  test('운송 완료 후에는 시나리오를 시작할 수 없고 기록은 남는다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final AppUser other = await user('other', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-DONE');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    await measure(created.id, at, 9);
    await database.startDemoScenario(
      actorUserId: courier.id,
      shipmentId: created.id,
      type: DemoScenario.coolingFault,
    );
    final int readings = await database.temperatureCount(created.id);
    final ShipmentRecord completed = await database.completeTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    expect(completed.status, ShipmentStatus.completed);
    expect(await database.temperatureCount(created.id), readings);
    expect(
      await database.activeScenarioFor(
        userId: courier.id,
        shipmentId: created.id,
      ),
      isNull,
    );
    expect((await events(courier, created.id)).single.isOpen, isTrue);
    expect(
      () => database.startDemoScenario(
        actorUserId: courier.id,
        shipmentId: created.id,
        type: DemoScenario.doorOpen,
      ),
      throwsA(isA<ExcursionException>()),
    );
    expect(
      () => database.startDemoScenario(
        actorUserId: other.id,
        shipmentId: created.id,
        type: DemoScenario.doorOpen,
      ),
      throwsA(isA<ExcursionException>()),
    );
    await database.saveExcursionAction(
      actorUserId: courier.id,
      excursionId: (await events(courier, created.id)).single.id,
      causeCategory: 'unknown',
      causeCertainty: ExcursionAction.suspected,
      description: '완료 후에도 원인을 남긴다',
      actionTaken: '품질 확인을 요청했다',
    );
    expect((await events(courier, created.id)), hasLength(1));
  });

  test('일반 온도 생성은 범위를 벗어나지 않는다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await createOwned(courier, lot: 'LOT-SAFE');
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    DateTime at = DateTime.now().toUtc().add(const Duration(seconds: 5));
    for (int index = 0; index < 12; index++) {
      final TemperatureReading? reading = await database.recordDemoSample(
        shipmentId: created.id,
        at: at,
        policy: InRangeTemperaturePolicy(random: Random(3)),
      );
      expect(reading!.celsius, inInclusiveRange(2, 8));
      at = at.add(const Duration(seconds: 5));
    }
    expect(await events(courier, created.id), isEmpty);
  });

  test('버전 4 운송 건과 온도 기록을 유지한 채 5로 올린다', () async {
    final String legacyPath = '${tempDir.path}${Platform.pathSeparator}v4.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 4,
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
            CREATE TABLE session (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              user_id INTEGER NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE shipments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              owner_user_id INTEGER NOT NULL,
              assignee_user_id INTEGER NOT NULL,
              participation_code TEXT NOT NULL UNIQUE,
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
              started_at TEXT,
              completed_at TEXT,
              source TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE shipment_members (
              shipment_id INTEGER NOT NULL,
              user_id INTEGER NOT NULL,
              role TEXT NOT NULL,
              joined_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE shipment_transfers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              shipment_id INTEGER NOT NULL,
              from_user_id INTEGER NOT NULL,
              to_user_id INTEGER NOT NULL,
              status TEXT NOT NULL
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
        },
      ),
    );
    await legacy.insert('users', <String, Object?>{
      'login_id': 'courier',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'password_iterations': 1,
      'role': 'transporter',
      'created_at': '2026-11-16T00:00:00.000Z',
    });
    await legacy.insert('shipments', <String, Object?>{
      'owner_user_id': 1,
      'assignee_user_id': 1,
      'participation_code': 'VX-KEEP',
      'vaccine': 'MMR',
      'manufacturer': 'Korea Vaccine',
      'lot': 'LOT-KEEP',
      'expiry_date': '2027-05-01',
      'quantity': 4,
      'origin': '인천',
      'destination': '부산',
      'target_range': '2 ~ 8°C',
      'temp_min': 2,
      'temp_max': 8,
      'status': 'registered',
      'created_at': '2026-11-16T01:00:00.000Z',
      'source': 'user_input',
    });
    await legacy.insert('temperature_readings', <String, Object?>{
      'shipment_id': 1,
      'temperature_c': 4.2,
      'measured_at': '2026-11-16T01:05:00.000Z',
      'recorded_at': '2026-11-16T01:05:00.000Z',
      'source': 'demo_virtual',
      'assignee_user_id': 1,
    });
    await legacy.close();

    final AppDatabase upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    await upgraded.open();
    final List<ShipmentRecord> owned = await upgraded.shipmentsOwnedBy(1);
    expect(owned.single.lot, 'LOT-KEEP');
    expect(owned.single.participationCode, 'VX-KEEP');
    expect(await upgraded.temperatureCount(1), 1);
    expect(await upgraded.excursionsFor(userId: 1, shipmentId: 1), isEmpty);
    await upgraded.close();
  });
}
