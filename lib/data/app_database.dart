import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/shipment_record.dart';
import '../models/user_role.dart';
import 'password_hasher.dart';

/// 같은 아이디로 계정을 다시 만들려고 할 때 발생합니다.
class DuplicateLoginIdException implements Exception {
  const DuplicateLoginIdException(this.loginId);

  final String loginId;

  @override
  String toString() => '이미 사용 중인 아이디입니다: $loginId';
}

/// 이 기기에 남는 SQLite 저장소입니다.
///
/// 계정, 로그인 세션, 사용자가 등록한 운송 건, 참여 코드 연결만 저장합니다.
/// 시뮬레이션 목록과 측정하지 않은 온도·적합도는 넣지 않습니다.
/// 로그아웃은 세션 행만 지우며, 데이터베이스 파일은 지우지 않습니다.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    // 호출부에서는 factory, databasePath라는 이름으로 넘깁니다.
    // ignore: prefer_initializing_formals
    : _factory = factory,
      // ignore: prefer_initializing_formals
      _databasePath = databasePath;

  static final AppDatabase instance = AppDatabase();

  static const int schemaVersion = 1;
  static const String fileName = 'vaxtrust.db';

  static const Set<String> _tables = <String>{
    'users',
    'session',
    'shipments',
    'shipment_members',
  };

  final DatabaseFactory? _factory;
  final String? _databasePath;
  Database? _database;

  Future<void> open() async {
    final Database? current = _database;
    if (current != null && current.isOpen) {
      return;
    }

    final String filePath = _databasePath ?? await _defaultPath();
    _database = await (_factory ?? databaseFactory).openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await _createSchema(db);
        },
      ),
    );
  }

  Future<void> close() async {
    final Database? current = _database;
    _database = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }

  Future<Set<String>> columnNames(String table) async {
    _checkTableName(table);
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      'PRAGMA table_info($table)',
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toSet();
  }

  /// 저장 내용을 확인할 때 사용합니다. 같은 파일을 다시 열면 기존 연결이 닫힙니다.
  Future<List<Map<String, Object?>>> tableRows(String table) async {
    _checkTableName(table);
    return _requireDatabase().query(table);
  }

  Future<AppUser> createUser({
    required String loginId,
    required String password,
    required UserRole role,
  }) async {
    final String normalizedId = loginId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(loginId, 'loginId', '아이디를 입력해야 합니다.');
    }
    if (password.isEmpty) {
      throw ArgumentError('비밀번호를 입력해야 합니다.');
    }

    final String salt = PasswordHasher.generateSalt();
    final String passwordHash = PasswordHasher.hash(
      password: password,
      salt: salt,
    );
    final String createdAt = _timestamp();

    try {
      final int id = await _requireDatabase().insert('users', <String, Object?>{
        'login_id': normalizedId,
        'password_hash': passwordHash,
        'password_salt': salt,
        'password_iterations': PasswordHasher.defaultIterations,
        'role': role.name,
        'created_at': createdAt,
      });
      return AppUser(
        id: id,
        loginId: normalizedId,
        role: role,
        createdAt: DateTime.parse(createdAt),
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw DuplicateLoginIdException(normalizedId);
      }
      rethrow;
    }
  }

  Future<AppUser?> authenticate({
    required String loginId,
    required String password,
  }) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'users',
      where: 'login_id = ?',
      whereArgs: <Object>[loginId.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final Map<String, Object?> row = rows.single;
    final bool matches = PasswordHasher.matches(
      password: password,
      salt: row['password_salt']! as String,
      expectedHash: row['password_hash']! as String,
      iterations: row['password_iterations']! as int,
    );
    if (!matches) {
      return null;
    }
    return _userFromRow(row);
  }

  /// 현재 로그인 세션을 한 행으로 바꿉니다. 계정 데이터는 건드리지 않습니다.
  Future<void> saveSession(int userId) async {
    await _requireDatabase().insert('session', <String, Object?>{
      'id': 1,
      'user_id': userId,
      'created_at': _timestamp(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AppUser?> currentSessionUser() async {
    final Database db = _requireDatabase();
    final List<Map<String, Object?>> rows = await db.query(
      'session',
      where: 'id = ?',
      whereArgs: <Object>[1],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _userById(db, rows.single['user_id']! as int);
  }

  /// 로그인 세션만 지웁니다. 계정과 운송 건 행은 남습니다.
  Future<void> clearSession() async {
    await _requireDatabase().delete('session');
  }

  Future<ShipmentRecord> createShipment({
    required int ownerUserId,
    required NewShipment draft,
  }) async {
    final Database db = _requireDatabase();
    final AppUser? owner = await _userById(db, ownerUserId);
    if (owner == null) {
      throw ArgumentError('운송 건을 등록할 계정을 찾을 수 없습니다.');
    }
    if (owner.role != UserRole.transporter) {
      throw ArgumentError('운송 건은 운송자 계정만 등록할 수 있습니다.');
    }
    if (draft.quantity <= 0) {
      throw ArgumentError.value(draft.quantity, 'quantity', '수량은 1 이상이어야 합니다.');
    }

    final String vaccine = _requiredText(draft.vaccine, '백신');
    final String manufacturer = _requiredText(draft.manufacturer, '제조사');
    final String lot = _requiredText(draft.lot, 'LOT 번호');
    final String expiryDate = _requiredText(draft.expiryDate, '유효기간');
    final String origin = _requiredText(draft.origin, '출발지');
    final String destination = _requiredText(draft.destination, '도착지');
    final String targetRange = _requiredText(draft.targetRange, '보관 범위');
    final String createdAt = _timestamp();

    return db.transaction((Transaction txn) async {
      final String participationCode = await _allocateCode(txn);
      final int id = await txn.insert('shipments', <String, Object?>{
        'owner_user_id': ownerUserId,
        'participation_code': participationCode,
        'vaccine': vaccine,
        'manufacturer': manufacturer,
        'lot': lot,
        'expiry_date': expiryDate,
        'quantity': draft.quantity,
        'origin': origin,
        'destination': destination,
        'target_range': targetRange,
        'created_at': createdAt,
        'source': ShipmentRecord.userInputSource,
      });
      await txn.insert('shipment_members', <String, Object?>{
        'shipment_id': id,
        'user_id': ownerUserId,
        'role': owner.role.name,
        'joined_at': createdAt,
      });
      return ShipmentRecord(
        id: id,
        ownerUserId: ownerUserId,
        participationCode: participationCode,
        vaccine: vaccine,
        manufacturer: manufacturer,
        lot: lot,
        expiryDate: expiryDate,
        quantity: draft.quantity,
        origin: origin,
        destination: destination,
        targetRange: targetRange,
        createdAt: DateTime.parse(createdAt),
        source: ShipmentRecord.userInputSource,
      );
    });
  }

  Future<ShipmentRecord?> findByParticipationCode(String code) async {
    final String normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      return null;
    }
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'shipments',
      where: 'participation_code = ?',
      whereArgs: <Object>[normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _shipmentFromRow(rows.single);
  }

  /// 품질관리자 또는 의료진 계정을 참여 코드로 운송 건에 연결합니다.
  /// 코드가 없으면 null을 반환하고, 이미 연결된 계정이면 같은 운송 건을 반환합니다.
  Future<ShipmentRecord?> joinByParticipationCode({
    required int userId,
    required String code,
  }) async {
    final Database db = _requireDatabase();
    final AppUser? user = await _userById(db, userId);
    if (user == null) {
      throw ArgumentError('참여할 계정을 찾을 수 없습니다.');
    }
    if (user.role == UserRole.transporter) {
      throw ArgumentError('참여 코드 연결은 품질관리자와 의료진 계정에서 할 수 있습니다.');
    }

    final ShipmentRecord? shipment = await findByParticipationCode(code);
    if (shipment == null) {
      return null;
    }

    await db.insert('shipment_members', <String, Object?>{
      'shipment_id': shipment.id,
      'user_id': userId,
      'role': user.role.name,
      'joined_at': _timestamp(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return shipment;
  }

  Future<List<ShipmentRecord>> shipmentsOwnedBy(int userId) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'shipments',
      where: 'owner_user_id = ?',
      whereArgs: <Object>[userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_shipmentFromRow).toList();
  }

  Future<List<ShipmentRecord>> shipmentsJoinedBy(int userId) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT shipments.*
      FROM shipments
      INNER JOIN shipment_members
        ON shipment_members.shipment_id = shipments.id
      WHERE shipment_members.user_id = ?
      ORDER BY shipments.created_at DESC
      ''',
      <Object>[userId],
    );
    return rows.map(_shipmentFromRow).toList();
  }

  Future<String> _defaultPath() async {
    final String directory = await getDatabasesPath();
    return p.join(directory, fileName);
  }

  Database _requireDatabase() {
    final Database? current = _database;
    if (current == null || !current.isOpen) {
      throw StateError('데이터베이스가 열려 있지 않습니다.');
    }
    return current;
  }

  void _checkTableName(String table) {
    if (!_tables.contains(table)) {
      throw ArgumentError.value(table, 'table', '알 수 없는 테이블입니다.');
    }
  }

  Future<void> _createSchema(Database db) async {
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
    await db.execute(
      'CREATE INDEX idx_shipments_owner ON shipments(owner_user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_shipment_members_user ON shipment_members(user_id)',
    );
  }

  Future<String> _allocateCode(DatabaseExecutor db) async {
    const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final Random random = Random.secure();

    for (var attempt = 0; attempt < 8; attempt++) {
      final StringBuffer body = StringBuffer();
      for (var index = 0; index < 6; index++) {
        body.write(alphabet[random.nextInt(alphabet.length)]);
      }
      final String code = 'VX-$body';
      final List<Map<String, Object?>> existing = await db.query(
        'shipments',
        columns: <String>['id'],
        where: 'participation_code = ?',
        whereArgs: <Object>[code],
        limit: 1,
      );
      if (existing.isEmpty) {
        return code;
      }
    }
    throw StateError('참여 코드를 만들지 못했습니다.');
  }

  Future<AppUser?> _userById(DatabaseExecutor db, int id) async {
    final List<Map<String, Object?>> rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _userFromRow(rows.single);
  }

  AppUser _userFromRow(Map<String, Object?> row) {
    return AppUser(
      id: row['id']! as int,
      loginId: row['login_id']! as String,
      role: UserRole.fromStorage(row['role']! as String),
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }

  ShipmentRecord _shipmentFromRow(Map<String, Object?> row) {
    return ShipmentRecord(
      id: row['id']! as int,
      ownerUserId: row['owner_user_id']! as int,
      participationCode: row['participation_code']! as String,
      vaccine: row['vaccine']! as String,
      manufacturer: row['manufacturer']! as String,
      lot: row['lot']! as String,
      expiryDate: row['expiry_date']! as String,
      quantity: row['quantity']! as int,
      origin: row['origin']! as String,
      destination: row['destination']! as String,
      targetRange: row['target_range']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      source: row['source']! as String,
    );
  }

  String _requiredText(String value, String label) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('$label 값을 입력해야 합니다.');
    }
    return trimmed;
  }

  String _timestamp() => DateTime.now().toUtc().toIso8601String();
}
