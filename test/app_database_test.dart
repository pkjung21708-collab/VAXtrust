import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/password_hasher.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/user_role.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_');
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

  test('웹이 아니면 시연 초기화가 데이터베이스 파일을 지우지 않는다', () async {
    final File file = File(databasePath);
    expect(await file.exists(), isTrue);
    final int sizeBefore = await file.length();

    await expectLater(
      database.deleteWebDemoDatabase(),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('iOS 저장소'),
        ),
      ),
    );

    expect(await file.exists(), isTrue);
    expect(await file.length(), sizeBefore);
    expect(await database.tableRows('users'), isEmpty);
  });

  test('PBKDF2-HMAC-SHA256 테스트 벡터와 일치한다', () {
    final Uint8List key = PasswordHasher.deriveKey(
      password: utf8.encode('password'),
      salt: utf8.encode('salt'),
      iterations: 1,
    );
    final String hex = key
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(
      hex,
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
  });

  test('스키마에 평문 비밀번호와 측정값 컬럼이 없다', () async {
    final Set<String> users = await database.columnNames('users');
    expect(users, containsAll(<String>['password_hash', 'password_salt']));
    expect(users, isNot(contains('password')));

    final Set<String> shipments = await database.columnNames('shipments');
    expect(
      shipments,
      containsAll(<String>[
        'participation_code',
        'vaccine',
        'lot',
        'quantity',
        'origin',
        'destination',
        'target_range',
        'source',
      ]),
    );
    expect(shipments, isNot(contains('current_temp')));
    expect(shipments, isNot(contains('compliance')));
    expect(shipments, isNot(contains('ready')));

    expect(await database.columnNames('session'), contains('user_id'));
    expect(
      await database.columnNames('shipment_members'),
      containsAll(<String>['shipment_id', 'user_id', 'role']),
    );
  });

  test('계정은 해시로 저장되고 세션을 지워도 남는다', () async {
    const String password = 'demo1234';
    final AppUser created = await database.createUser(
      loginId: 'Courier',
      password: password,
      role: UserRole.transporter,
    );

    final List<Map<String, Object?>> rows = await database.tableRows('users');

    expect(rows, hasLength(1));
    expect(rows.single['password_hash'], isNot(password));
    expect(rows.single['password_salt'], isNot(password));
    expect(rows.single.containsKey('password'), isFalse);

    expect(
      await database.authenticate(loginId: 'courier', password: password),
      isNotNull,
    );
    expect(
      await database.authenticate(loginId: 'courier', password: 'wrong'),
      isNull,
    );

    await database.saveSession(created.id);
    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();

    final AppUser? restored = await database.currentSessionUser();
    expect(restored?.loginId, 'Courier');
    expect(restored?.role, UserRole.transporter);

    await database.clearSession();
    expect(await database.currentSessionUser(), isNull);
    expect(
      await database.authenticate(loginId: 'courier', password: password),
      isNotNull,
    );
  });

  test('같은 아이디는 대소문자를 무시하고 한 번만 저장된다', () async {
    await database.createUser(
      loginId: 'quality',
      password: 'demo1234',
      role: UserRole.qualityManager,
    );

    expect(
      () => database.createUser(
        loginId: 'Quality',
        password: 'other-pass',
        role: UserRole.medicalStaff,
      ),
      throwsA(isA<DuplicateLoginIdException>()),
    );
  });

  test('운송 건은 참여 코드로 연결되고 시뮬레이션 데이터는 들어가지 않는다', () async {
    final AppUser transporter = await database.createUser(
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

    final ShipmentRecord first = await database.createShipment(
      ownerUserId: transporter.id,
      draft: const NewShipment(
        vaccine: '인플루엔자 4가',
        manufacturer: 'Korea Vaccine',
        lot: 'LOT-KR-8812',
        expiryDate: '2027-11-03',
        quantity: 100,
        origin: 'Incheon Vaccine Center',
        destination: 'Seoul National University Hospital',
        targetRange: '2 ~ 8°C',
      ),
    );
    final ShipmentRecord second = await database.createShipment(
      ownerUserId: transporter.id,
      draft: const NewShipment(
        vaccine: 'MMR',
        manufacturer: 'Korea Vaccine',
        lot: 'LOT-KR-1001',
        expiryDate: '2028-01-01',
        quantity: 20,
        origin: '오산허브',
        destination: '분당서울대병원',
        targetRange: '2 ~ 8°C',
      ),
    );

    expect(first.source, ShipmentRecord.userInputSource);
    expect(first.participationCode, startsWith('VX-'));
    expect(second.participationCode, isNot(first.participationCode));
    expect(await database.findByParticipationCode('vt-24031'), isNull);
    expect(await database.shipmentsOwnedBy(transporter.id), hasLength(2));

    expect(first.status, ShipmentStatus.registered);
    expect(first.tempMin, 2);
    expect(first.tempMax, 8);
    expect(first.ownerUserId, transporter.id);
    expect(first.assigneeUserId, transporter.id);
    expect(first.displayId, isNot(first.participationCode));
    expect(first.displayId, startsWith('VT-'));
    expect(first.id.toString(), isNot(first.participationCode));
    expect(await database.tableRows('shipment_transfers'), isEmpty);

    final ShipmentJoinResult? joined = await database.joinByParticipationCode(
      userId: quality.id,
      code: first.participationCode.toLowerCase(),
    );
    expect(joined?.alreadyJoined, isFalse);
    expect(joined?.shipment.lot, 'LOT-KR-8812');
    expect(joined?.shipment.quantity, 100);
    expect(joined?.shipment.targetRange, '2 ~ 8°C');
    expect(joined?.shipment.status, ShipmentStatus.registered);

    final ShipmentJoinResult? medicalJoin = await database
        .joinByParticipationCode(
          userId: medical.id,
          code: ' ${first.participationCode} ',
        );
    expect(medicalJoin?.alreadyJoined, isFalse);
    final ShipmentJoinResult? medicalAgain = await database
        .joinByParticipationCode(
          userId: medical.id,
          code: first.participationCode,
        );
    expect(medicalAgain?.alreadyJoined, isTrue);
    final List<Map<String, Object?>> members = await database.tableRows(
      'shipment_members',
    );
    expect(
      members.where((Map<String, Object?> row) => row['user_id'] == medical.id),
      hasLength(1),
    );
    final AppUser? qualityUser = await database.authenticate(
      loginId: 'quality',
      password: 'demo1234',
    );
    expect(qualityUser?.role, UserRole.qualityManager);

    final List<ShipmentRecord> qualityView = await database.shipmentsJoinedBy(
      quality.id,
    );
    final List<ShipmentRecord> medicalView = await database.shipmentsJoinedBy(
      medical.id,
    );
    expect(qualityView.single.id, first.id);
    expect(medicalView.single.vaccine, first.vaccine);
    expect(medicalView.single.origin, first.origin);
    expect(medicalView.single.destination, first.destination);

    expect(
      () => database.joinByParticipationCode(
        userId: transporter.id,
        code: first.participationCode,
      ),
      throwsArgumentError,
    );
    expect(
      () => database.createShipment(
        ownerUserId: quality.id,
        draft: const NewShipment(
          vaccine: 'MMR',
          manufacturer: 'Korea Vaccine',
          lot: 'LOT-X',
          expiryDate: '2027-01-01',
          quantity: 1,
          origin: '출발',
          destination: '도착',
          targetRange: '2 ~ 8°C',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      await database.joinByParticipationCode(userId: medical.id, code: '없음'),
      isNull,
    );
  });

  test('없는 사용자 세션은 외래 키 때문에 저장되지 않는다', () async {
    expect(() => database.saveSession(999), throwsA(isA<DatabaseException>()));
  });

  test('시연 계정은 없을 때만 추가되고 세션을 지워도 남는다', () async {
    await database.ensureDemoAccounts();
    final AppUser? courier = await database.authenticate(
      loginId: 'courier',
      password: 'demo1234',
    );
    expect(courier?.role, UserRole.transporter);

    await database.saveSession(courier!.id);
    await database.clearSession();
    expect(await database.currentSessionUser(), isNull);

    final List<Map<String, Object?>> rows = await database.tableRows('users');
    expect(
      rows.map((Map<String, Object?> row) => row['login_id']).toSet(),
      <Object>{'courier', 'quality', 'medical'},
    );

    await database.ensureDemoAccounts();
    expect(await database.tableRows('users'), hasLength(3));
  });

  test('이미 있는 시연 아이디는 비밀번호와 역할을 바꾸지 않는다', () async {
    await database.createUser(
      loginId: 'courier',
      password: 'custom-pass',
      role: UserRole.medicalStaff,
    );
    await database.ensureDemoAccounts();

    final AppUser? kept = await database.authenticate(
      loginId: 'courier',
      password: 'custom-pass',
    );
    expect(kept?.role, UserRole.medicalStaff);
    expect(
      await database.authenticate(loginId: 'courier', password: 'demo1234'),
      isNull,
    );
    expect(await database.tableRows('users'), hasLength(3));
  });

  test('운송 상태, 온도 범위, 담당 운송자, 인수인계 테이블이 있다', () async {
    final Set<String> shipments = await database.columnNames('shipments');
    expect(
      shipments,
      containsAll(<String>[
        'status',
        'temp_min',
        'temp_max',
        'assignee_user_id',
      ]),
    );
    expect(shipments, isNot(contains('current_temp')));
    expect(
      await database.columnNames('shipment_transfers'),
      containsAll(<String>[
        'shipment_id',
        'from_user_id',
        'to_user_id',
        'status',
      ]),
    );
  });

  test('참여 코드는 서로 다르고 운송 건 ID와 겹치지 않는다', () async {
    final AppUser transporter = await database.createUser(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final Set<String> codes = <String>{};
    for (var index = 0; index < 8; index++) {
      final ShipmentRecord record = await database.createShipment(
        ownerUserId: transporter.id,
        draft: NewShipment(
          vaccine: 'MMR',
          manufacturer: 'Korea Vaccine',
          lot: 'LOT-$index',
          expiryDate: '2028-01-01',
          quantity: index + 1,
          origin: '오산허브',
          destination: '분당서울대병원',
          targetRange: '2 ~ 8°C',
        ),
      );
      expect(codes.add(record.participationCode), isTrue);
      expect(record.participationCode, isNot(record.displayId));
      expect(record.participationCode, isNot('${record.id}'));
      expect(record.status, ShipmentStatus.registered);
    }
  });

  test('같은 내용의 운송 건은 다시 등록되지 않는다', () async {
    final AppUser transporter = await database.createUser(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    const NewShipment draft = NewShipment(
      vaccine: '인플루엔자 4가',
      manufacturer: 'Korea Vaccine',
      lot: 'LOT-KR-8812',
      expiryDate: '2027-11-03',
      quantity: 100,
      origin: 'Incheon Vaccine Center',
      destination: 'Seoul National University Hospital',
      targetRange: '2 ~ 8°C',
    );
    await database.createShipment(ownerUserId: transporter.id, draft: draft);
    expect(
      () => database.createShipment(ownerUserId: transporter.id, draft: draft),
      throwsA(isA<DuplicateShipmentException>()),
    );
    expect(await database.shipmentsOwnedBy(transporter.id), hasLength(1));
  });

  test('재실행과 로그아웃 후에도 남고 다른 계정에는 보이지 않는다', () async {
    final AppUser transporter = await database.createUser(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser other = await database.createUser(
      loginId: 'courier2',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    final AppUser quality = await database.createUser(
      loginId: 'quality',
      password: 'demo1234',
      role: UserRole.qualityManager,
    );
    final ShipmentRecord shipment = await database.createShipment(
      ownerUserId: transporter.id,
      draft: const NewShipment(
        vaccine: '인플루엔자 4가',
        manufacturer: 'Korea Vaccine',
        lot: 'LOT-KEEP',
        expiryDate: '2027-11-03',
        quantity: 40,
        origin: '인천',
        destination: '서울',
        targetRange: '2 ~ 8°C',
      ),
    );
    expect(
      await database.shipmentVisibleTo(
        userId: quality.id,
        shipmentId: shipment.id,
      ),
      isNull,
    );
    await database.joinByParticipationCode(
      userId: quality.id,
      code: shipment.participationCode,
    );

    expect(await database.shipmentsOwnedBy(other.id), isEmpty);
    expect(await database.shipmentsJoinedBy(other.id), isEmpty);
    expect(
      await database.shipmentVisibleTo(
        userId: other.id,
        shipmentId: shipment.id,
      ),
      isNull,
    );
    expect(
      (await database.shipmentVisibleTo(
        userId: quality.id,
        shipmentId: shipment.id,
      ))?.id,
      shipment.id,
    );

    await database.saveSession(transporter.id);
    await database.clearSession();
    expect(await database.currentSessionUser(), isNull);
    expect(
      (await database.shipmentsOwnedBy(transporter.id)).single.lot,
      'LOT-KEEP',
    );
    expect(
      (await database.shipmentsJoinedBy(quality.id)).single.id,
      shipment.id,
    );

    final int id = shipment.id;
    final String code = shipment.participationCode;
    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();

    final List<ShipmentRecord> restored = await database.shipmentsOwnedBy(
      transporter.id,
    );
    expect(restored.single.id, id);
    expect(restored.single.participationCode, code);
    expect(restored.single.status, ShipmentStatus.registered);
    expect(restored.single.tempMin, 2);
    expect(restored.single.tempMax, 8);
    expect((await database.shipmentsJoinedBy(quality.id)).single.id, id);
    expect(await database.currentSessionUser(), isNull);
  });

  test('버전 1 데이터베이스의 계정과 운송 건을 유지한 채 올린다', () async {
    final String legacyPath =
        '${tempDir.path}${Platform.pathSeparator}legacy.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              login_id TEXT NOT NULL COLLATE NOCASE UNIQUE,
              password_hash TEXT NOT NULL,
              password_salt TEXT NOT NULL,
              password_iterations INTEGER NOT NULL,
              role TEXT NOT NULL CHECK (
                role IN ('transporter', 'qualityManager', 'medicalStaff')
              ),
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE session (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              user_id INTEGER NOT NULL REFERENCES users(id),
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE shipments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              owner_user_id INTEGER NOT NULL REFERENCES users(id),
              participation_code TEXT NOT NULL UNIQUE,
              vaccine TEXT NOT NULL,
              manufacturer TEXT NOT NULL,
              lot TEXT NOT NULL,
              expiry_date TEXT NOT NULL,
              quantity INTEGER NOT NULL CHECK (quantity > 0),
              origin TEXT NOT NULL,
              destination TEXT NOT NULL,
              target_range TEXT NOT NULL,
              created_at TEXT NOT NULL,
              source TEXT NOT NULL CHECK (source = 'user_input')
            )
          ''');
          await db.execute('''
            CREATE TABLE shipment_members (
              shipment_id INTEGER NOT NULL REFERENCES shipments(id),
              user_id INTEGER NOT NULL REFERENCES users(id),
              role TEXT NOT NULL CHECK (
                role IN ('transporter', 'qualityManager', 'medicalStaff')
              ),
              joined_at TEXT NOT NULL,
              PRIMARY KEY (shipment_id, user_id)
            )
          ''');
        },
      ),
    );

    const String password = 'demo1234';
    final String salt = PasswordHasher.generateSalt();
    final int userId = await legacy.insert('users', <String, Object?>{
      'login_id': 'courier',
      'password_hash': PasswordHasher.hash(password: password, salt: salt),
      'password_salt': salt,
      'password_iterations': PasswordHasher.defaultIterations,
      'role': 'transporter',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    await legacy.insert('shipments', <String, Object?>{
      'owner_user_id': userId,
      'participation_code': 'VX-LEGACY',
      'vaccine': 'MMR',
      'manufacturer': 'Korea Vaccine',
      'lot': 'LOT-OLD',
      'expiry_date': '2027-05-01',
      'quantity': 12,
      'origin': '인천',
      'destination': '부산',
      'target_range': '2 ~ 8°C',
      'created_at': '2026-02-01T00:00:00.000Z',
      'source': 'user_input',
    });
    await legacy.insert('session', <String, Object?>{
      'id': 1,
      'user_id': userId,
      'created_at': '2026-02-01T00:00:00.000Z',
    });
    await legacy.close();

    final AppDatabase upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: legacyPath,
    );
    await upgraded.open();
    final AppUser? user = await upgraded.authenticate(
      loginId: 'courier',
      password: password,
    );
    expect(user?.id, userId);
    expect(user?.role, UserRole.transporter);

    final List<ShipmentRecord> owned = await upgraded.shipmentsOwnedBy(userId);
    expect(owned, hasLength(1));
    expect(owned.single.participationCode, 'VX-LEGACY');
    expect(owned.single.lot, 'LOT-OLD');
    expect(owned.single.status, ShipmentStatus.registered);
    expect(owned.single.tempMin, 2);
    expect(owned.single.tempMax, 8);
    expect(owned.single.assigneeUserId, userId);
    expect(owned.single.displayId, isNot(owned.single.participationCode));
    expect(await upgraded.tableRows('users'), hasLength(1));
    final AppUser? restoredUser = await upgraded.currentSessionUser();
    expect(restoredUser?.loginId, 'courier');
    expect(
      await upgraded.columnNames('shipment_transfers'),
      contains('to_user_id'),
    );
    await upgraded.close();
  });
}
