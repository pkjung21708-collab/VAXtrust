import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/shipment_transfer.dart';
import 'package:vaxtrust/models/user_role.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_handover_');
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
    lot: 'LOT-HAND-1',
    expiryDate: '2027-11-15',
    quantity: 100,
    origin: 'Incheon Vaccine Center',
    destination: 'Seoul National University Hospital',
    targetRange: '2 ~ 8°C',
    tempMin: 2,
    tempMax: 8,
  );

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

  test('인수 수락은 담당자만 바꾸고 이력과 참여 연결을 남긴다', () async {
    final AppUser courierA = await database.createUser(
      loginId: 'courierA',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser courierB = await database.createUser(
      loginId: 'courierB',
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
    final ShipmentRecord created = await createOwned(courierA, 'LOT-HAND-1');
    await database.joinByParticipationCode(
      userId: quality.id,
      code: created.participationCode,
    );
    await database.joinByParticipationCode(
      userId: medical.id,
      code: created.participationCode,
    );

    final ShipmentTransfer requested = await database.requestHandover(
      actorUserId: courierA.id,
      shipmentId: created.id,
      toLoginId: 'courierB',
      location: '서울역',
      scheduledAt: DateTime.utc(2026, 11, 16, 3),
      note: '보냉 박스 확인',
    );
    expect(requested.status, TransferStatus.requested);
    expect(requested.handoverTempC, isNull);
    final ShipmentRecord before = (await database.shipmentVisibleTo(
      userId: courierA.id,
      shipmentId: created.id,
    ))!;
    expect(before.assigneeUserId, courierA.id);
    expect(await database.incomingHandovers(courierB.id), hasLength(1));
    expect(await database.outgoingHandovers(courierA.id), hasLength(1));
    expect(await database.incomingHandovers(quality.id), isEmpty);

    final ShipmentTransfer accepted = await database.acceptHandover(
      actorUserId: courierB.id,
      transferId: requested.id,
    );
    expect(accepted.status, TransferStatus.accepted);
    expect(accepted.respondedAt, isNotNull);
    final ShipmentRecord after = (await database.shipmentVisibleTo(
      userId: courierB.id,
      shipmentId: created.id,
    ))!;
    expect(after.id, created.id);
    expect(after.lot, created.lot);
    expect(after.participationCode, created.participationCode);
    expect(after.assigneeUserId, courierB.id);
    expect(
      (await database.shipmentsAssignedTo(courierB.id)).single.id,
      created.id,
    );
    expect(await database.shipmentsAssignedTo(courierA.id), isEmpty);
    expect(
      (await database.shipmentsPreviouslyAssigned(courierA.id)).single.id,
      created.id,
    );
    expect(await database.shipmentsOwnedBy(courierA.id), hasLength(1));
    expect(
      (await database.handoverHistoryForUser(courierA.id)).single.status,
      TransferStatus.accepted,
    );
    expect(
      (await database.handoverHistoryForUser(courierB.id)).single.id,
      accepted.id,
    );
    expect(
      () => database.acceptHandover(
        actorUserId: courierB.id,
        transferId: requested.id,
      ),
      throwsA(isA<TransferException>()),
    );

    expect(
      (await database.shipmentsJoinedBy(quality.id)).single.id,
      created.id,
    );
    expect(
      (await database.shipmentsJoinedBy(medical.id)).single.id,
      created.id,
    );
    final List<Map<String, Object?>> members = await database.tableRows(
      'shipment_members',
    );
    expect(
      members.map((Map<String, Object?> row) => row['user_id']),
      containsAll(<int>[courierA.id, quality.id, medical.id]),
    );

    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    final List<ShipmentTransfer> reopened = await database
        .handoverHistoryForShipment(created.id);
    expect(reopened.single.status, TransferStatus.accepted);
    expect(reopened.single.location, '서울역');
    expect(reopened.single.note, '보냉 박스 확인');
    expect(
      (await database.shipmentVisibleTo(
        userId: courierB.id,
        shipmentId: created.id,
      ))!.assigneeUserId,
      courierB.id,
    );
  });

  test('거절과 취소는 담당자를 유지하고 기록을 남긴다', () async {
    final AppUser courierA = await database.createUser(
      loginId: 'courierA',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser courierB = await database.createUser(
      loginId: 'courierB',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final ShipmentRecord rejectedShipment = await createOwned(
      courierA,
      'LOT-REJECT',
    );
    final ShipmentTransfer rejection = await database.requestHandover(
      actorUserId: courierA.id,
      shipmentId: rejectedShipment.id,
      toLoginId: courierB.loginId,
      location: '부산항',
    );
    final ShipmentTransfer rejected = await database.rejectHandover(
      actorUserId: courierB.id,
      transferId: rejection.id,
      reason: '일정 불가',
    );
    expect(rejected.status, TransferStatus.rejected);
    expect(rejected.rejectionReason, '일정 불가');
    expect(rejected.respondedAt, isNotNull);
    expect(
      (await database.shipmentVisibleTo(
        userId: courierA.id,
        shipmentId: rejectedShipment.id,
      ))!.assigneeUserId,
      courierA.id,
    );
    expect(await database.tableRows('shipment_transfers'), hasLength(1));

    final ShipmentRecord cancelledShipment = await createOwned(
      courierA,
      'LOT-CANCEL',
    );
    final ShipmentTransfer cancellation = await database.requestHandover(
      actorUserId: courierA.id,
      shipmentId: cancelledShipment.id,
      toLoginId: courierB.loginId,
      location: '대전역',
    );
    final ShipmentTransfer cancelled = await database.cancelHandover(
      actorUserId: courierA.id,
      transferId: cancellation.id,
    );
    expect(cancelled.status, TransferStatus.cancelled);
    expect(
      (await database.shipmentVisibleTo(
        userId: courierA.id,
        shipmentId: cancelledShipment.id,
      ))!.assigneeUserId,
      courierA.id,
    );
    expect(
      () => database.cancelHandover(
        actorUserId: courierA.id,
        transferId: rejection.id,
      ),
      throwsA(isA<TransferException>()),
    );
  });

  test('권한이 없거나 완료된 운송 건은 인수인계할 수 없다', () async {
    final AppUser courierA = await database.createUser(
      loginId: 'courierA',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser courierB = await database.createUser(
      loginId: 'courierB',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser courierC = await database.createUser(
      loginId: 'courierC',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser quality = await database.createUser(
      loginId: 'quality',
      password: 'demo1234',
      role: UserRole.qualityManager,
    );
    final ShipmentRecord shipment = await createOwned(courierA, 'LOT-RULE');
    await database.requestHandover(
      actorUserId: courierA.id,
      shipmentId: shipment.id,
      toLoginId: courierB.loginId,
      location: '수원',
    );

    expect(
      () => database.requestHandover(
        actorUserId: courierA.id,
        shipmentId: shipment.id,
        toLoginId: courierC.loginId,
        location: '수원',
      ),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => database.requestHandover(
        actorUserId: courierC.id,
        shipmentId: shipment.id,
        toLoginId: courierB.loginId,
        location: '수원',
      ),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => database.requestHandover(
        actorUserId: courierA.id,
        shipmentId: shipment.id,
        toLoginId: courierA.loginId,
        location: '수원',
      ),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => database.requestHandover(
        actorUserId: courierA.id,
        shipmentId: shipment.id,
        toLoginId: 'missing-user',
        location: '수원',
      ),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => database.requestHandover(
        actorUserId: courierA.id,
        shipmentId: shipment.id,
        toLoginId: quality.loginId,
        location: '수원',
      ),
      throwsA(isA<TransferException>()),
    );
    expect(
      () => database.acceptHandover(actorUserId: quality.id, transferId: 1),
      throwsA(isA<TransferException>()),
    );

    final ShipmentRecord other = await createOwned(courierA, 'LOT-DONE');
    await database.close();
    final Database done = await databaseFactoryFfi.openDatabase(databasePath);
    await done.update(
      'shipments',
      <String, Object?>{'status': ShipmentStatus.completed.storageValue},
      where: 'id = ?',
      whereArgs: <Object>[other.id],
    );
    await done.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    expect(
      () => database.requestHandover(
        actorUserId: courierA.id,
        shipmentId: other.id,
        toLoginId: courierB.loginId,
        location: '완료 지점',
      ),
      throwsA(isA<TransferException>()),
    );
  });

  test('버전 2 인수인계 행은 버전 3으로 유지된다', () async {
    await database.close();
    final String legacyPath =
        '${tempDir.path}${Platform.pathSeparator}legacy.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 2,
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
            CREATE TABLE shipment_members (
              shipment_id INTEGER NOT NULL,
              user_id INTEGER NOT NULL,
              role TEXT NOT NULL,
              joined_at TEXT NOT NULL,
              PRIMARY KEY (shipment_id, user_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE shipment_transfers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              shipment_id INTEGER NOT NULL,
              from_user_id INTEGER NOT NULL,
              to_user_id INTEGER NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              resolved_at TEXT
            )
          ''');
        },
      ),
    );
    final int fromId = await legacy.insert('users', <String, Object?>{
      'login_id': 'courierA',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'password_iterations': 1,
      'role': 'transporter',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    final int toId = await legacy.insert('users', <String, Object?>{
      'login_id': 'courierB',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'password_iterations': 1,
      'role': 'transporter',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    final int shipmentId = await legacy.insert('shipments', <String, Object?>{
      'owner_user_id': fromId,
      'assignee_user_id': fromId,
      'participation_code': 'VX-KEEP',
      'vaccine': '인플루엔자 4가',
      'manufacturer': 'Korea Vaccine',
      'lot': 'LOT-OLD',
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
    await legacy.insert('shipment_transfers', <String, Object?>{
      'shipment_id': shipmentId,
      'from_user_id': fromId,
      'to_user_id': toId,
      'status': 'requested',
      'created_at': '2026-02-02T00:00:00.000Z',
    });
    await legacy.close();

    final AppDatabase upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    await upgraded.open();
    final List<ShipmentTransfer> rows = await upgraded
        .handoverHistoryForShipment(shipmentId);
    expect(rows, hasLength(1));
    expect(rows.single.status, TransferStatus.requested);
    expect(rows.single.fromLoginId, 'courierA');
    expect(rows.single.toLoginId, 'courierB');
    expect(
      await upgraded.columnNames('shipment_transfers'),
      containsAll(<String>[
        'requested_at',
        'responded_at',
        'location',
        'scheduled_at',
        'note',
        'rejection_reason',
        'handover_temp_c',
      ]),
    );
    expect(
      (await upgraded.shipmentVisibleTo(
        userId: fromId,
        shipmentId: shipmentId,
      ))!.assigneeUserId,
      fromId,
    );
    await upgraded.close();
  });
}
