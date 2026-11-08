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

    final ShipmentRecord? joined = await database.joinByParticipationCode(
      userId: quality.id,
      code: first.participationCode.toLowerCase(),
    );
    expect(joined?.lot, 'LOT-KR-8812');
    expect(joined?.quantity, 100);
    expect(joined?.targetRange, '2 ~ 8°C');

    await database.joinByParticipationCode(
      userId: medical.id,
      code: ' ${first.participationCode} ',
    );

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
}
