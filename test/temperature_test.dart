import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/demo_temperature_session.dart';
import 'package:vaxtrust/data/temperature_policy.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;
  late DemoTemperatureSession session;
  late DateTime now;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_temperature_');
    databasePath = '${tempDir.path}${Platform.pathSeparator}vaxtrust.db';
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    now = DateTime.now().toUtc();
    session = DemoTemperatureSession(
      database: database,
      clock: () => now,
      policy: InRangeTemperaturePolicy(random: Random(7)),
    );
  });

  tearDown(() async {
    session.pauseGeneration();
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const NewShipment draft = NewShipment(
    vaccine: '인플루엔자 4가',
    manufacturer: 'Korea Vaccine',
    lot: 'LOT-TEMP',
    expiryDate: '2027-11-16',
    quantity: 80,
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

  Future<ShipmentRecord> createOwned(AppUser owner, String lot) {
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
        targetRange: draft.targetRange,
        tempMin: draft.tempMin,
        tempMax: draft.tempMax,
      ),
    );
  }

  test('운송 시작은 한 번만 되고 범위 안에서 이어서 기록된다', () async {
    final AppUser courierA = await user('courierA', UserRole.transporter);
    final AppUser courierC = await user('courierC', UserRole.transporter);
    final AppUser quality = await user('quality', UserRole.qualityManager);
    final ShipmentRecord created = await createOwned(courierA, 'LOT-START');

    final ShipmentRecord started = await database.startTransport(
      actorUserId: courierA.id,
      shipmentId: created.id,
    );
    expect(started.status, ShipmentStatus.inTransit);
    expect(started.startedAt, isNotNull);
    expect(started.id, created.id);
    expect(await database.temperatureCount(created.id), 1);
    final TemperatureReading first = (await database.latestTemperature(
      created.id,
    ))!;
    expect(first.source, TemperatureReading.demoVirtualSource);
    expect(first.assigneeUserId, courierA.id);
    expect(first.celsius, inInclusiveRange(2, 8));
    expect(first.recordedAt.difference(first.measuredAt).inSeconds.abs(), 0);

    expect(
      () => database.startTransport(
        actorUserId: courierA.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );
    expect(
      () => database.startTransport(
        actorUserId: courierC.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );
    expect(
      () => database.startTransport(
        actorUserId: quality.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );
    expect(await database.temperatureCount(created.id), 1);

    now = first.measuredAt.add(const Duration(seconds: 1));
    await session.recordDue();
    expect(await database.temperatureCount(created.id), 1);

    now = first.measuredAt.add(const Duration(hours: 1));
    await session.recordDue();
    final List<TemperatureReading> readings = await database.recentTemperatures(
      created.id,
    );
    expect(readings, hasLength(2));
    expect(readings.first.measuredAt.isAfter(readings.last.measuredAt), isTrue);
    expect(
      (readings.last.celsius - readings.first.celsius).abs(),
      lessThanOrEqualTo(0.4),
    );
    expect(readings.first.celsius, inInclusiveRange(2, 8));
    expect(
      readings.first.measuredAt.difference(readings.last.measuredAt).inMinutes,
      greaterThan(50),
    );

    final ShipmentRecord second = await createOwned(courierA, 'LOT-OTHER');
    await database.startTransport(
      actorUserId: courierA.id,
      shipmentId: second.id,
    );
    now = DateTime.now().toUtc().add(const Duration(hours: 2));
    await session.recordDue();
    expect(await database.temperatureCount(created.id), 3);
    expect(await database.temperatureCount(second.id), 2);
    TemperatureReading? previous = await database.latestTemperature(second.id);
    for (var step = 0; step < 12; step++) {
      now = previous!.measuredAt.add(const Duration(seconds: 5));
      await session.recordDue();
      final TemperatureReading next = (await database.latestTemperature(
        second.id,
      ))!;
      expect(next.celsius, inInclusiveRange(2, 8));
      expect((next.celsius - previous.celsius).abs(), lessThanOrEqualTo(0.4));
      previous = next;
    }

    session.ensureRunning();
    session.ensureRunning();
    expect(session.activeTimerCount, 1);
    expect(session.interval, const Duration(seconds: 5));
    final int beforeRestore = await database.temperatureCount(created.id);
    await session.restore();
    expect(session.isRunning, isTrue);
    expect(await database.temperatureCount(created.id), beforeRestore);
    session.pauseGeneration();
    expect(session.isRunning, isFalse);
  });

  test('인수인계 뒤에도 기록이 남고 완료하면 생성이 멈춘다', () async {
    final AppUser courierA = await user('courierA', UserRole.transporter);
    final AppUser courierB = await user('courierB', UserRole.transporter);
    final AppUser quality = await user('quality', UserRole.qualityManager);
    final AppUser medical = await user('medical', UserRole.medicalStaff);
    final ShipmentRecord created = await createOwned(courierA, 'LOT-DONE');
    await database.joinByParticipationCode(
      userId: quality.id,
      code: created.participationCode,
    );
    await database.joinByParticipationCode(
      userId: medical.id,
      code: created.participationCode,
    );
    await database.startTransport(
      actorUserId: courierA.id,
      shipmentId: created.id,
    );
    final TemperatureReading startedReading = (await database.latestTemperature(
      created.id,
    ))!;
    now = startedReading.measuredAt.add(const Duration(seconds: 5));
    await session.recordDue();

    final requested = await database.requestHandover(
      actorUserId: courierA.id,
      shipmentId: created.id,
      toLoginId: courierB.loginId,
      location: '서울역',
    );
    await database.acceptHandover(
      actorUserId: courierB.id,
      transferId: requested.id,
    );
    expect(await database.temperatureCount(created.id), 2);
    final ShipmentRecord handed = (await database.shipmentVisibleTo(
      userId: courierB.id,
      shipmentId: created.id,
    ))!;
    expect(handed.assigneeUserId, courierB.id);
    expect(handed.status, ShipmentStatus.inTransit);
    expect(handed.startedAt, isNotNull);

    now = startedReading.measuredAt.add(const Duration(seconds: 20));
    await session.recordDue();
    final TemperatureReading afterHandover = (await database.latestTemperature(
      created.id,
    ))!;
    expect(afterHandover.assigneeUserId, courierB.id);
    expect(await database.temperatureCount(created.id), 3);
    session.ensureRunning();
    expect(session.isRunning, isTrue);

    expect(
      () => database.completeTransport(
        actorUserId: courierA.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );
    final ShipmentRecord completed = await database.completeTransport(
      actorUserId: courierB.id,
      shipmentId: created.id,
    );
    expect(completed.status, ShipmentStatus.completed);
    expect(completed.completedAt, isNotNull);
    now = startedReading.measuredAt.add(const Duration(hours: 3));
    await session.recordDue();
    expect(await database.temperatureCount(created.id), 3);
    expect(session.isRunning, isFalse);
    expect(
      () => database.startTransport(
        actorUserId: courierB.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );
    expect(
      () => database.completeTransport(
        actorUserId: courierB.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );

    expect(
      (await database.shipmentVisibleTo(
        userId: quality.id,
        shipmentId: created.id,
      ))!.status,
      ShipmentStatus.completed,
    );
    expect(await database.recentTemperatures(created.id), hasLength(3));
    expect(
      (await database.shipmentVisibleTo(
        userId: medical.id,
        shipmentId: created.id,
      ))!.id,
      created.id,
    );
    expect(
      (await database.latestTemperature(created.id))!.sourceLabel,
      '시연용 가상 데이터',
    );

    await database.clearSession();
    expect(await database.temperatureCount(created.id), 3);

    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    final ShipmentRecord reopened = (await database.shipmentVisibleTo(
      userId: courierB.id,
      shipmentId: created.id,
    ))!;
    expect(reopened.status, ShipmentStatus.completed);
    expect(await database.temperatureCount(created.id), 3);
    expect(await database.recentTemperatures(created.id), hasLength(3));
  });

  test('버전 3 운송 건은 온도 테이블을 추가해도 남는다', () async {
    await database.close();
    final String legacyPath =
        '${tempDir.path}${Platform.pathSeparator}legacy.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (Database db, int version) async {
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
        },
      ),
    );
    await legacy.insert('shipments', <String, Object?>{
      'owner_user_id': 1,
      'assignee_user_id': 1,
      'participation_code': 'VX-KEEP',
      'vaccine': '인플루엔자 4가',
      'manufacturer': 'Korea Vaccine',
      'lot': 'LOT-KEEP',
      'expiry_date': '2027-01-01',
      'quantity': 10,
      'origin': '출발',
      'destination': '도착',
      'target_range': '2 ~ 8°C',
      'temp_min': 2,
      'temp_max': 8,
      'status': 'registered',
      'created_at': '2026-02-01T00:00:00.000Z',
      'source': 'user_input',
    });
    await legacy.close();

    final AppDatabase upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    await upgraded.open();
    expect(
      await upgraded.columnNames('shipments'),
      containsAll(<String>['started_at', 'completed_at', 'status']),
    );
    expect(
      await upgraded.columnNames('temperature_readings'),
      containsAll(<String>[
        'shipment_id',
        'temperature_c',
        'measured_at',
        'recorded_at',
        'source',
        'assignee_user_id',
      ]),
    );
    final List<Map<String, Object?>> rows = await upgraded.tableRows(
      'shipments',
    );
    expect(rows.single['lot'], 'LOT-KEEP');
    expect(rows.single['status'], 'registered');
    expect(rows.single['started_at'], isNull);
    await upgraded.close();
  });
}
