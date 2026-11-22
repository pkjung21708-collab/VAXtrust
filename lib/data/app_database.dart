import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/demo_scenario.dart';
import '../models/excursion_action.dart';
import '../models/quality_review.dart';
import '../models/shipment_receipt.dart';
import '../models/shipment_record.dart';
import '../models/shipment_release.dart';
import '../models/shipment_transfer.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import '../models/user_role.dart';
import '../models/vaccine_product.dart';
import 'auto_demo_policy.dart';
import 'demo_scenario_policy.dart';
import 'password_hasher.dart';
import 'temperature_policy.dart';
import 'vaccine_catalog.dart';

/// 같은 아이디로 계정을 다시 만들려고 할 때 발생합니다.
class DuplicateLoginIdException implements Exception {
  const DuplicateLoginIdException(this.loginId);

  final String loginId;

  @override
  String toString() => '이미 사용 중인 아이디입니다: $loginId';
}

/// 같은 운송자가 같은 내용의 운송 건을 다시 등록할 때 발생합니다.
class DuplicateShipmentException implements Exception {
  const DuplicateShipmentException();

  String get message => '같은 내용의 운송 건이 이미 등록되어 있습니다.';

  @override
  String toString() => message;
}

/// 품질 검토 권한이나 참여 범위를 지키지 못할 때 발생합니다.
class QualityReviewException implements Exception {
  const QualityReviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExcursionException implements Exception {
  const ExcursionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 출고 확인이나 의료기관 인수 규칙을 지키지 못할 때 발생합니다.
class CustodyException implements Exception {
  const CustodyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 운송 시작·완료 규칙을 지키지 못할 때 발생합니다. 상태는 그대로입니다.
class TransportException implements Exception {
  const TransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 인수인계 규칙을 지키지 못할 때 발생합니다. 담당자는 그대로입니다.
class TransferException implements Exception {
  const TransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 참여 코드로 운송 건에 연결한 결과입니다.
class ShipmentJoinResult {
  const ShipmentJoinResult({
    required this.shipment,
    required this.alreadyJoined,
  });

  final ShipmentRecord shipment;

  /// 이미 연결된 계정입니다. 참여 행을 다시 만들지 않습니다.
  final bool alreadyJoined;
}

/// 이 기기에 남는 SQLite 저장소입니다.
///
/// 계정, 로그인 세션, 운송 건, 참여 연결, 인수인계, 시연용 온도 기록을 저장합니다.
/// 시뮬레이션 목록과 품질 판정은 넣지 않습니다.
/// 로그아웃은 세션 행만 지우며, 데이터베이스 파일과 온도 기록은 지우지 않습니다.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    // 호출부에서는 factory, databasePath라는 이름으로 넘깁니다.
    // ignore: prefer_initializing_formals
    : _factory = factory,
      // ignore: prefer_initializing_formals
      _databasePath = databasePath;

  /// 앱 전역 저장소입니다. 테스트에서는 임시 파일 인스턴스로 바꿀 수 있습니다.
  static AppDatabase instance = AppDatabase();

  static const int schemaVersion = 11;
  static const String fileName = 'vaxtrust.db';
  static const String _transferSelect = '''
    SELECT
      shipment_transfers.id,
      shipment_transfers.shipment_id,
      shipment_transfers.from_user_id,
      shipment_transfers.to_user_id,
      shipment_transfers.status,
      shipment_transfers.requested_at,
      shipment_transfers.responded_at,
      shipment_transfers.location,
      shipment_transfers.scheduled_at,
      shipment_transfers.note,
      shipment_transfers.rejection_reason,
      shipment_transfers.handover_temp_c,
      from_user.login_id AS from_login_id,
      to_user.login_id AS to_login_id,
      shipments.vaccine AS vaccine,
      shipments.lot AS lot,
      shipments.status AS shipment_status
    FROM shipment_transfers
    INNER JOIN users AS from_user
      ON from_user.id = shipment_transfers.from_user_id
    INNER JOIN users AS to_user
      ON to_user.id = shipment_transfers.to_user_id
    INNER JOIN shipments
      ON shipments.id = shipment_transfers.shipment_id
  ''';
  static const String _reviewSelect = '''
    SELECT
      quality_reviews.id,
      quality_reviews.shipment_id,
      quality_reviews.reviewer_user_id,
      quality_reviews.review_status,
      quality_reviews.review_comment,
      quality_reviews.created_at,
      quality_reviews.updated_at,
      users.login_id AS reviewer_login_id
    FROM quality_reviews
    INNER JOIN users
      ON users.id = quality_reviews.reviewer_user_id
  ''';
  static const String _releaseSelect = '''
    SELECT
      shipment_releases.id,
      shipment_releases.shipment_id,
      shipment_releases.confirmed_by_user_id,
      shipment_releases.confirmed_at,
      shipment_releases.note,
      users.login_id AS confirmed_by_login_id
    FROM shipment_releases
    INNER JOIN users
      ON users.id = shipment_releases.confirmed_by_user_id
  ''';
  static const String _receiptSelect = '''
    SELECT
      shipment_receipts.id,
      shipment_receipts.shipment_id,
      shipment_receipts.receiver_user_id,
      shipment_receipts.received_quantity,
      shipment_receipts.package_condition,
      shipment_receipts.receipt_note,
      shipment_receipts.received_at,
      users.login_id AS receiver_login_id
    FROM shipment_receipts
    INNER JOIN users
      ON users.id = shipment_receipts.receiver_user_id
  ''';
  static const String _actionSelect = '''
    SELECT
      excursion_actions.id,
      excursion_actions.shipment_id,
      excursion_actions.excursion_id,
      excursion_actions.author_user_id,
      excursion_actions.cause_category,
      excursion_actions.cause_certainty,
      excursion_actions.description,
      excursion_actions.discovered_at,
      excursion_actions.response_started_at,
      excursion_actions.action_taken,
      excursion_actions.reported_to,
      excursion_actions.reported_at,
      excursion_actions.note,
      excursion_actions.created_at,
      excursion_actions.situation_type,
      excursion_actions.responsible_contacted,
      excursion_actions.hold_guidance_given,
      excursion_actions.hold_action_completed,
      users.login_id AS author_login_id
    FROM excursion_actions
    INNER JOIN users
      ON users.id = excursion_actions.author_user_id
  ''';

  static const Set<String> _tables = <String>{
    'users',
    'session',
    'shipments',
    'shipment_members',
    'shipment_transfers',
    'temperature_readings',
    'temperature_excursions',
    'excursion_actions',
    'demo_temperature_scenarios',
    'quality_reviews',
    'shipment_releases',
    'shipment_receipts',
    'vaccine_products',
    'vaccine_storage_profiles',
  };

  final DatabaseFactory? _factory;
  final String? _databasePath;
  Database? _database;
  List<VaccineProduct> _cachedProducts = const <VaccineProduct>[];
  final Map<int, List<VaccineStorageProfile>> _cachedProfiles =
      <int, List<VaccineStorageProfile>>{};

  List<VaccineProduct> get loadedVaccineProducts => _cachedProducts;

  List<VaccineStorageProfile> loadedProfilesFor(int productId) {
    return _cachedProfiles[productId] ?? const <VaccineStorageProfile>[];
  }

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
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await _upgradeToV2(db);
          }
          if (oldVersion < 3) {
            await _upgradeToV3(db);
          }
          if (oldVersion < 4) {
            await _upgradeToV4(db);
          }
          if (oldVersion < 5) {
            await _upgradeToV5(db);
          }
          if (oldVersion < 6) {
            await _upgradeToV6(db);
          }
          if (oldVersion < 7) {
            await _upgradeToV7(db);
          }
          if (oldVersion < 8) {
            await _upgradeToV8(db);
          }
          if (oldVersion < 9) {
            await _upgradeToV9(db);
          }
          if (oldVersion < 10) {
            await _upgradeToV10(db);
          }
          if (oldVersion < 11) {
            await _upgradeToV11(db);
          }
        },
      ),
    );
    await _ensureVaccineCatalog(_database!);
  }

  Future<void> close() async {
    final Database? current = _database;
    _database = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }

  /// 웹 브라우저의 시연 데이터베이스만 지웁니다.
  /// iOS 파일은 이 메서드로 닫거나 삭제하지 않습니다.
  Future<void> deleteWebDemoDatabase() async {
    if (!kIsWeb) {
      throw StateError('iOS 저장소는 웹 시연 초기화로 지우지 않습니다.');
    }
    final String filePath = _databasePath ?? await _defaultPath();
    await close();
    await (_factory ?? databaseFactory).deleteDatabase(filePath);
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

  /// 시연용 계정이 없으면 추가합니다.
  /// 이미 있는 아이디의 비밀번호와 역할은 바꾸지 않습니다.
  Future<void> ensureDemoAccounts() async {
    await _ensureDemoAccount(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
    await _ensureDemoAccount(
      loginId: 'quality',
      password: 'demo1234',
      role: UserRole.qualityManager,
    );
    await _ensureDemoAccount(
      loginId: 'medical',
      password: 'demo1234',
      role: UserRole.medicalStaff,
    );
  }

  Future<ShipmentRecord> createShipment({
    required int ownerUserId,
    required NewShipment draft,
    bool releaseRequired = false,
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
    final TemperatureBounds? bounds = _boundsFromDraft(draft, targetRange);
    if (bounds == null) {
      throw ArgumentError('설정 온도 하한과 상한을 확인해 주세요.');
    }
    final String createdAt = _timestamp();

    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> duplicates = await txn.query(
        'shipments',
        columns: <String>['id'],
        where: '''
          owner_user_id = ?
          AND vaccine = ? COLLATE NOCASE
          AND manufacturer = ? COLLATE NOCASE
          AND lot = ? COLLATE NOCASE
          AND expiry_date = ? COLLATE NOCASE
          AND quantity = ?
          AND origin = ? COLLATE NOCASE
          AND destination = ? COLLATE NOCASE
        ''',
        whereArgs: <Object>[
          ownerUserId,
          vaccine,
          manufacturer,
          lot,
          expiryDate,
          draft.quantity,
          origin,
          destination,
        ],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw const DuplicateShipmentException();
      }

      final String participationCode = await _allocateCode(txn);
      final int id = await txn.insert('shipments', <String, Object?>{
        'owner_user_id': ownerUserId,
        'assignee_user_id': ownerUserId,
        'participation_code': participationCode,
        'vaccine': vaccine,
        'manufacturer': manufacturer,
        'lot': lot,
        'expiry_date': expiryDate,
        'quantity': draft.quantity,
        'origin': origin,
        'destination': destination,
        'target_range': targetRange,
        'temp_min': bounds.min,
        'temp_max': bounds.max,
        'status': ShipmentStatus.registered.storageValue,
        'created_at': createdAt,
        'source': ShipmentRecord.userInputSource,
        'release_required': releaseRequired ? 1 : 0,
        ...?await _storageColumns(txn, draft, bounds),
      });
      final String displayId = ShipmentRecord.displayIdFor(id);
      if (participationCode == displayId || participationCode == '$id') {
        throw StateError('운송 건 ID와 참여 코드가 같습니다.');
      }
      await txn.insert('shipment_members', <String, Object?>{
        'shipment_id': id,
        'user_id': ownerUserId,
        'role': owner.role.name,
        'joined_at': createdAt,
      });
      final List<Map<String, Object?>> stored = await txn.query(
        'shipments',
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      return _shipmentFromRow(stored.single);
    });
  }

  /// 목록에 있는 백신만 스냅샷으로 붙입니다. 권장 범위는 목록에서 복사합니다.
  /// 적용 범위는 호출자가 넘긴 온도이며, 기존 운송 건 행은 수정하지 않습니다.
  Future<Map<String, Object?>?> _storageColumns(
    DatabaseExecutor db,
    NewShipment draft,
    TemperatureBounds bounds,
  ) async {
    final int? productId = draft.vaccineProductId;
    final int? profileId = draft.storageProfileId;
    if (productId == null && profileId == null) {
      return null;
    }
    if (productId == null || profileId == null) {
      throw ArgumentError('백신과 보관 단계를 함께 선택해 주세요.');
    }
    final List<Map<String, Object?>> products = await db.query(
      'vaccine_products',
      where: 'id = ?',
      whereArgs: <Object>[productId],
      limit: 1,
    );
    if (products.isEmpty) {
      throw ArgumentError('등록된 백신을 찾을 수 없습니다.');
    }
    final VaccineProduct product = _productFromRow(products.single);
    if (!product.isActive) {
      throw ArgumentError('사용 중지된 백신은 선택할 수 없습니다.');
    }
    final List<Map<String, Object?>> profiles = await db.query(
      'vaccine_storage_profiles',
      where: 'id = ? AND vaccine_product_id = ?',
      whereArgs: <Object>[profileId, productId],
      limit: 1,
    );
    if (profiles.isEmpty) {
      throw ArgumentError('선택한 백신의 보관 단계가 아닙니다.');
    }
    final VaccineStorageProfile profile = _profileFromRow(profiles.single);
    return <String, Object?>{
      'vaccine_product_id': product.id,
      'vaccine_storage_profile_id': profile.id,
      'selected_product_name': product.productName,
      'selected_manufacturer': product.manufacturer,
      'selected_storage_stage': profile.profileName,
      'recommended_min_temperature': profile.minTemperature,
      'recommended_max_temperature': profile.maxTemperature,
      'actual_min_temperature': bounds.min,
      'actual_max_temperature': bounds.max,
      'storage_profile_reference': profile.sourceReference,
      'handling_notes_snapshot': profile.handlingNotes,
      'time_limit_notes_snapshot': profile.timeLimitNotes,
    };
  }

  /// 신규 운송 등록에 쓸 수 있는 백신입니다. 비활성 제품은 포함하지 않습니다.
  Future<List<VaccineProduct>> vaccineProducts() async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'vaccine_products',
      where: 'is_active = 1',
      orderBy: 'id ASC',
    );
    return rows.map(_productFromRow).toList();
  }

  /// 활성·비활성 제품을 모두 읽습니다. 과거 운송 기록 확인용이며 행을 지우지 않습니다.
  Future<List<VaccineProduct>> allVaccineProducts() async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'vaccine_products',
      orderBy: 'id ASC',
    );
    return rows.map(_productFromRow).toList();
  }

  Future<List<VaccineStorageProfile>> storageProfilesFor(int productId) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'vaccine_storage_profiles',
      where: 'vaccine_product_id = ?',
      whereArgs: <Object>[productId],
      orderBy: 'id ASC',
    );
    return rows.map(_profileFromRow).toList();
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
  /// 코드가 없으면 null을 반환합니다.
  /// 이미 연결된 계정이면 새 참여 행을 만들지 않고 같은 운송 건을 반환합니다.
  /// 계정의 역할은 바꾸지 않습니다.
  Future<ShipmentJoinResult?> joinByParticipationCode({
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

    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        'shipment_members',
        columns: <String>['user_id'],
        where: 'shipment_id = ? AND user_id = ?',
        whereArgs: <Object>[shipment.id, userId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return ShipmentJoinResult(shipment: shipment, alreadyJoined: true);
      }
      await txn.insert('shipment_members', <String, Object?>{
        'shipment_id': shipment.id,
        'user_id': userId,
        'role': user.role.name,
        'joined_at': _timestamp(),
      });
      return ShipmentJoinResult(shipment: shipment, alreadyJoined: false);
    });
  }

  /// 등록자, 현재 담당자, 참여 계정, 인수인계 당사자만 운송 건을 봅니다.
  Future<ShipmentRecord?> shipmentVisibleTo({
    required int userId,
    required int shipmentId,
  }) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT shipments.*
      FROM shipments
      WHERE shipments.id = ?
        AND (
          shipments.owner_user_id = ?
          OR shipments.assignee_user_id = ?
          OR EXISTS (
            SELECT 1
            FROM shipment_members
            WHERE shipment_members.shipment_id = shipments.id
              AND shipment_members.user_id = ?
          )
          OR EXISTS (
            SELECT 1
            FROM shipment_transfers
            WHERE shipment_transfers.shipment_id = shipments.id
              AND (
                shipment_transfers.from_user_id = ?
                OR shipment_transfers.to_user_id = ?
              )
          )
        )
      LIMIT 1
      ''',
      <Object>[shipmentId, userId, userId, userId, userId, userId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _shipmentFromRow(rows.single);
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

  Future<AppUser?> userById(int id) => _userById(_requireDatabase(), id);

  /// 가입된 운송자 계정을 아이디로 찾습니다. 빈 검색어는 다른 운송자 전체입니다.
  Future<List<AppUser>> searchTransporters({
    required int excludeUserId,
    String query = '',
  }) async {
    final String trimmed = query.trim();
    final List<Object> args = <Object>[excludeUserId];
    final StringBuffer where = StringBuffer("role = 'transporter' AND id != ?");
    if (trimmed.isNotEmpty) {
      where.write(" AND login_id LIKE ? ESCAPE '\\'");
      args.add('%${_escapeLike(trimmed)}%');
    }
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'users',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'login_id COLLATE NOCASE',
      limit: 30,
    );
    return rows.map(_userFromRow).toList();
  }

  Future<List<ShipmentRecord>> shipmentsInTransit() async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'shipments',
      where: 'status = ?',
      whereArgs: <Object>[ShipmentStatus.inTransit.storageValue],
      orderBy: 'id ASC',
    );
    return rows.map(_shipmentFromRow).toList();
  }

  Future<List<ShipmentRecord>> shipmentsAssignedTo(int userId) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'shipments',
      where: 'assignee_user_id = ?',
      whereArgs: <Object>[userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_shipmentFromRow).toList();
  }

  /// 수락된 인수인계에 참여했지만 지금 담당자가 아닌 운송 건입니다.
  Future<List<ShipmentRecord>> shipmentsPreviouslyAssigned(int userId) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT DISTINCT shipments.*
      FROM shipments
      INNER JOIN shipment_transfers
        ON shipment_transfers.shipment_id = shipments.id
      WHERE shipments.assignee_user_id != ?
        AND shipment_transfers.status = 'accepted'
        AND (
          shipment_transfers.from_user_id = ?
          OR shipment_transfers.to_user_id = ?
        )
      ORDER BY shipments.created_at DESC
      ''',
      <Object>[userId, userId, userId],
    );
    return rows.map(_shipmentFromRow).toList();
  }

  Future<List<ShipmentTransfer>> incomingHandovers(int userId) {
    return _transfers(
      'shipment_transfers.to_user_id = ? AND shipment_transfers.status = ?',
      <Object>[userId, TransferStatus.requested.storageValue],
    );
  }

  Future<List<ShipmentTransfer>> outgoingHandovers(int userId) {
    return _transfers(
      'shipment_transfers.from_user_id = ? AND shipment_transfers.status = ?',
      <Object>[userId, TransferStatus.requested.storageValue],
    );
  }

  Future<List<ShipmentTransfer>> handoverHistoryForUser(int userId) {
    return _transfers(
      'shipment_transfers.from_user_id = ? OR shipment_transfers.to_user_id = ?',
      <Object>[userId, userId],
    );
  }

  Future<List<ShipmentTransfer>> handoverHistoryForShipment(int shipmentId) {
    return _transfers('shipment_transfers.shipment_id = ?', <Object>[
      shipmentId,
    ], newestFirst: false);
  }

  Future<ShipmentTransfer?> pendingHandoverForShipment(int shipmentId) async {
    final List<ShipmentTransfer> rows = await _transfers(
      'shipment_transfers.shipment_id = ? AND shipment_transfers.status = ?',
      <Object>[shipmentId, TransferStatus.requested.storageValue],
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  /// 현재 담당 운송자가 인수 요청을 저장합니다. 담당자 ID는 바꾸지 않습니다.
  Future<ShipmentTransfer> requestHandover({
    required int actorUserId,
    required int shipmentId,
    required String toLoginId,
    required String location,
    DateTime? scheduledAt,
    String? note,
  }) async {
    final String place = _requiredText(location, '인계 장소');
    final String memo = note?.trim() ?? '';
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final AppUser actor = await _requireTransporter(txn, actorUserId);
      final ShipmentRecord shipment = await _requireShipment(txn, shipmentId);
      if (shipment.assigneeUserId != actor.id) {
        throw const TransferException('현재 담당 운송자만 인수인계를 요청할 수 있습니다.');
      }
      if (shipment.status == ShipmentStatus.completed) {
        throw const TransferException('운송 완료된 운송 건은 인수인계할 수 없습니다.');
      }
      final AppUser recipient = await _requireRecipient(
        txn,
        toLoginId: toLoginId,
        actorId: actor.id,
      );
      final List<Map<String, Object?>> open = await txn.query(
        'shipment_transfers',
        columns: <String>['id'],
        where: 'shipment_id = ? AND status = ?',
        whereArgs: <Object>[shipmentId, TransferStatus.requested.storageValue],
        limit: 1,
      );
      if (open.isNotEmpty) {
        throw const TransferException('처리되지 않은 인수인계 요청이 이미 있습니다.');
      }
      final String requestedAt = _timestamp();
      final int id = await txn.insert('shipment_transfers', <String, Object?>{
        'shipment_id': shipmentId,
        'from_user_id': actor.id,
        'to_user_id': recipient.id,
        'status': TransferStatus.requested.storageValue,
        'created_at': requestedAt,
        'requested_at': requestedAt,
        'location': place,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'note': memo.isEmpty ? null : memo,
        'handover_temp_c': null,
      });
      final ShipmentRecord unchanged = await _requireShipment(txn, shipmentId);
      if (unchanged.assigneeUserId != actor.id) {
        throw const TransferException('담당자가 바뀌어 요청을 저장하지 못했습니다.');
      }
      return (await _transferById(txn, id))!;
    });
  }

  /// 인수 수락과 담당자 변경을 한 트랜잭션에서 처리합니다.
  Future<ShipmentTransfer> acceptHandover({
    required int actorUserId,
    required int transferId,
  }) {
    return _respond(
      actorUserId: actorUserId,
      transferId: transferId,
      nextStatus: TransferStatus.accepted,
      asRecipient: true,
    );
  }

  /// 거절해도 담당자는 바뀌지 않고 기록은 남습니다.
  Future<ShipmentTransfer> rejectHandover({
    required int actorUserId,
    required int transferId,
    String? reason,
  }) {
    final String trimmed = reason?.trim() ?? '';
    return _respond(
      actorUserId: actorUserId,
      transferId: transferId,
      nextStatus: TransferStatus.rejected,
      asRecipient: true,
      rejectionReason: trimmed.isEmpty ? null : trimmed,
    );
  }

  /// 등록된 운송 건을 운송 중으로 바꾸고 첫 시연 온도를 현재 시각으로 남깁니다.
  /// 같은 요청을 다시 해도 상태는 한 번만 바뀝니다.
  Future<ShipmentRecord> startTransport({
    required int actorUserId,
    required int shipmentId,
    String? demoMode,
  }) async {
    if (demoMode != null && !DemoMode.isKnown(demoMode)) {
      throw const TransportException('알 수 없는 자동 시연 방식입니다.');
    }
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final ShipmentRecord shipment = await _requireTransportShipment(
        txn,
        actorUserId: actorUserId,
        shipmentId: shipmentId,
        action: '시작',
      );
      if (shipment.status == ShipmentStatus.completed) {
        throw const TransportException('완료된 운송 건은 다시 시작할 수 없습니다.');
      }
      if (shipment.status != ShipmentStatus.registered) {
        throw const TransportException('이미 운송이 시작된 건입니다.');
      }
      if (shipment.releaseRequired) {
        final List<Map<String, Object?>> release = await txn.query(
          'shipment_releases',
          columns: <String>['id'],
          where: 'shipment_id = ?',
          whereArgs: <Object>[shipmentId],
          limit: 1,
        );
        if (release.isEmpty) {
          throw const TransportException('출고 확인 후 운송을 시작할 수 있습니다.');
        }
      }
      final double? min = shipment.tempMin;
      final double? max = shipment.tempMax;
      if (min == null || max == null) {
        throw const TransportException('설정 온도 범위가 없어 운송을 시작할 수 없습니다.');
      }
      final DateTime at = DateTime.now();
      final String startedAt = at.toUtc().toIso8601String();
      final int updated = await txn.update(
        'shipments',
        <String, Object?>{
          'status': ShipmentStatus.inTransit.storageValue,
          'started_at': startedAt,
          'demo_mode': ?demoMode,
        },
        where: 'id = ? AND status = ? AND assignee_user_id = ?',
        whereArgs: <Object>[
          shipmentId,
          ShipmentStatus.registered.storageValue,
          actorUserId,
        ],
      );
      if (updated != 1) {
        throw const TransportException('운송을 시작하지 못했습니다. 다시 확인해 주세요.');
      }
      await _insertTemperature(
        txn,
        shipmentId: shipmentId,
        celsius: demoMode == DemoMode.presentation
            ? PresentationSettings.midpoint(min, max)
            : InRangeTemperaturePolicy().next(
                previous: null,
                min: min,
                max: max,
              ),
        at: at,
        assigneeUserId: actorUserId,
        boundsMin: min,
        boundsMax: max,
      );
      return _requireShipment(txn, shipmentId);
    });
  }

  /// 운송 중 건을 완료하고 온도 기록을 남깁니다. 생성은 상태 변경으로 멈춥니다.
  Future<ShipmentRecord> completeTransport({
    required int actorUserId,
    required int shipmentId,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final ShipmentRecord shipment = await _requireTransportShipment(
        txn,
        actorUserId: actorUserId,
        shipmentId: shipmentId,
        action: '완료',
      );
      if (shipment.status != ShipmentStatus.inTransit) {
        throw const TransportException('운송 중인 건만 완료할 수 있습니다.');
      }
      final List<Map<String, Object?>> open = await txn.query(
        'shipment_transfers',
        columns: <String>['id'],
        where: 'shipment_id = ? AND status = ?',
        whereArgs: <Object>[shipmentId, TransferStatus.requested.storageValue],
        limit: 1,
      );
      if (open.isNotEmpty) {
        throw const TransportException('처리되지 않은 인수인계 요청이 있으면 운송을 완료할 수 없습니다.');
      }
      final int updated = await txn.update(
        'shipments',
        <String, Object?>{
          'status': ShipmentStatus.completed.storageValue,
          'completed_at': _timestamp(),
        },
        where: 'id = ? AND status = ? AND assignee_user_id = ?',
        whereArgs: <Object>[
          shipmentId,
          ShipmentStatus.inTransit.storageValue,
          actorUserId,
        ],
      );
      if (updated != 1) {
        throw const TransportException('운송을 완료하지 못했습니다. 다시 확인해 주세요.');
      }
      await _endActiveScenario(txn, shipmentId, DateTime.now());
      return _requireShipment(txn, shipmentId);
    });
  }

  /// 출고 확인만 저장합니다. 운송 상태는 바꾸지 않습니다.
  Future<ShipmentRelease> confirmRelease({
    required int actorUserId,
    required int shipmentId,
    String? note,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final AppUser? actor = await _userById(txn, actorUserId);
      if (actor == null || actor.role != UserRole.transporter) {
        throw const CustodyException('운송자만 출고를 확인할 수 있습니다.');
      }
      final ShipmentRecord? shipment = await _findShipment(txn, shipmentId);
      if (shipment == null) {
        throw const CustodyException('운송 건을 찾을 수 없습니다.');
      }
      if (shipment.assigneeUserId != actor.id) {
        throw const CustodyException('현재 담당 운송자만 출고를 확인할 수 있습니다.');
      }
      if (shipment.status != ShipmentStatus.registered) {
        throw const CustodyException('등록된 운송 건에서만 출고를 확인할 수 있습니다.');
      }
      final List<Map<String, Object?>> existing = await txn.query(
        'shipment_releases',
        columns: <String>['id'],
        where: 'shipment_id = ?',
        whereArgs: <Object>[shipmentId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw const CustodyException('이미 출고 확인이 저장된 운송 건입니다.');
      }
      final String now = _timestamp();
      final String trimmed = note?.trim() ?? '';
      final int id = await txn.insert('shipment_releases', <String, Object?>{
        'shipment_id': shipmentId,
        'confirmed_by_user_id': actorUserId,
        'confirmed_at': now,
        'note': trimmed.isEmpty ? null : trimmed,
        'created_at': now,
      });
      return (await _releaseById(txn, id))!;
    });
  }

  Future<ShipmentRelease?> releaseFor({
    required int userId,
    required int shipmentId,
  }) async {
    await _requireVisible(userId, shipmentId);
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_releaseSelect
      WHERE shipment_releases.shipment_id = ?
      LIMIT 1
      ''',
      <Object>[shipmentId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _releaseFromRow(rows.single);
  }

  /// 물품 수령만 저장합니다. 운송 상태와 품질 검토는 바꾸지 않습니다.
  Future<ShipmentReceipt> confirmReceipt({
    required int actorUserId,
    required int shipmentId,
    required int receivedQuantity,
    required String packageCondition,
    String? note,
  }) async {
    if (receivedQuantity < 0) {
      throw const CustodyException('도착 수량은 0 이상이어야 합니다.');
    }
    if (!PackageCondition.isKnown(packageCondition)) {
      throw const CustodyException('포장 상태를 선택해 주세요.');
    }
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final AppUser? actor = await _userById(txn, actorUserId);
      if (actor == null || actor.role != UserRole.medicalStaff) {
        throw const CustodyException('의료진만 의료기관 인수를 확인할 수 있습니다.');
      }
      final ShipmentRecord? shipment = await _findShipment(txn, shipmentId);
      if (shipment == null) {
        throw const CustodyException('운송 건을 찾을 수 없습니다.');
      }
      final List<Map<String, Object?>> member = await txn.query(
        'shipment_members',
        columns: <String>['user_id'],
        where: 'shipment_id = ? AND user_id = ? AND role = ?',
        whereArgs: <Object>[
          shipmentId,
          actorUserId,
          UserRole.medicalStaff.name,
        ],
        limit: 1,
      );
      if (member.isEmpty) {
        throw const CustodyException('참여한 운송 건만 인수할 수 있습니다.');
      }
      if (shipment.status != ShipmentStatus.completed) {
        throw const CustodyException('운송이 완료된 건만 인수할 수 있습니다.');
      }
      final List<Map<String, Object?>> existing = await txn.query(
        'shipment_receipts',
        columns: <String>['id'],
        where: 'shipment_id = ?',
        whereArgs: <Object>[shipmentId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw const CustodyException('이미 인수 확인이 저장된 운송 건입니다.');
      }
      final String now = _timestamp();
      final String trimmed = note?.trim() ?? '';
      final int id = await txn.insert('shipment_receipts', <String, Object?>{
        'shipment_id': shipmentId,
        'receiver_user_id': actorUserId,
        'received_quantity': receivedQuantity,
        'package_condition': packageCondition,
        'receipt_note': trimmed.isEmpty ? null : trimmed,
        'received_at': now,
        'created_at': now,
      });
      return (await _receiptById(txn, id))!;
    });
  }

  Future<ShipmentReceipt?> receiptFor({
    required int userId,
    required int shipmentId,
  }) async {
    await _requireVisible(userId, shipmentId);
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_receiptSelect
      WHERE shipment_receipts.shipment_id = ?
      LIMIT 1
      ''',
      <Object>[shipmentId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _receiptFromRow(rows.single);
  }

  /// 운송 중 건에 현재 시각의 시연 온도를 한 점 저장합니다.
  /// 간격이 지나지 않았거나 운송 중이 아니면 저장하지 않습니다.
  /// 마지막 기록과 이번 시각 사이의 빈 시간은 채우지 않습니다.
  Future<TemperatureReading?> recordDemoSample({
    required int shipmentId,
    required DateTime at,
    required InRangeTemperaturePolicy policy,
    Duration? minimumGap,
    DemoScenarioSettings scenarioSettings = const DemoScenarioSettings(),
    AutoDemoSettings autoSettings = const AutoDemoSettings(),
    PresentationSettings presentation = const PresentationSettings(),
    DemoRoll? autoRoll,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final ShipmentRecord? shipment = await _findShipment(txn, shipmentId);
      if (shipment == null || shipment.status != ShipmentStatus.inTransit) {
        return null;
      }
      final double? min = shipment.tempMin;
      final double? max = shipment.tempMax;
      if (min == null || max == null) {
        return null;
      }
      final TemperatureReading? latest = await _latestTemperature(
        txn,
        shipmentId,
      );
      if (minimumGap != null &&
          latest != null &&
          at.toUtc().difference(latest.measuredAt.toUtc()) < minimumGap) {
        return null;
      }
      if (shipment.autoGapSkips > 0) {
        final int remaining = shipment.autoGapSkips - 1;
        final int quiet = _quietSamples(
          shipment,
          autoSettings: autoSettings,
          presentation: presentation,
        );
        await txn.update(
          'shipments',
          <String, Object?>{
            'auto_gap_skips': remaining,
            if (remaining == 0)
              'auto_cooldown_until_count':
                  await _readingCount(txn, shipmentId) + quiet,
            if (remaining == 0)
              'auto_completed_events': shipment.autoCompletedEvents + 1,
          },
          where: 'id = ?',
          whereArgs: <Object>[shipmentId],
        );
        return null;
      }
      DemoScenario? scenario = await _activeScenario(txn, shipmentId);
      late final double celsius;
      ScenarioStep? step;
      if (scenario == null && shipment.demoMode == DemoMode.presentation) {
        final int count = await _readingCount(txn, shipmentId);
        final String? due = presentation.eventDue(
          shipmentId: shipment.id,
          readingCount: count,
          cooldownUntilCount: shipment.autoCooldownUntilCount,
          completedEvents: shipment.autoCompletedEvents,
        );
        if (due == PresentationSettings.dataGap) {
          final int skips = autoSettings.gapSkips;
          final int quiet = _quietSamples(
            shipment,
            autoSettings: autoSettings,
            presentation: presentation,
          );
          await txn.update(
            'shipments',
            <String, Object?>{
              'auto_gap_skips': skips <= 1 ? 0 : skips - 1,
              if (skips <= 1)
                'auto_cooldown_until_count':
                    await _readingCount(txn, shipmentId) + quiet,
              if (skips <= 1)
                'auto_completed_events': shipment.autoCompletedEvents + 1,
            },
            where: 'id = ?',
            whereArgs: <Object>[shipmentId],
          );
          return null;
        }
        if (due != null) {
          final int id = await txn.insert(
            'demo_temperature_scenarios',
            <String, Object?>{
              'shipment_id': shipmentId,
              'scenario_type': due,
              'phase': DemoScenario.rising,
              'started_at': at.toUtc().toIso8601String(),
              'started_by_user_id': shipment.assigneeUserId,
              'hold_samples': 0,
              'trigger_source': DemoScenario.autoTrigger,
            },
          );
          scenario = await _scenarioById(txn, id);
        }
        if (scenario == null) {
          celsius = VariedTemperature.next(
            previous: latest?.celsius,
            min: min,
            max: max,
            sampleIndex: count,
            seed: shipment.id,
          );
        } else {
          step = _advanceScenario(
            scenario: scenario,
            previous: latest?.celsius,
            min: min,
            max: max,
            scenarioSettings: scenarioSettings,
            autoSettings: autoSettings,
          );
          celsius = _autoHoldWobble(
            celsius: step.celsius,
            scenario: scenario,
            step: step,
            min: min,
            max: max,
          );
        }
      } else if (scenario == null &&
          shipment.demoMode == DemoMode.probabilistic) {
        final int count = await _readingCount(txn, shipmentId);
        final AutoDemoStart? start = ProbabilisticAutoDemo.roll(
          roll: autoRoll ?? DemoRoll.random(),
          readingCount: count,
          cooldownUntilCount: shipment.autoCooldownUntilCount,
          scenarioActive: false,
          gapSkipsRemaining: 0,
          settings: autoSettings,
        );
        if (start != null && start.gap) {
          await txn.update(
            'shipments',
            <String, Object?>{'auto_gap_skips': autoSettings.gapSkips - 1},
            where: 'id = ?',
            whereArgs: <Object>[shipmentId],
          );
          return null;
        }
        if (start != null && start.scenarioType != null) {
          final int id = await txn.insert(
            'demo_temperature_scenarios',
            <String, Object?>{
              'shipment_id': shipmentId,
              'scenario_type': start.scenarioType,
              'phase': DemoScenario.rising,
              'started_at': at.toUtc().toIso8601String(),
              'started_by_user_id': shipment.assigneeUserId,
              'hold_samples': 0,
              'trigger_source': DemoScenario.autoTrigger,
            },
          );
          scenario = await _scenarioById(txn, id);
        }
        if (scenario == null) {
          celsius = VariedTemperature.next(
            previous: latest?.celsius,
            min: min,
            max: max,
            sampleIndex: count,
            random: Random(),
          );
        } else {
          step = _advanceScenario(
            scenario: scenario,
            previous: latest?.celsius,
            min: min,
            max: max,
            scenarioSettings: scenarioSettings,
            autoSettings: autoSettings,
          );
          celsius = _autoHoldWobble(
            celsius: step.celsius,
            scenario: scenario,
            step: step,
            min: min,
            max: max,
          );
        }
      } else if (scenario != null) {
        step = _advanceScenario(
          scenario: scenario,
          previous: latest?.celsius,
          min: min,
          max: max,
          scenarioSettings: scenarioSettings,
          autoSettings: autoSettings,
        );
        celsius = _autoHoldWobble(
          celsius: step.celsius,
          scenario: scenario,
          step: step,
          min: min,
          max: max,
        );
      } else {
        celsius = policy.next(previous: latest?.celsius, min: min, max: max);
      }
      final TemperatureReading reading = await _insertTemperature(
        txn,
        shipmentId: shipmentId,
        celsius: celsius,
        at: at,
        assigneeUserId: shipment.assigneeUserId,
        boundsMin: min,
        boundsMax: max,
      );
      if (scenario != null && step != null) {
        await txn.update(
          'demo_temperature_scenarios',
          <String, Object?>{
            'phase': step.phase,
            'hold_samples': step.holdSamples,
            'ended_at': step.ended
                ? reading.measuredAt.toUtc().toIso8601String()
                : null,
          },
          where: 'id = ?',
          whereArgs: <Object>[scenario.id],
        );
        if (scenario.isAuto && step.ended) {
          await txn.update(
            'shipments',
            <String, Object?>{
              'auto_cooldown_until_count':
                  await _readingCount(txn, shipmentId) +
                  _quietSamples(
                    shipment,
                    autoSettings: autoSettings,
                    presentation: presentation,
                  ),
              'auto_completed_events': shipment.autoCompletedEvents + 1,
            },
            where: 'id = ?',
            whereArgs: <Object>[shipmentId],
          );
        }
      }
      return reading;
    });
  }

  int _quietSamples(
    ShipmentRecord shipment, {
    required AutoDemoSettings autoSettings,
    required PresentationSettings presentation,
  }) {
    if (shipment.demoMode == DemoMode.presentation) {
      return presentation.quietSamples;
    }
    return autoSettings.cooldownSamples;
  }

  /// 이탈을 유지하는 동안 같은 숫자에 고정되지 않게 0.1°C만 흔듭니다.
  /// 흔들린 값도 허용 범위 밖에 남습니다.
  double _autoHoldWobble({
    required double celsius,
    required DemoScenario scenario,
    required ScenarioStep step,
    required double min,
    required double max,
  }) {
    if (!scenario.isAuto || step.phase != DemoScenario.holding) {
      return celsius;
    }
    final double wobble = step.holdSamples.isEven ? 0.1 : -0.1;
    var value = ((celsius + wobble) * 10).round() / 10;
    if (scenario.type == DemoScenario.overcool) {
      if (value >= min) {
        value = ((min - 0.1) * 10).round() / 10;
      }
    } else if (value <= max) {
      value = ((max + 0.1) * 10).round() / 10;
    }
    return value;
  }

  ScenarioStep _advanceScenario({
    required DemoScenario scenario,
    required double? previous,
    required double min,
    required double max,
    required DemoScenarioSettings scenarioSettings,
    required AutoDemoSettings autoSettings,
  }) {
    final DemoScenarioSettings settings = scenario.isAuto
        ? DemoScenarioSettings(
            stepCelsius: scenarioSettings.stepCelsius,
            holdSamples: autoSettings.holdSamples,
            breachMargin: scenarioSettings.breachMargin,
          )
        : scenarioSettings;
    return DemoScenarioPolicy.advance(
      type: scenario.type,
      phase: scenario.phase,
      holdSamples: scenario.holdSamples,
      previous: previous,
      min: min,
      max: max,
      settings: settings,
      recoverCooling: scenario.isAuto,
    );
  }

  /// 테스트와 감지 검증에서 지정한 온도를 그대로 저장합니다.
  /// 시나리오 이름은 붙이지 않고, 범위를 벗어난 값만 이탈 이벤트가 됩니다.
  Future<TemperatureReading?> recordMeasuredSample({
    required int shipmentId,
    required DateTime at,
    required double celsius,
    Duration? minimumGap,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final ShipmentRecord? shipment = await _findShipment(txn, shipmentId);
      if (shipment == null || shipment.status != ShipmentStatus.inTransit) {
        return null;
      }
      final double? min = shipment.tempMin;
      final double? max = shipment.tempMax;
      if (min == null || max == null) {
        return null;
      }
      final TemperatureReading? latest = await _latestTemperature(
        txn,
        shipmentId,
      );
      if (minimumGap != null &&
          latest != null &&
          at.toUtc().difference(latest.measuredAt.toUtc()) < minimumGap) {
        return null;
      }
      return _insertTemperature(
        txn,
        shipmentId: shipmentId,
        celsius: celsius,
        at: at,
        assigneeUserId: shipment.assigneeUserId,
        boundsMin: min,
        boundsMax: max,
      );
    });
  }

  Future<TemperatureReading?> latestTemperature(int shipmentId) {
    return _latestTemperature(_requireDatabase(), shipmentId);
  }

  Future<Map<int, TemperatureReading>> latestTemperatures(
    List<int> shipmentIds,
  ) async {
    if (shipmentIds.isEmpty) {
      return <int, TemperatureReading>{};
    }
    final String placeholders = List<String>.filled(
      shipmentIds.length,
      '?',
    ).join(', ');
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT temperature_readings.*
      FROM temperature_readings
      INNER JOIN (
        SELECT shipment_id, MAX(id) AS id
        FROM temperature_readings
        WHERE shipment_id IN ($placeholders)
        GROUP BY shipment_id
      ) latest ON latest.id = temperature_readings.id
      ''',
      shipmentIds,
    );
    return <int, TemperatureReading>{
      for (final Map<String, Object?> row in rows)
        row['shipment_id']! as int: _temperatureFromRow(row),
    };
  }

  /// 최근 [limit]건을 최신 측정이 앞에 오도록 돌려줍니다.
  /// 그래프는 [temperaturesForShipment]의 과거→현재 순서를 유지합니다.
  Future<List<TemperatureReading>> recentTemperatures(
    int shipmentId, {
    int limit = 20,
  }) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'temperature_readings',
      where: 'shipment_id = ?',
      whereArgs: <Object>[shipmentId],
      orderBy: 'measured_at DESC, id DESC',
      limit: limit,
    );
    final Set<int> seen = <int>{};
    return <TemperatureReading>[
      for (final Map<String, Object?> row in rows)
        if (seen.add(row['id']! as int)) _temperatureFromRow(row),
    ];
  }

  /// 그래프용 원본 온도입니다. 값을 줄이거나 바꾸지 않습니다.
  Future<List<TemperatureReading>> temperaturesForShipment(
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'temperature_readings',
      where: 'shipment_id = ?',
      whereArgs: <Object>[shipmentId],
      orderBy: 'measured_at ASC, id ASC',
    );
    return rows.map(_temperatureFromRow).toList();
  }

  Future<List<TemperatureReading>> temperaturesForShipments(
    List<int> shipmentIds,
  ) async {
    if (shipmentIds.isEmpty) {
      return const <TemperatureReading>[];
    }
    final String placeholders = List<String>.filled(
      shipmentIds.length,
      '?',
    ).join(', ');
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT *
      FROM temperature_readings
      WHERE shipment_id IN ($placeholders)
      ORDER BY shipment_id ASC, measured_at ASC, id ASC
      ''',
      shipmentIds,
    );
    return rows.map(_temperatureFromRow).toList();
  }

  Future<Map<int, List<TemperatureExcursion>>> excursionsByShipment(
    List<int> shipmentIds,
  ) async {
    if (shipmentIds.isEmpty) {
      return const <int, List<TemperatureExcursion>>{};
    }
    final String placeholders = List<String>.filled(
      shipmentIds.length,
      '?',
    ).join(', ');
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT *
      FROM temperature_excursions
      WHERE shipment_id IN ($placeholders)
      ORDER BY shipment_id ASC, started_at ASC, id ASC
      ''',
      shipmentIds,
    );
    final Map<int, List<TemperatureExcursion>> grouped =
        <int, List<TemperatureExcursion>>{};
    for (final Map<String, Object?> row in rows) {
      final TemperatureExcursion excursion = _excursionFromRow(row);
      grouped.putIfAbsent(excursion.shipmentId, () => <TemperatureExcursion>[]);
      grouped[excursion.shipmentId]!.add(excursion);
    }
    return grouped;
  }

  Future<int> _readingCount(DatabaseExecutor db, int shipmentId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM temperature_readings
      WHERE shipment_id = ?
      ''',
      <Object>[shipmentId],
    );
    return _asInt(rows.single['count']);
  }

  Future<int> temperatureCount(int shipmentId) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM temperature_readings
      WHERE shipment_id = ?
      ''',
      <Object>[shipmentId],
    );
    final Object? raw = rows.single['count'];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return 0;
  }

  /// 시나리오 선택만 저장합니다. 이탈 이벤트는 온도가 범위를 벗어날 때 생깁니다.
  Future<DemoScenario> startDemoScenario({
    required int actorUserId,
    required int shipmentId,
    required String type,
  }) async {
    if (type != DemoScenario.doorOpen &&
        type != DemoScenario.coolingFault &&
        type != DemoScenario.overcool) {
      throw const ExcursionException('알 수 없는 시연 시나리오입니다.');
    }
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final ShipmentRecord shipment = await _requireAssignee(
        txn,
        actorUserId: actorUserId,
        shipmentId: shipmentId,
        action: '이상 상황 시연을 시작',
      );
      if (shipment.status != ShipmentStatus.inTransit) {
        throw const ExcursionException('운송 중인 운송 건에서만 시연할 수 있습니다.');
      }
      if (shipment.autoGapSkips > 0) {
        throw const ExcursionException('온도 데이터 공백 시연 중에는 다른 시연을 시작하지 않습니다.');
      }
      if (await _activeScenario(txn, shipmentId) != null) {
        throw const ExcursionException('이미 진행 중인 시연 시나리오가 있습니다.');
      }
      final String startedAt = _timestamp();
      final int id = await txn.insert(
        'demo_temperature_scenarios',
        <String, Object?>{
          'shipment_id': shipmentId,
          'scenario_type': type,
          'phase': DemoScenario.rising,
          'started_at': startedAt,
          'started_by_user_id': actorUserId,
          'hold_samples': 0,
          'trigger_source': DemoScenario.manualTrigger,
        },
      );
      return (await _scenarioById(txn, id))!;
    });
  }

  /// 시나리오를 멈추면 바로 끊지 않고 정상 범위로 천천히 돌아옵니다.
  /// 이미 저장된 온도 기록은 지우지 않습니다.
  Future<DemoScenario> endDemoScenario({
    required int actorUserId,
    required int shipmentId,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      await _requireAssignee(
        txn,
        actorUserId: actorUserId,
        shipmentId: shipmentId,
        action: '시연 시나리오를 종료',
      );
      final DemoScenario? scenario = await _activeScenario(txn, shipmentId);
      if (scenario == null) {
        throw const ExcursionException('진행 중인 시연 시나리오가 없습니다.');
      }
      if (scenario.phase == DemoScenario.rising ||
          scenario.phase == DemoScenario.holding) {
        await txn.update(
          'demo_temperature_scenarios',
          <String, Object?>{'phase': DemoScenario.recovering},
          where: 'id = ?',
          whereArgs: <Object>[scenario.id],
        );
      }
      return (await _scenarioById(txn, scenario.id))!;
    });
  }

  Future<DemoScenario?> activeScenarioFor({
    required int userId,
    required int shipmentId,
  }) async {
    await _requireVisible(userId, shipmentId);
    return _activeScenario(_requireDatabase(), shipmentId);
  }

  Future<List<TemperatureExcursion>> excursionsFor({
    required int userId,
    required int shipmentId,
  }) async {
    await _requireVisible(userId, shipmentId);
    final List<Map<String, Object?>> rows = await _requireDatabase().query(
      'temperature_excursions',
      where: 'shipment_id = ?',
      whereArgs: <Object>[shipmentId],
      orderBy: 'started_at ASC, id ASC',
    );
    return rows.map(_excursionFromRow).toList();
  }

  Future<Map<int, ExcursionSummary>> excursionSummaries(
    List<int> shipmentIds,
  ) async {
    if (shipmentIds.isEmpty) {
      return <int, ExcursionSummary>{};
    }
    final String placeholders = List<String>.filled(
      shipmentIds.length,
      '?',
    ).join(', ');
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT shipment_id,
             COUNT(*) AS total,
             SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) AS open_count,
             MAX(data_gap_detected) AS gap_flag
      FROM temperature_excursions
      WHERE shipment_id IN ($placeholders)
      GROUP BY shipment_id
      ''',
      shipmentIds,
    );
    return <int, ExcursionSummary>{
      for (final Map<String, Object?> row in rows)
        row['shipment_id']! as int: ExcursionSummary(
          count: _asInt(row['total']),
          open: _asInt(row['open_count']) > 0,
          gap: _asInt(row['gap_flag']) > 0,
        ),
    };
  }

  Future<List<ExcursionAction>> actionsForExcursion({
    required int userId,
    required int excursionId,
  }) async {
    final TemperatureExcursion? excursion = await _excursionById(
      _requireDatabase(),
      excursionId,
    );
    if (excursion == null) {
      throw const ExcursionException('이탈 기록을 찾을 수 없습니다.');
    }
    await _requireVisible(userId, excursion.shipmentId);
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_actionSelect
      WHERE excursion_actions.excursion_id = ?
      ORDER BY excursion_actions.created_at ASC, excursion_actions.id ASC
      ''',
      <Object>[excursionId],
    );
    return rows.map(_actionFromRow).toList();
  }

  Future<List<ExcursionAction>> actionsForShipment({
    required int userId,
    required int shipmentId,
  }) async {
    await _requireVisible(userId, shipmentId);
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_actionSelect
      WHERE excursion_actions.shipment_id = ?
      ORDER BY excursion_actions.created_at ASC, excursion_actions.id ASC
      ''',
      <Object>[shipmentId],
    );
    return rows.map(_actionFromRow).toList();
  }

  Future<Map<int, ExcursionAction>> latestActionsForShipment(
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_actionSelect
      INNER JOIN (
        SELECT actions.excursion_id AS excursion_id, MAX(actions.id) AS id
        FROM excursion_actions AS actions
        INNER JOIN temperature_excursions
          ON temperature_excursions.id = actions.excursion_id
        WHERE temperature_excursions.shipment_id = ?
        GROUP BY actions.excursion_id
      ) latest ON latest.id = excursion_actions.id
      ''',
      <Object>[shipmentId],
    );
    return <int, ExcursionAction>{
      for (final Map<String, Object?> row in rows)
        if (row['excursion_id'] != null)
          row['excursion_id']! as int: _actionFromRow(row),
    };
  }

  /// 이탈 이벤트에 원인·조치 기록이 있는지만 돌려줍니다. 담당자가 바뀌어도 기록은 남습니다.
  Future<Map<int, bool>> recordedExcursionActions(List<int> shipmentIds) async {
    if (shipmentIds.isEmpty) {
      return const <int, bool>{};
    }
    final String placeholders = List<String>.filled(
      shipmentIds.length,
      '?',
    ).join(', ');
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      SELECT DISTINCT excursion_actions.excursion_id AS excursion_id
      FROM excursion_actions
      INNER JOIN temperature_excursions
        ON temperature_excursions.id = excursion_actions.excursion_id
      WHERE temperature_excursions.shipment_id IN ($placeholders)
      ''',
      shipmentIds,
    );
    return <int, bool>{
      for (final Map<String, Object?> row in rows)
        row['excursion_id']! as int: true,
    };
  }

  Future<int> userVersion() async {
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      'PRAGMA user_version',
    );
    return _asInt(rows.single['user_version']);
  }

  /// 보이는 운송 건의 검토 이력을 시간순으로 돌려줍니다. 행을 지우지 않습니다.
  Future<List<QualityReview>> qualityReviewsFor({
    required int userId,
    required int shipmentId,
  }) async {
    await _requireVisible(userId, shipmentId);
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_reviewSelect
      WHERE quality_reviews.shipment_id = ?
      ORDER BY quality_reviews.created_at ASC, quality_reviews.id ASC
      ''',
      <Object>[shipmentId],
    );
    return rows.map(_reviewFromRow).toList();
  }

  Future<Map<int, QualityReview>> latestQualityReviews(
    List<int> shipmentIds,
  ) async {
    if (shipmentIds.isEmpty) {
      return const <int, QualityReview>{};
    }
    final String placeholders = List<String>.filled(
      shipmentIds.length,
      '?',
    ).join(', ');
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_reviewSelect
      INNER JOIN (
        SELECT reviews.shipment_id AS shipment_id, MAX(reviews.id) AS id
        FROM quality_reviews AS reviews
        WHERE reviews.shipment_id IN ($placeholders)
        GROUP BY reviews.shipment_id
      ) latest ON latest.id = quality_reviews.id
      ''',
      shipmentIds,
    );
    return <int, QualityReview>{
      for (final Map<String, Object?> row in rows)
        row['shipment_id']! as int: _reviewFromRow(row),
    };
  }

  /// 품질관리자가 참여한 운송 건에만 새 검토 이력을 추가합니다.
  /// 이전 이력과 온도 기록은 수정하지 않습니다.
  Future<QualityReview> saveQualityReview({
    required int actorUserId,
    required int shipmentId,
    required QualityReviewStatus status,
    required String comment,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final AppUser? actor = await _userById(txn, actorUserId);
      if (actor == null || actor.role != UserRole.qualityManager) {
        throw const QualityReviewException('품질관리자만 검토 상태를 변경할 수 있습니다.');
      }
      final ShipmentRecord? shipment = await _findShipment(txn, shipmentId);
      if (shipment == null) {
        throw const QualityReviewException('운송 건을 찾을 수 없습니다.');
      }
      final List<Map<String, Object?>> member = await txn.query(
        'shipment_members',
        columns: <String>['user_id'],
        where: 'shipment_id = ? AND user_id = ? AND role = ?',
        whereArgs: <Object>[
          shipmentId,
          actorUserId,
          UserRole.qualityManager.name,
        ],
        limit: 1,
      );
      if (member.isEmpty) {
        throw const QualityReviewException('참여한 운송 건만 검토할 수 있습니다.');
      }
      final String now = _timestamp();
      final int id = await txn.insert('quality_reviews', <String, Object?>{
        'shipment_id': shipmentId,
        'reviewer_user_id': actorUserId,
        'review_status': status.storageValue,
        'review_comment': comment.trim(),
        'created_at': now,
        'updated_at': now,
      });
      final List<Map<String, Object?>> rows = await txn.rawQuery(
        '''
        $_reviewSelect
        WHERE quality_reviews.id = ?
        LIMIT 1
        ''',
        <Object>[id],
      );
      return _reviewFromRow(rows.single);
    });
  }

  /// 원인 기록을 추가합니다. 이전 기록은 남고, 품질 검토 완료로 바뀌지 않습니다.
  /// 시나리오 종류를 원인으로 복사하지 않습니다.
  Future<ExcursionAction> saveExcursionAction({
    required int actorUserId,
    required int excursionId,
    required String causeCategory,
    required String causeCertainty,
    required String description,
    required String actionTaken,
    DateTime? discoveredAt,
    DateTime? responseStartedAt,
    String? reportedTo,
    DateTime? reportedAt,
    String? note,
    String? situationType,
    bool? responsibleContacted,
    bool? holdGuidanceGiven,
    bool? holdActionCompleted,
  }) async {
    if (!ExcursionAction.categories.contains(causeCategory)) {
      throw const ExcursionException('원인 분류를 선택해 주세요.');
    }
    if (causeCertainty != ExcursionAction.confirmed &&
        causeCertainty != ExcursionAction.suspected) {
      throw const ExcursionException('확인된 원인인지 추정 원인인지 선택해 주세요.');
    }
    final String detail = description.trim();
    final String action = actionTaken.trim();
    if (detail.isEmpty || action.isEmpty) {
      throw const ExcursionException('상황 설명과 시행한 조치를 입력해 주세요.');
    }
    if (situationType != null &&
        !ExcursionAction.situationTypes.contains(situationType)) {
      throw const ExcursionException('상황 유형을 선택해 주세요.');
    }
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final TemperatureExcursion? excursion = await _excursionById(
        txn,
        excursionId,
      );
      if (excursion == null) {
        throw const ExcursionException('이탈 기록을 찾을 수 없습니다.');
      }
      await _requireAssignee(
        txn,
        actorUserId: actorUserId,
        shipmentId: excursion.shipmentId,
        action: '원인과 조치를 기록',
      );
      final String createdAt = _timestamp();
      final int id = await txn.insert('excursion_actions', <String, Object?>{
        'shipment_id': excursion.shipmentId,
        'excursion_id': excursionId,
        'author_user_id': actorUserId,
        'cause_category': causeCategory,
        'cause_certainty': causeCertainty,
        'description': detail,
        'discovered_at': discoveredAt?.toUtc().toIso8601String(),
        'response_started_at': responseStartedAt?.toUtc().toIso8601String(),
        'action_taken': action,
        'reported_to': _blankToNull(reportedTo),
        'reported_at': reportedAt?.toUtc().toIso8601String(),
        'note': _blankToNull(note),
        'created_at': createdAt,
        'situation_type': situationType,
        'responsible_contacted': _optionalFlag(responsibleContacted),
        'hold_guidance_given': _optionalFlag(holdGuidanceGiven),
        'hold_action_completed': _optionalFlag(holdActionCompleted),
      });
      return (await _actionById(txn, id))!;
    });
  }

  /// 이탈 이벤트가 없는 수동 상황 보고입니다. 온도 이탈 행을 만들지 않습니다.
  Future<ExcursionAction> saveSituationReport({
    required int actorUserId,
    required int shipmentId,
    required String situationType,
    required String description,
    required String actionTaken,
    required bool responsibleContacted,
    required bool holdGuidanceGiven,
    required bool holdActionCompleted,
    String? note,
  }) async {
    if (!ExcursionAction.situationTypes.contains(situationType)) {
      throw const ExcursionException('상황 유형을 선택해 주세요.');
    }
    final String detail = description.trim();
    final String action = actionTaken.trim();
    if (detail.isEmpty || action.isEmpty) {
      throw const ExcursionException('상황 설명과 시행한 조치를 입력해 주세요.');
    }
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      await _requireAssignee(
        txn,
        actorUserId: actorUserId,
        shipmentId: shipmentId,
        action: '상황을 기록',
      );
      final String createdAt = _timestamp();
      final int id = await txn.insert('excursion_actions', <String, Object?>{
        'shipment_id': shipmentId,
        'excursion_id': null,
        'author_user_id': actorUserId,
        'cause_category': 'other',
        'cause_certainty': ExcursionAction.suspected,
        'description': detail,
        'action_taken': action,
        'note': _blankToNull(note),
        'created_at': createdAt,
        'situation_type': situationType,
        'responsible_contacted': responsibleContacted ? 1 : 0,
        'hold_guidance_given': holdGuidanceGiven ? 1 : 0,
        'hold_action_completed': holdActionCompleted ? 1 : 0,
      });
      return (await _actionById(txn, id))!;
    });
  }

  int? _optionalFlag(bool? value) {
    if (value == null) {
      return null;
    }
    return value ? 1 : 0;
  }

  /// 수락 전에만 요청자가 취소할 수 있습니다.
  Future<ShipmentTransfer> cancelHandover({
    required int actorUserId,
    required int transferId,
  }) {
    return _respond(
      actorUserId: actorUserId,
      transferId: transferId,
      nextStatus: TransferStatus.cancelled,
      asRecipient: false,
    );
  }

  Future<ShipmentTransfer> _respond({
    required int actorUserId,
    required int transferId,
    required TransferStatus nextStatus,
    required bool asRecipient,
    String? rejectionReason,
  }) async {
    final Database db = _requireDatabase();
    return db.transaction((Transaction txn) async {
      final ShipmentTransfer? transfer = await _transferById(txn, transferId);
      if (transfer == null) {
        throw const TransferException('인수인계 요청을 찾을 수 없습니다.');
      }
      if (transfer.status != TransferStatus.requested) {
        throw const TransferException('이미 처리된 인수인계 요청입니다.');
      }
      if (asRecipient && transfer.toUserId != actorUserId) {
        throw const TransferException('지정된 인수자만 요청을 처리할 수 있습니다.');
      }
      if (!asRecipient && transfer.fromUserId != actorUserId) {
        throw const TransferException('요청한 운송자만 취소할 수 있습니다.');
      }
      final ShipmentRecord shipment = await _requireShipment(
        txn,
        transfer.shipmentId,
      );
      if (shipment.assigneeUserId != transfer.fromUserId) {
        throw const TransferException('담당자가 바뀌어 이 요청은 처리할 수 없습니다.');
      }
      if (shipment.status == ShipmentStatus.completed) {
        throw const TransferException('운송 완료된 운송 건은 인수인계할 수 없습니다.');
      }
      final String respondedAt = _timestamp();
      final int updated = await txn.update(
        'shipment_transfers',
        <String, Object?>{
          'status': nextStatus.storageValue,
          'resolved_at': respondedAt,
          'responded_at': respondedAt,
          'rejection_reason': rejectionReason,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object>[transferId, TransferStatus.requested.storageValue],
      );
      if (updated != 1) {
        throw const TransferException('이미 처리된 인수인계 요청입니다.');
      }
      if (nextStatus == TransferStatus.accepted) {
        final int assigneeUpdated = await txn.update(
          'shipments',
          <String, Object?>{'assignee_user_id': transfer.toUserId},
          where: 'id = ? AND assignee_user_id = ?',
          whereArgs: <Object>[shipment.id, transfer.fromUserId],
        );
        if (assigneeUpdated != 1) {
          throw const TransferException('담당자를 변경하지 못했습니다.');
        }
      }
      return (await _transferById(txn, transferId))!;
    });
  }

  Future<void> _ensureDemoAccount({
    required String loginId,
    required String password,
    required UserRole role,
  }) async {
    final List<Map<String, Object?>> existing = await _requireDatabase().query(
      'users',
      columns: <String>['id'],
      where: 'login_id = ?',
      whereArgs: <Object>[loginId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }
    await createUser(loginId: loginId, password: password, role: role);
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
        assignee_user_id INTEGER NOT NULL REFERENCES users(id),
        participation_code TEXT NOT NULL UNIQUE,
        vaccine TEXT NOT NULL,
        manufacturer TEXT NOT NULL,
        lot TEXT NOT NULL,
        expiry_date TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        origin TEXT NOT NULL,
        destination TEXT NOT NULL,
        target_range TEXT NOT NULL,
        temp_min REAL NOT NULL,
        temp_max REAL NOT NULL,
        status TEXT NOT NULL CHECK (
          status IN ('registered', 'in_transit', 'completed')
        ),
        created_at TEXT NOT NULL,
        started_at TEXT,
        completed_at TEXT,
        source TEXT NOT NULL CHECK (source = 'user_input'),
        vaccine_product_id INTEGER,
        vaccine_storage_profile_id INTEGER,
        selected_product_name TEXT,
        selected_manufacturer TEXT,
        selected_storage_stage TEXT,
        recommended_min_temperature REAL,
        recommended_max_temperature REAL,
        actual_min_temperature REAL,
        actual_max_temperature REAL,
        storage_profile_reference TEXT,
        handling_notes_snapshot TEXT,
        time_limit_notes_snapshot TEXT,
        demo_mode TEXT,
        auto_gap_skips INTEGER NOT NULL DEFAULT 0,
        auto_cooldown_until_count INTEGER NOT NULL DEFAULT 0,
        auto_completed_events INTEGER NOT NULL DEFAULT 0,
        release_required INTEGER NOT NULL DEFAULT 0 CHECK (release_required IN (0, 1)),
        CHECK (temp_min <= temp_max),
        CHECK (
          demo_mode IS NULL OR demo_mode IN ('probabilistic', 'presentation')
        )
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
    await _createTransferTable(db);
    await db.execute(
      'CREATE INDEX idx_shipments_owner ON shipments(owner_user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_shipments_assignee ON shipments(assignee_user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_shipment_members_user ON shipment_members(user_id)',
    );
    await _createTransferIndexes(db);
    await _createTemperatureTable(db);
    await _createTemperatureIndexes(db);
    await _createExcursionTables(db);
    await _createQualityReviewTable(db);
    await _createCustodyTables(db);
    await _createVaccineTables(db);
    await _ensureVaccineCatalog(db);
  }

  /// 버전 1 파일에 상태, 온도 범위, 담당 운송자, 인수인계 이력 테이블을 더합니다.
  /// 계정과 기존 운송 건 행은 지우지 않습니다.
  Future<void> _upgradeToV2(Database db) async {
    await db.execute(
      "ALTER TABLE shipments ADD COLUMN status TEXT NOT NULL DEFAULT 'registered'",
    );
    await db.execute('ALTER TABLE shipments ADD COLUMN temp_min REAL');
    await db.execute('ALTER TABLE shipments ADD COLUMN temp_max REAL');
    await db.execute(
      'ALTER TABLE shipments ADD COLUMN assignee_user_id INTEGER',
    );
    final List<Map<String, Object?>> rows = await db.query(
      'shipments',
      columns: <String>[
        'id',
        'owner_user_id',
        'target_range',
        'assignee_user_id',
      ],
    );
    for (final Map<String, Object?> row in rows) {
      final TemperatureBounds? bounds = TemperatureBounds.tryParse(
        row['target_range']! as String,
      );
      await db.update(
        'shipments',
        <String, Object?>{
          'assignee_user_id': row['assignee_user_id'] ?? row['owner_user_id'],
          'status': ShipmentStatus.registered.storageValue,
          if (bounds != null) 'temp_min': bounds.min,
          if (bounds != null) 'temp_max': bounds.max,
        },
        where: 'id = ?',
        whereArgs: <Object>[row['id']!],
      );
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shipment_transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        from_user_id INTEGER NOT NULL REFERENCES users(id),
        to_user_id INTEGER NOT NULL REFERENCES users(id),
        status TEXT NOT NULL CHECK (
          status IN ('requested', 'accepted', 'rejected')
        ),
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipments_assignee ON shipments(assignee_user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipment_transfers_shipment ON shipment_transfers(shipment_id)',
    );
  }

  /// 버전 2의 인수인계 표를 장소, 메모, 취소 상태를 담는 표로 바꿉니다.
  /// 기존 요청 행은 지우지 않고 옮깁니다.
  Future<void> _upgradeToV3(Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'shipment_transfers'",
    );
    if (tables.isEmpty) {
      await _createTransferTable(db);
      await _createTransferIndexes(db);
      return;
    }
    final Set<String> columns = (await db.rawQuery(
      'PRAGMA table_info(shipment_transfers)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    if (columns.contains('requested_at') &&
        columns.contains('rejection_reason')) {
      await _createTransferIndexes(db);
      return;
    }
    await db.execute(
      'ALTER TABLE shipment_transfers RENAME TO shipment_transfers_v2',
    );
    await _createTransferTable(db);
    await db.execute('''
      INSERT INTO shipment_transfers (
        id, shipment_id, from_user_id, to_user_id, status,
        created_at, requested_at, resolved_at, responded_at, location
      )
      SELECT
        id, shipment_id, from_user_id, to_user_id, status,
        created_at, created_at, resolved_at, resolved_at, ''
      FROM shipment_transfers_v2
    ''');
    await db.execute('DROP TABLE shipment_transfers_v2');
    await _createTransferIndexes(db);
  }

  /// 운송 시작·완료 시각과 시연용 온도 기록을 추가합니다.
  /// 계정, 운송 건, 참여 관계, 인수인계 행은 지우지 않습니다.
  Future<void> _upgradeToV4(Database db) async {
    final Set<String> columns = (await db.rawQuery(
      'PRAGMA table_info(shipments)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    if (!columns.contains('started_at')) {
      await db.execute('ALTER TABLE shipments ADD COLUMN started_at TEXT');
    }
    if (!columns.contains('completed_at')) {
      await db.execute('ALTER TABLE shipments ADD COLUMN completed_at TEXT');
    }
    await _createTemperatureTable(db);
    await _createTemperatureIndexes(db);
  }

  /// 온도 이탈, 원인 기록, 시연 시나리오 표를 추가합니다.
  /// 기존 계정과 온도 기록은 지우지 않습니다.
  Future<void> _upgradeToV5(Database db) async {
    await _createExcursionTables(db);
  }

  /// 품질 검토 이력 표를 추가합니다. 기존 행은 지우거나 고치지 않습니다.
  Future<void> _upgradeToV6(Database db) async {
    await _createQualityReviewTable(db);
  }

  /// 백신 목록과 운송 건 스냅샷 열을 추가합니다.
  /// 기존 운송 건의 온도 범위와 다른 행은 바꾸지 않습니다.
  Future<void> _upgradeToV7(Database db) async {
    await _createVaccineTables(db);
    const Map<String, String> columns = <String, String>{
      'vaccine_product_id': 'INTEGER',
      'vaccine_storage_profile_id': 'INTEGER',
      'selected_product_name': 'TEXT',
      'selected_manufacturer': 'TEXT',
      'selected_storage_stage': 'TEXT',
      'recommended_min_temperature': 'REAL',
      'recommended_max_temperature': 'REAL',
      'actual_min_temperature': 'REAL',
      'actual_max_temperature': 'REAL',
      'storage_profile_reference': 'TEXT',
      'handling_notes_snapshot': 'TEXT',
      'time_limit_notes_snapshot': 'TEXT',
    };
    final Set<String> existing = (await db.rawQuery(
      'PRAGMA table_info(shipments)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    for (final MapEntry<String, String> column in columns.entries) {
      if (!existing.contains(column.key)) {
        await db.execute(
          'ALTER TABLE shipments ADD COLUMN ${column.key} ${column.value}',
        );
      }
    }
    await _ensureVaccineCatalog(db);
  }

  /// 조치 기록에 운송 건과 상황 유형, 연락·보류 여부를 추가합니다.
  /// 기존 행의 내용과 이벤트 ID는 유지하고, 새 값은 비워 둡니다.
  Future<void> _upgradeToV8(Database db) async {
    final Set<String> columns = (await db.rawQuery(
      'PRAGMA table_info(excursion_actions)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    if (!columns.contains('id')) {
      return;
    }
    if (columns.contains('shipment_id') && columns.contains('situation_type')) {
      return;
    }
    await db.execute('''
      CREATE TABLE excursion_actions_v8 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        excursion_id INTEGER REFERENCES temperature_excursions(id),
        author_user_id INTEGER NOT NULL REFERENCES users(id),
        cause_category TEXT NOT NULL,
        cause_certainty TEXT NOT NULL CHECK (
          cause_certainty IN ('confirmed', 'suspected')
        ),
        description TEXT NOT NULL,
        discovered_at TEXT,
        response_started_at TEXT,
        action_taken TEXT NOT NULL,
        reported_to TEXT,
        reported_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        situation_type TEXT,
        responsible_contacted INTEGER CHECK (
          responsible_contacted IS NULL OR responsible_contacted IN (0, 1)
        ),
        hold_guidance_given INTEGER CHECK (
          hold_guidance_given IS NULL OR hold_guidance_given IN (0, 1)
        ),
        hold_action_completed INTEGER CHECK (
          hold_action_completed IS NULL OR hold_action_completed IN (0, 1)
        )
      )
    ''');
    String source(String name) {
      return columns.contains(name) ? 'actions.$name' : 'NULL';
    }

    await db.execute('''
      INSERT INTO excursion_actions_v8 (
        id, shipment_id, excursion_id, author_user_id, cause_category,
        cause_certainty, description, discovered_at, response_started_at,
        action_taken, reported_to, reported_at, note, created_at,
        situation_type, responsible_contacted, hold_guidance_given,
        hold_action_completed
      )
      SELECT
        actions.id, excursions.shipment_id, actions.excursion_id,
        actions.author_user_id, actions.cause_category, actions.cause_certainty,
        actions.description, ${source('discovered_at')}, ${source('response_started_at')},
        actions.action_taken, ${source('reported_to')}, ${source('reported_at')},
        ${source('note')}, actions.created_at, NULL, NULL, NULL, NULL
      FROM excursion_actions AS actions
      INNER JOIN temperature_excursions AS excursions
        ON excursions.id = actions.excursion_id
    ''');
    final int before =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM excursion_actions'),
        ) ??
        0;
    final int after =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM excursion_actions_v8'),
        ) ??
        0;
    if (before != after) {
      throw StateError('기존 조치 기록 건수가 달라 이관을 중단합니다.');
    }
    await db.execute('DROP TABLE excursion_actions');
    await db.execute(
      'ALTER TABLE excursion_actions_v8 RENAME TO excursion_actions',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_excursion_actions_event ON excursion_actions(excursion_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_excursion_actions_shipment ON excursion_actions(shipment_id, created_at, id)',
    );
    await db.execute('''
      UPDATE sqlite_sequence
      SET name = 'excursion_actions'
      WHERE name = 'excursion_actions_v8'
    ''');
  }

  /// 자동 시연 방식과 진행 상태만 추가합니다. 기존 행의 모드는 비워 둡니다.
  Future<void> _upgradeToV9(Database db) async {
    final Set<String> shipmentColumns = (await db.rawQuery(
      'PRAGMA table_info(shipments)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    if (shipmentColumns.contains('id')) {
      if (!shipmentColumns.contains('demo_mode')) {
        await db.execute('ALTER TABLE shipments ADD COLUMN demo_mode TEXT');
      }
      if (!shipmentColumns.contains('auto_gap_skips')) {
        await db.execute(
          'ALTER TABLE shipments ADD COLUMN auto_gap_skips INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!shipmentColumns.contains('auto_cooldown_until_count')) {
        await db.execute(
          'ALTER TABLE shipments ADD COLUMN auto_cooldown_until_count INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    final List<Map<String, Object?>> tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'demo_temperature_scenarios'
      ''');
    if (tables.isEmpty) {
      return;
    }
    final Set<String> scenarioColumns = (await db.rawQuery(
      'PRAGMA table_info(demo_temperature_scenarios)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    if (!scenarioColumns.contains('trigger_source')) {
      await db.execute('''
        ALTER TABLE demo_temperature_scenarios
        ADD COLUMN trigger_source TEXT NOT NULL DEFAULT 'manual'
        ''');
    }
  }

  /// 끝난 자동 이상 상황의 개수만 추가합니다. 기존 온도와 모드는 바꾸지 않습니다.
  Future<void> _upgradeToV10(Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'shipments'
      ''');
    if (tables.isEmpty) {
      return;
    }
    final Set<String> shipmentColumns = (await db.rawQuery(
      'PRAGMA table_info(shipments)',
    )).map((Map<String, Object?> row) => row['name']! as String).toSet();
    if (!shipmentColumns.contains('auto_completed_events')) {
      await db.execute('''
        ALTER TABLE shipments
        ADD COLUMN auto_completed_events INTEGER NOT NULL DEFAULT 0
        ''');
    }
  }

  /// 출고 확인과 의료기관 인수 표를 추가합니다. 기존 행은 바꾸지 않습니다.
  Future<void> _upgradeToV11(Database db) async {
    final List<Map<String, Object?>> tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'shipments'
      ''');
    if (tables.isNotEmpty) {
      final Set<String> shipmentColumns = (await db.rawQuery(
        'PRAGMA table_info(shipments)',
      )).map((Map<String, Object?> row) => row['name']! as String).toSet();
      if (!shipmentColumns.contains('release_required')) {
        await db.execute('''
          ALTER TABLE shipments
          ADD COLUMN release_required INTEGER NOT NULL DEFAULT 0
            CHECK (release_required IN (0, 1))
          ''');
      }
    }
    await _createCustodyTables(db);
  }

  Future<void> _createCustodyTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shipment_releases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL UNIQUE REFERENCES shipments(id),
        confirmed_by_user_id INTEGER NOT NULL REFERENCES users(id),
        confirmed_at TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shipment_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL UNIQUE REFERENCES shipments(id),
        receiver_user_id INTEGER NOT NULL REFERENCES users(id),
        received_quantity INTEGER NOT NULL CHECK (received_quantity >= 0),
        package_condition TEXT NOT NULL CHECK (
          package_condition IN ('intact', 'suspected_damage', 'needs_check')
        ),
        receipt_note TEXT,
        received_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createVaccineTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vaccine_products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_name TEXT NOT NULL UNIQUE,
        manufacturer TEXT,
        vaccine_type TEXT,
        authorization_reference TEXT,
        authorization_item_code TEXT,
        source_document TEXT,
        source_url TEXT,
        source_checked_at TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        verification_status TEXT NOT NULL CHECK (
          verification_status IN (
            'verified',
            'verification_required',
            'outdated'
          )
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vaccine_storage_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vaccine_product_id INTEGER NOT NULL REFERENCES vaccine_products(id),
        profile_name TEXT NOT NULL,
        storage_stage TEXT NOT NULL,
        min_temperature REAL NOT NULL,
        max_temperature REAL NOT NULL,
        freezing_prohibited INTEGER NOT NULL CHECK (
          freezing_prohibited IN (0, 1)
        ),
        refreezing_prohibited INTEGER NOT NULL CHECK (
          refreezing_prohibited IN (0, 1)
        ),
        light_protection_required INTEGER NOT NULL CHECK (
          light_protection_required IN (0, 1)
        ),
        handling_notes TEXT,
        time_limit_notes TEXT,
        source_reference TEXT,
        verification_status TEXT NOT NULL CHECK (
          verification_status IN (
            'verified',
            'verification_required',
            'outdated'
          )
        ),
        CHECK (min_temperature <= max_temperature),
        UNIQUE (vaccine_product_id, storage_stage)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_vaccine_profiles_product
      ON vaccine_storage_profiles(vaccine_product_id, id)
    ''');
  }

  /// 없는 제품과 보관 단계만 넣습니다.
  /// 이미 있는 제품은 활성 여부만 맞추고, 보관 조건·출처·검증 상태와 운송 건은 바꾸지 않습니다.
  Future<void> _ensureVaccineCatalog(DatabaseExecutor db) async {
    for (final VaccineCatalogSeed seed in VaccineCatalogSeed.products) {
      final List<Map<String, Object?>> existing = await db.query(
        'vaccine_products',
        columns: <String>['id'],
        where: 'product_name = ?',
        whereArgs: <Object>[seed.productName],
        limit: 1,
      );
      final int productId;
      if (existing.isEmpty) {
        productId = await db.insert('vaccine_products', <String, Object?>{
          'product_name': seed.productName,
          'manufacturer': seed.manufacturer,
          'vaccine_type': seed.vaccineType,
          'authorization_reference': seed.authorizationReference,
          'authorization_item_code': seed.authorizationItemCode,
          'source_document': seed.sourceDocument,
          'source_url': seed.sourceUrl,
          'source_checked_at': seed.sourceCheckedAt,
          'is_active': seed.selectableForNewShipment ? 1 : 0,
          'verification_status': seed.verificationStatus.storageValue,
        });
      } else {
        productId = existing.single['id']! as int;
        await db.update(
          'vaccine_products',
          <String, Object?>{'is_active': seed.selectableForNewShipment ? 1 : 0},
          where: 'id = ?',
          whereArgs: <Object>[productId],
        );
      }
      for (final VaccineProfileSeed profile in seed.profiles) {
        final List<Map<String, Object?>> profiles = await db.query(
          'vaccine_storage_profiles',
          columns: <String>['id'],
          where: 'vaccine_product_id = ? AND storage_stage = ?',
          whereArgs: <Object>[productId, profile.storageStage],
          limit: 1,
        );
        if (profiles.isNotEmpty) {
          continue;
        }
        await db.insert('vaccine_storage_profiles', <String, Object?>{
          'vaccine_product_id': productId,
          'profile_name': profile.profileName,
          'storage_stage': profile.storageStage,
          'min_temperature': profile.minTemperature,
          'max_temperature': profile.maxTemperature,
          'freezing_prohibited': profile.freezingProhibited ? 1 : 0,
          'refreezing_prohibited': profile.refreezingProhibited ? 1 : 0,
          'light_protection_required': profile.lightProtectionRequired ? 1 : 0,
          'handling_notes': profile.handlingNotes,
          'time_limit_notes': profile.timeLimitNotes,
          'source_reference': profile.referenceFor(seed),
          'verification_status': profile.verificationStatus.storageValue,
        });
      }
    }
    await _rememberVaccineCatalog(db);
  }

  Future<void> _rememberVaccineCatalog(DatabaseExecutor db) async {
    final List<Map<String, Object?>> productRows = await db.query(
      'vaccine_products',
      where: 'is_active = 1',
      orderBy: 'id ASC',
    );
    final List<Map<String, Object?>> profileRows = await db.query(
      'vaccine_storage_profiles',
      orderBy: 'id ASC',
    );
    _cachedProducts = productRows.map(_productFromRow).toList();
    _cachedProfiles.clear();
    for (final VaccineStorageProfile profile in profileRows.map(
      _profileFromRow,
    )) {
      _cachedProfiles
          .putIfAbsent(
            profile.vaccineProductId,
            () => <VaccineStorageProfile>[],
          )
          .add(profile);
    }
  }

  Future<void> _createQualityReviewTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quality_reviews (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        reviewer_user_id INTEGER NOT NULL REFERENCES users(id),
        review_status TEXT NOT NULL CHECK (
          review_status IN (
            'not_reviewed',
            'in_review',
            'needs_information',
            'on_hold',
            'review_completed'
          )
        ),
        review_comment TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_quality_reviews_shipment
      ON quality_reviews(shipment_id, created_at, id)
    ''');
  }

  Future<void> _createExcursionTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS temperature_excursions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        direction TEXT NOT NULL CHECK (direction IN ('above_max', 'below_min')),
        started_at TEXT NOT NULL,
        last_out_of_range_at TEXT NOT NULL,
        recovered_at TEXT,
        min_temperature REAL NOT NULL,
        max_temperature REAL NOT NULL,
        data_gap_detected INTEGER NOT NULL DEFAULT 0 CHECK (data_gap_detected IN (0, 1)),
        status TEXT NOT NULL CHECK (status IN ('open', 'recovered')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS excursion_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        excursion_id INTEGER REFERENCES temperature_excursions(id),
        author_user_id INTEGER NOT NULL REFERENCES users(id),
        cause_category TEXT NOT NULL,
        cause_certainty TEXT NOT NULL CHECK (
          cause_certainty IN ('confirmed', 'suspected')
        ),
        description TEXT NOT NULL,
        discovered_at TEXT,
        response_started_at TEXT,
        action_taken TEXT NOT NULL,
        reported_to TEXT,
        reported_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        situation_type TEXT,
        responsible_contacted INTEGER CHECK (
          responsible_contacted IS NULL OR responsible_contacted IN (0, 1)
        ),
        hold_guidance_given INTEGER CHECK (
          hold_guidance_given IS NULL OR hold_guidance_given IN (0, 1)
        ),
        hold_action_completed INTEGER CHECK (
          hold_action_completed IS NULL OR hold_action_completed IN (0, 1)
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS demo_temperature_scenarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        scenario_type TEXT NOT NULL CHECK (
          scenario_type IN ('door_open', 'cooling_fault', 'overcool')
        ),
        phase TEXT NOT NULL CHECK (
          phase IN ('rising', 'holding', 'recovering', 'ended')
        ),
        started_at TEXT NOT NULL,
        ended_at TEXT,
        started_by_user_id INTEGER NOT NULL REFERENCES users(id),
        hold_samples INTEGER NOT NULL DEFAULT 0,
        trigger_source TEXT NOT NULL DEFAULT 'manual'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_excursions_shipment ON temperature_excursions(shipment_id, started_at)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_excursions_open
      ON temperature_excursions(shipment_id)
      WHERE status = 'open'
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_excursion_actions_event ON excursion_actions(excursion_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_excursion_actions_shipment ON excursion_actions(shipment_id, created_at, id)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_demo_scenarios_active
      ON demo_temperature_scenarios(shipment_id)
      WHERE phase != 'ended'
    ''');
  }

  Future<void> _createTemperatureTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS temperature_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        temperature_c REAL NOT NULL,
        measured_at TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        source TEXT NOT NULL CHECK (source = 'demo_virtual'),
        assignee_user_id INTEGER NOT NULL REFERENCES users(id)
      )
    ''');
  }

  Future<void> _createTemperatureIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_temperature_readings_shipment
      ON temperature_readings(shipment_id, measured_at, id)
    ''');
  }

  Future<void> _createTransferTable(
    DatabaseExecutor db, {
    String tableName = 'shipment_transfers',
  }) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id INTEGER NOT NULL REFERENCES shipments(id),
        from_user_id INTEGER NOT NULL REFERENCES users(id),
        to_user_id INTEGER NOT NULL REFERENCES users(id),
        status TEXT NOT NULL CHECK (
          status IN ('requested', 'accepted', 'rejected', 'cancelled')
        ),
        created_at TEXT NOT NULL,
        requested_at TEXT NOT NULL,
        resolved_at TEXT,
        responded_at TEXT,
        location TEXT NOT NULL DEFAULT '',
        scheduled_at TEXT,
        note TEXT,
        rejection_reason TEXT,
        handover_temp_c REAL,
        CHECK (from_user_id != to_user_id)
      )
    ''');
  }

  Future<void> _createTransferIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipment_transfers_shipment ON shipment_transfers(shipment_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipment_transfers_to ON shipment_transfers(to_user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shipment_transfers_from ON shipment_transfers(from_user_id)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_shipment_transfers_open
      ON shipment_transfers(shipment_id)
      WHERE status = 'requested'
    ''');
  }

  Future<List<ShipmentTransfer>> _transfers(
    String where,
    List<Object> args, {
    bool newestFirst = true,
  }) async {
    final String order = newestFirst
        ? 'shipment_transfers.requested_at DESC'
        : 'shipment_transfers.requested_at ASC';
    final List<Map<String, Object?>> rows = await _requireDatabase().rawQuery(
      '''
      $_transferSelect
      WHERE $where
      ORDER BY $order
      ''',
      args,
    );
    return rows.map(_transferFromRow).toList();
  }

  Future<ShipmentTransfer?> _transferById(DatabaseExecutor db, int id) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      $_transferSelect
      WHERE shipment_transfers.id = ?
      LIMIT 1
      ''',
      <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _transferFromRow(rows.single);
  }

  Future<ShipmentRecord> _requireAssignee(
    DatabaseExecutor db, {
    required int actorUserId,
    required int shipmentId,
    required String action,
  }) async {
    final AppUser? actor = await _userById(db, actorUserId);
    if (actor == null || actor.role != UserRole.transporter) {
      throw ExcursionException('현재 담당 운송자만 $action할 수 있습니다.');
    }
    final ShipmentRecord? shipment = await _findShipment(db, shipmentId);
    if (shipment == null) {
      throw const ExcursionException('운송 건을 찾을 수 없습니다.');
    }
    if (shipment.assigneeUserId != actor.id) {
      throw ExcursionException('현재 담당 운송자만 $action할 수 있습니다.');
    }
    return shipment;
  }

  Future<void> _requireVisible(int userId, int shipmentId) async {
    final ShipmentRecord? shipment = await shipmentVisibleTo(
      userId: userId,
      shipmentId: shipmentId,
    );
    if (shipment == null) {
      throw const ExcursionException('이 운송 건의 기록을 볼 수 없습니다.');
    }
  }

  Future<void> _endActiveScenario(
    DatabaseExecutor db,
    int shipmentId,
    DateTime at,
  ) async {
    await db.update(
      'demo_temperature_scenarios',
      <String, Object?>{
        'phase': DemoScenario.ended,
        'ended_at': at.toUtc().toIso8601String(),
      },
      where: 'shipment_id = ? AND phase != ?',
      whereArgs: <Object>[shipmentId, DemoScenario.ended],
    );
  }

  Future<DemoScenario?> _activeScenario(
    DatabaseExecutor db,
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'demo_temperature_scenarios',
      where: 'shipment_id = ? AND phase != ?',
      whereArgs: <Object>[shipmentId, DemoScenario.ended],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _scenarioFromRow(rows.single);
  }

  Future<DemoScenario?> _scenarioById(DatabaseExecutor db, int id) async {
    final List<Map<String, Object?>> rows = await db.query(
      'demo_temperature_scenarios',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _scenarioFromRow(rows.single);
  }

  Future<TemperatureExcursion?> _openExcursion(
    DatabaseExecutor db,
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'temperature_excursions',
      where: 'shipment_id = ? AND status = ?',
      whereArgs: <Object>[shipmentId, TemperatureExcursion.openStatus],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _excursionFromRow(rows.single);
  }

  Future<TemperatureExcursion?> _excursionById(
    DatabaseExecutor db,
    int id,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'temperature_excursions',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _excursionFromRow(rows.single);
  }

  Future<ExcursionAction?> _actionById(DatabaseExecutor db, int id) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      $_actionSelect
      WHERE excursion_actions.id = ?
      LIMIT 1
      ''',
      <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _actionFromRow(rows.single);
  }

  DemoScenario _scenarioFromRow(Map<String, Object?> row) {
    return DemoScenario(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      type: row['scenario_type']! as String,
      phase: row['phase']! as String,
      startedAt: DateTime.parse(row['started_at']! as String),
      endedAt: _parseDate(row['ended_at']),
      startedByUserId: row['started_by_user_id']! as int,
      holdSamples: _asInt(row['hold_samples']),
      triggerSource:
          (row['trigger_source'] as String?) ?? DemoScenario.manualTrigger,
    );
  }

  TemperatureExcursion _excursionFromRow(Map<String, Object?> row) {
    return TemperatureExcursion(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      direction: row['direction']! as String,
      startedAt: DateTime.parse(row['started_at']! as String),
      lastOutOfRangeAt: DateTime.parse(row['last_out_of_range_at']! as String),
      recoveredAt: _parseDate(row['recovered_at']),
      minTemperature: _asDouble(row['min_temperature'])!,
      maxTemperature: _asDouble(row['max_temperature'])!,
      dataGapDetected: _asInt(row['data_gap_detected']) == 1,
      status: row['status']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  ExcursionAction _actionFromRow(Map<String, Object?> row) {
    final Object? reportedTo = row['reported_to'];
    final Object? note = row['note'];
    final Object? excursionId = row['excursion_id'];
    return ExcursionAction(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      excursionId: excursionId is int ? excursionId : null,
      authorUserId: row['author_user_id']! as int,
      authorLoginId: row['author_login_id']! as String,
      causeCategory: row['cause_category']! as String,
      causeCertainty: row['cause_certainty']! as String,
      description: row['description']! as String,
      discoveredAt: _parseDate(row['discovered_at']),
      responseStartedAt: _parseDate(row['response_started_at']),
      actionTaken: row['action_taken']! as String,
      reportedTo: reportedTo is String && reportedTo.isNotEmpty
          ? reportedTo
          : null,
      reportedAt: _parseDate(row['reported_at']),
      note: note is String && note.isNotEmpty ? note : null,
      createdAt: DateTime.parse(row['created_at']! as String),
      situationType: row['situation_type'] as String?,
      responsibleContacted: _optionalFlagFrom(row['responsible_contacted']),
      holdGuidanceGiven: _optionalFlagFrom(row['hold_guidance_given']),
      holdActionCompleted: _optionalFlagFrom(row['hold_action_completed']),
    );
  }

  bool? _optionalFlagFrom(Object? value) {
    if (value == null) {
      return null;
    }
    return value == 1;
  }

  QualityReview _reviewFromRow(Map<String, Object?> row) {
    return QualityReview(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      reviewerUserId: row['reviewer_user_id']! as int,
      reviewerLoginId: row['reviewer_login_id']! as String,
      status: QualityReviewStatus.fromStorage(row['review_status']! as String),
      comment: row['review_comment']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  Future<ShipmentRelease?> _releaseById(DatabaseExecutor db, int id) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      $_releaseSelect
      WHERE shipment_releases.id = ?
      LIMIT 1
      ''',
      <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _releaseFromRow(rows.single);
  }

  Future<ShipmentReceipt?> _receiptById(DatabaseExecutor db, int id) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      $_receiptSelect
      WHERE shipment_receipts.id = ?
      LIMIT 1
      ''',
      <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _receiptFromRow(rows.single);
  }

  ShipmentRelease _releaseFromRow(Map<String, Object?> row) {
    return ShipmentRelease(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      confirmedByUserId: row['confirmed_by_user_id']! as int,
      confirmedByLoginId: row['confirmed_by_login_id']! as String,
      confirmedAt: DateTime.parse(row['confirmed_at']! as String),
      note: _optionalText(row['note']),
    );
  }

  ShipmentReceipt _receiptFromRow(Map<String, Object?> row) {
    return ShipmentReceipt(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      receiverUserId: row['receiver_user_id']! as int,
      receiverLoginId: row['receiver_login_id']! as String,
      receivedQuantity: _asInt(row['received_quantity']),
      packageCondition: row['package_condition']! as String,
      note: _optionalText(row['receipt_note']),
      receivedAt: DateTime.parse(row['received_at']! as String),
    );
  }

  String? _blankToNull(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  Future<ShipmentRecord> _requireTransportShipment(
    DatabaseExecutor db, {
    required int actorUserId,
    required int shipmentId,
    required String action,
  }) async {
    final AppUser? actor = await _userById(db, actorUserId);
    if (actor == null || actor.role != UserRole.transporter) {
      throw TransportException('현재 담당 운송자만 운송을 $action할 수 있습니다.');
    }
    final ShipmentRecord? shipment = await _findShipment(db, shipmentId);
    if (shipment == null) {
      throw const TransportException('운송 건을 찾을 수 없습니다.');
    }
    if (shipment.assigneeUserId != actor.id) {
      throw TransportException('현재 담당 운송자만 운송을 $action할 수 있습니다.');
    }
    return shipment;
  }

  Future<ShipmentRecord?> _findShipment(
    DatabaseExecutor db,
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'shipments',
      where: 'id = ?',
      whereArgs: <Object>[shipmentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _shipmentFromRow(rows.single);
  }

  Future<TemperatureReading?> _latestTemperature(
    DatabaseExecutor db,
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'temperature_readings',
      where: 'shipment_id = ?',
      whereArgs: <Object>[shipmentId],
      orderBy: 'measured_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _temperatureFromRow(rows.single);
  }

  Future<TemperatureReading> _insertTemperature(
    DatabaseExecutor db, {
    required int shipmentId,
    required double celsius,
    required DateTime at,
    required int assigneeUserId,
    required double boundsMin,
    required double boundsMax,
  }) async {
    final TemperatureReading? previous = await _latestTemperature(
      db,
      shipmentId,
    );
    final String stamp = at.toUtc().toIso8601String();
    final int id = await db.insert('temperature_readings', <String, Object?>{
      'shipment_id': shipmentId,
      'temperature_c': celsius,
      'measured_at': stamp,
      'recorded_at': stamp,
      'source': TemperatureReading.demoVirtualSource,
      'assignee_user_id': assigneeUserId,
    });
    final TemperatureReading reading = TemperatureReading(
      id: id,
      shipmentId: shipmentId,
      celsius: celsius,
      measuredAt: at.toUtc(),
      recordedAt: at.toUtc(),
      source: TemperatureReading.demoVirtualSource,
      assigneeUserId: assigneeUserId,
    );
    await _syncExcursion(
      db,
      reading: reading,
      previous: previous,
      min: boundsMin,
      max: boundsMax,
    );
    return reading;
  }

  Future<void> _syncExcursion(
    DatabaseExecutor db, {
    required TemperatureReading reading,
    required TemperatureReading? previous,
    required double min,
    required double max,
  }) async {
    final String? direction = reading.celsius > max
        ? TemperatureExcursion.aboveMax
        : reading.celsius < min
        ? TemperatureExcursion.belowMin
        : null;
    final TemperatureExcursion? open = await _openExcursion(
      db,
      reading.shipmentId,
    );
    final String stamp = reading.measuredAt.toUtc().toIso8601String();
    final bool gap =
        previous != null &&
        reading.measuredAt.toUtc().difference(previous.measuredAt.toUtc()) >
            TemperatureExcursion.gapAfter;
    if (direction == null) {
      if (open == null) {
        return;
      }
      await db.update(
        'temperature_excursions',
        <String, Object?>{
          'status': TemperatureExcursion.recoveredStatus,
          'recovered_at': stamp,
          'data_gap_detected': (open.dataGapDetected || gap) ? 1 : 0,
          'updated_at': stamp,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object>[open.id, TemperatureExcursion.openStatus],
      );
      return;
    }
    if (open == null) {
      await db.insert('temperature_excursions', <String, Object?>{
        'shipment_id': reading.shipmentId,
        'direction': direction,
        'started_at': stamp,
        'last_out_of_range_at': stamp,
        'min_temperature': reading.celsius,
        'max_temperature': reading.celsius,
        'data_gap_detected': 0,
        'status': TemperatureExcursion.openStatus,
        'created_at': stamp,
        'updated_at': stamp,
      });
      return;
    }
    if (open.direction != direction) {
      await db.update(
        'temperature_excursions',
        <String, Object?>{
          'status': TemperatureExcursion.recoveredStatus,
          'data_gap_detected': 1,
          'updated_at': stamp,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object>[open.id, TemperatureExcursion.openStatus],
      );
      await db.insert('temperature_excursions', <String, Object?>{
        'shipment_id': reading.shipmentId,
        'direction': direction,
        'started_at': stamp,
        'last_out_of_range_at': stamp,
        'min_temperature': reading.celsius,
        'max_temperature': reading.celsius,
        'data_gap_detected': 0,
        'status': TemperatureExcursion.openStatus,
        'created_at': stamp,
        'updated_at': stamp,
      });
      return;
    }
    await db.update(
      'temperature_excursions',
      <String, Object?>{
        'last_out_of_range_at': stamp,
        'min_temperature': open.minTemperature < reading.celsius
            ? open.minTemperature
            : reading.celsius,
        'max_temperature': open.maxTemperature > reading.celsius
            ? open.maxTemperature
            : reading.celsius,
        'data_gap_detected': (open.dataGapDetected || gap) ? 1 : 0,
        'updated_at': stamp,
      },
      where: 'id = ? AND status = ?',
      whereArgs: <Object>[open.id, TemperatureExcursion.openStatus],
    );
  }

  TemperatureReading _temperatureFromRow(Map<String, Object?> row) {
    return TemperatureReading(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      celsius: _asDouble(row['temperature_c'])!,
      measuredAt: DateTime.parse(row['measured_at']! as String),
      recordedAt: DateTime.parse(row['recorded_at']! as String),
      source: row['source']! as String,
      assigneeUserId: row['assignee_user_id']! as int,
    );
  }

  Future<AppUser> _requireTransporter(DatabaseExecutor db, int userId) async {
    final AppUser? user = await _userById(db, userId);
    if (user == null) {
      throw const TransferException('계정을 찾을 수 없습니다.');
    }
    if (user.role != UserRole.transporter) {
      throw const TransferException('운송자 계정만 인수인계할 수 있습니다.');
    }
    return user;
  }

  Future<AppUser> _requireRecipient(
    DatabaseExecutor db, {
    required String toLoginId,
    required int actorId,
  }) async {
    final String loginId = toLoginId.trim();
    if (loginId.isEmpty) {
      throw const TransferException('인수할 운송자를 선택해 주세요.');
    }
    final List<Map<String, Object?>> rows = await db.query(
      'users',
      where: 'login_id = ? COLLATE NOCASE',
      whereArgs: <Object>[loginId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const TransferException('존재하지 않는 계정은 인수자로 지정할 수 없습니다.');
    }
    final AppUser recipient = _userFromRow(rows.single);
    if (recipient.role != UserRole.transporter) {
      throw const TransferException('운송자 역할이 아닌 계정은 인수자로 지정할 수 없습니다.');
    }
    if (recipient.id == actorId) {
      throw const TransferException('본인에게 인수인계를 요청할 수 없습니다.');
    }
    return recipient;
  }

  Future<ShipmentRecord> _requireShipment(
    DatabaseExecutor db,
    int shipmentId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      'shipments',
      where: 'id = ?',
      whereArgs: <Object>[shipmentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const TransferException('운송 건을 찾을 수 없습니다.');
    }
    return _shipmentFromRow(rows.single);
  }

  ShipmentTransfer _transferFromRow(Map<String, Object?> row) {
    final Object? note = row['note'];
    final Object? reason = row['rejection_reason'];
    return ShipmentTransfer(
      id: row['id']! as int,
      shipmentId: row['shipment_id']! as int,
      fromUserId: row['from_user_id']! as int,
      toUserId: row['to_user_id']! as int,
      fromLoginId: row['from_login_id']! as String,
      toLoginId: row['to_login_id']! as String,
      status: TransferStatus.fromStorage(row['status']! as String),
      requestedAt: DateTime.parse(row['requested_at']! as String),
      respondedAt: _parseDate(row['responded_at']),
      location: (row['location'] as String?) ?? '',
      scheduledAt: _parseDate(row['scheduled_at']),
      note: note is String && note.isNotEmpty ? note : null,
      rejectionReason: reason is String && reason.isNotEmpty ? reason : null,
      handoverTempC: _asDouble(row['handover_temp_c']),
      vaccine: row['vaccine']! as String,
      lot: row['lot']! as String,
      shipmentStatus: ShipmentStatus.fromStorage(
        row['shipment_status']! as String,
      ),
    );
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }

  String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
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
    final String targetRange = row['target_range']! as String;
    final TemperatureBounds? parsed = TemperatureBounds.tryParse(targetRange);
    final Object? rawStatus = row['status'];
    return ShipmentRecord(
      id: row['id']! as int,
      ownerUserId: row['owner_user_id']! as int,
      assigneeUserId:
          (row['assignee_user_id'] as int?) ?? row['owner_user_id']! as int,
      participationCode: row['participation_code']! as String,
      vaccine: row['vaccine']! as String,
      manufacturer: row['manufacturer']! as String,
      lot: row['lot']! as String,
      expiryDate: row['expiry_date']! as String,
      quantity: row['quantity']! as int,
      origin: row['origin']! as String,
      destination: row['destination']! as String,
      targetRange: targetRange,
      tempMin: _asDouble(row['temp_min']) ?? parsed?.min,
      tempMax: _asDouble(row['temp_max']) ?? parsed?.max,
      status: rawStatus is String
          ? ShipmentStatus.fromStorage(rawStatus)
          : ShipmentStatus.registered,
      createdAt: DateTime.parse(row['created_at']! as String),
      source: row['source']! as String,
      startedAt: _parseDate(row['started_at']),
      completedAt: _parseDate(row['completed_at']),
      vaccineProductId: row['vaccine_product_id'] as int?,
      storageProfileId: row['vaccine_storage_profile_id'] as int?,
      selectedProductName: _optionalText(row['selected_product_name']),
      selectedManufacturer: _optionalText(row['selected_manufacturer']),
      selectedStorageStage: _optionalText(row['selected_storage_stage']),
      recommendedMin: _asDouble(row['recommended_min_temperature']),
      recommendedMax: _asDouble(row['recommended_max_temperature']),
      actualMin: _asDouble(row['actual_min_temperature']),
      actualMax: _asDouble(row['actual_max_temperature']),
      storageProfileReference: _optionalText(row['storage_profile_reference']),
      handlingNotesSnapshot: _optionalText(row['handling_notes_snapshot']),
      timeLimitNotesSnapshot: _optionalText(row['time_limit_notes_snapshot']),
      demoMode: _optionalText(row['demo_mode']),
      autoGapSkips: _asInt(row['auto_gap_skips']),
      autoCooldownUntilCount: _asInt(row['auto_cooldown_until_count']),
      autoCompletedEvents: _asInt(row['auto_completed_events']),
      releaseRequired: _asInt(row['release_required']) == 1,
    );
  }

  VaccineProduct _productFromRow(Map<String, Object?> row) {
    return VaccineProduct(
      id: row['id']! as int,
      productName: row['product_name']! as String,
      manufacturer: _optionalText(row['manufacturer']),
      vaccineType: _optionalText(row['vaccine_type']),
      authorizationReference: _optionalText(row['authorization_reference']),
      authorizationItemCode: _optionalText(row['authorization_item_code']),
      sourceDocument: _optionalText(row['source_document']),
      sourceUrl: _optionalText(row['source_url']),
      sourceCheckedAt: _optionalText(row['source_checked_at']),
      isActive: (row['is_active'] as int? ?? 0) == 1,
      verificationStatus: StorageVerificationStatus.fromStorage(
        row['verification_status']! as String,
      ),
    );
  }

  VaccineStorageProfile _profileFromRow(Map<String, Object?> row) {
    return VaccineStorageProfile(
      id: row['id']! as int,
      vaccineProductId: row['vaccine_product_id']! as int,
      profileName: row['profile_name']! as String,
      storageStage: row['storage_stage']! as String,
      minTemperature: _asDouble(row['min_temperature'])!,
      maxTemperature: _asDouble(row['max_temperature'])!,
      freezingProhibited: (row['freezing_prohibited'] as int? ?? 0) == 1,
      refreezingProhibited: (row['refreezing_prohibited'] as int? ?? 0) == 1,
      lightProtectionRequired:
          (row['light_protection_required'] as int? ?? 0) == 1,
      handlingNotes: _optionalText(row['handling_notes']),
      timeLimitNotes: _optionalText(row['time_limit_notes']),
      sourceReference: _optionalText(row['source_reference']),
      verificationStatus: StorageVerificationStatus.fromStorage(
        row['verification_status']! as String,
      ),
    );
  }

  String? _optionalText(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  TemperatureBounds? _boundsFromDraft(NewShipment draft, String targetRange) {
    final double? min = draft.tempMin;
    final double? max = draft.tempMax;
    if (min != null || max != null) {
      if (min == null || max == null || min > max) {
        return null;
      }
      return TemperatureBounds(min: min, max: max);
    }
    return TemperatureBounds.tryParse(targetRange);
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value == null) {
      return null;
    }
    return double.tryParse(value.toString());
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
