import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/shipment_history.dart';
import 'package:vaxtrust/data/temperature_policy.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/quality_review.dart';
import 'package:vaxtrust/models/shipment_receipt.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/shipment_release.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/widgets/shipment_custody_panels.dart';

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_custody_');
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
    vaccine: '스카이셀플루4가프리필드시린지',
    manufacturer: '에스케이바이오사이언스(주)',
    lot: 'LOT-PHASE9',
    expiryDate: '2027-11-21',
    quantity: 10,
    origin: '창고',
    destination: '병원',
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

  test('신규 운송은 출고 확인과 운송 시작이 분리된다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final AppUser quality = await user('quality', UserRole.qualityManager);
    final ShipmentRecord created = await database.createShipment(
      ownerUserId: courier.id,
      draft: draft,
      releaseRequired: true,
    );
    expect(created.status, ShipmentStatus.registered);
    expect(created.releaseRequired, isTrue);
    expect(
      () => database.startTransport(
        actorUserId: courier.id,
        shipmentId: created.id,
      ),
      throwsA(isA<TransportException>()),
    );
    expect(created.status, ShipmentStatus.registered);

    final ShipmentRecord joined = (await database.joinByParticipationCode(
      userId: quality.id,
      code: created.participationCode,
    ))!.shipment;
    expect(
      () => database.confirmRelease(
        actorUserId: quality.id,
        shipmentId: joined.id,
        note: '품질은 출고할 수 없음',
      ),
      throwsA(isA<CustodyException>()),
    );

    final ShipmentRelease release = await database.confirmRelease(
      actorUserId: courier.id,
      shipmentId: created.id,
      note: '냉장 포장 확인',
    );
    expect(release.confirmedByUserId, courier.id);
    expect(release.note, '냉장 포장 확인');
    expect(release.confirmedAt, isNotNull);
    final ShipmentRecord stillRegistered = (await database.shipmentVisibleTo(
      userId: courier.id,
      shipmentId: created.id,
    ))!;
    expect(stillRegistered.status, ShipmentStatus.registered);
    expect(stillRegistered.startedAt, isNull);
    expect(
      () => database.confirmRelease(
        actorUserId: courier.id,
        shipmentId: created.id,
      ),
      throwsA(isA<CustodyException>()),
    );

    final ShipmentRecord started = await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    expect(started.status, ShipmentStatus.inTransit);
    expect(
      (await database.releaseFor(
        userId: courier.id,
        shipmentId: created.id,
      ))!.id,
      release.id,
    );
  });

  test('기존 운송 건은 출고 확인 없이도 시작하고 기록을 만들지 않는다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final ShipmentRecord created = await database.createShipment(
      ownerUserId: courier.id,
      draft: draft,
    );
    expect(created.releaseRequired, isFalse);
    final ShipmentRecord started = await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    expect(started.status, ShipmentStatus.inTransit);
    expect(
      await database.releaseFor(userId: courier.id, shipmentId: created.id),
      isNull,
    );
    final List<ShipmentHistoryEntry> history = buildShipmentHistory(
      shipment: started,
      release: null,
      transfers: const [],
      excursions: const [],
      actions: const [],
      reviews: const [],
      receipt: null,
    );
    expect(
      history.map((ShipmentHistoryEntry entry) => entry.title),
      isNot(contains('출고 확인')),
    );
    expect(history.first.title, '운송 건 등록');
    expect(history.last.title, '운송 시작');
  });

  test('완료된 운송만 인수하고 수량 차이와 검토 상태를 유지한다', () async {
    final AppUser courier = await user('courier', UserRole.transporter);
    final AppUser quality = await user('quality', UserRole.qualityManager);
    final AppUser medical = await user('medical', UserRole.medicalStaff);
    final AppUser outsider = await user('other-medical', UserRole.medicalStaff);
    final ShipmentRecord created = await database.createShipment(
      ownerUserId: courier.id,
      draft: draft,
      releaseRequired: true,
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
      () => database.confirmReceipt(
        actorUserId: medical.id,
        shipmentId: created.id,
        receivedQuantity: 10,
        packageCondition: PackageCondition.intact,
      ),
      throwsA(isA<CustodyException>()),
    );
    await database.confirmRelease(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    await database.startTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    final int readings = await database.temperatureCount(created.id);
    final ShipmentRecord completed = await database.completeTransport(
      actorUserId: courier.id,
      shipmentId: created.id,
    );
    expect(completed.status, ShipmentStatus.completed);
    expect(
      await database.recordDemoSample(
        shipmentId: created.id,
        at: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        policy: InRangeTemperaturePolicy(),
      ),
      isNull,
    );
    expect(await database.temperatureCount(created.id), readings);

    final QualityReview held = await database.saveQualityReview(
      actorUserId: quality.id,
      shipmentId: created.id,
      status: QualityReviewStatus.onHold,
      comment: '추가 온도 확인',
    );
    expect(
      () => database.confirmReceipt(
        actorUserId: courier.id,
        shipmentId: created.id,
        receivedQuantity: 9,
        packageCondition: PackageCondition.intact,
      ),
      throwsA(isA<CustodyException>()),
    );
    expect(
      () => database.confirmReceipt(
        actorUserId: quality.id,
        shipmentId: created.id,
        receivedQuantity: 9,
        packageCondition: PackageCondition.intact,
      ),
      throwsA(isA<CustodyException>()),
    );
    expect(
      () => database.confirmReceipt(
        actorUserId: outsider.id,
        shipmentId: created.id,
        receivedQuantity: 9,
        packageCondition: PackageCondition.intact,
      ),
      throwsA(isA<CustodyException>()),
    );

    final ShipmentReceipt receipt = await database.confirmReceipt(
      actorUserId: medical.id,
      shipmentId: created.id,
      receivedQuantity: 9,
      packageCondition: PackageCondition.suspectedDamage,
      note: '한 상자 파손 의심',
    );
    expect(receipt.receiverUserId, medical.id);
    expect(receipt.receivedQuantity, 9);
    expect(receipt.packageCondition, PackageCondition.suspectedDamage);
    expect(receipt.quantityDiffersFrom(created.quantity), isTrue);
    expect(receipt.needsSeparateCheck(created.quantity), isTrue);
    final ShipmentRecord after = (await database.shipmentVisibleTo(
      userId: medical.id,
      shipmentId: created.id,
    ))!;
    expect(after.status, ShipmentStatus.completed);
    expect(after.quantity, 10);
    final List<QualityReview> reviews = await database.qualityReviewsFor(
      userId: quality.id,
      shipmentId: created.id,
    );
    expect(reviews.single.id, held.id);
    expect(reviews.single.status, QualityReviewStatus.onHold);
    expect(
      () => database.confirmReceipt(
        actorUserId: medical.id,
        shipmentId: created.id,
        receivedQuantity: 10,
        packageCondition: PackageCondition.intact,
      ),
      throwsA(isA<CustodyException>()),
    );

    final List<ShipmentHistoryEntry> history = buildShipmentHistory(
      shipment: after,
      release: await database.releaseFor(
        userId: medical.id,
        shipmentId: created.id,
      ),
      transfers: const [],
      excursions: const [],
      actions: const [],
      reviews: reviews,
      receipt: receipt,
    );
    expect(
      history.map((ShipmentHistoryEntry entry) => entry.title).toList(),
      <String>[
        '운송 건 등록',
        '출고 확인',
        '운송 시작',
        '운송 완료',
        '품질 검토 · 사용 보류',
        '의료기관 인수',
      ],
    );
    expect(
      history.any((ShipmentHistoryEntry entry) => entry.title.contains('승인')),
      isFalse,
    );
    expect(await database.userVersion(), 11);
  });

  testWidgets('인수 화면은 수량 차이와 사용 승인 아님을 보여 준다', (tester) async {
    final DateTime at = DateTime.utc(2026, 11, 21, 2, 50);
    final AppUser medical = AppUser(
      id: 3,
      loginId: 'medical',
      role: UserRole.medicalStaff,
      createdAt: at,
    );
    final ShipmentRecord shipment = ShipmentRecord(
      id: 9,
      ownerUserId: 1,
      assigneeUserId: 1,
      participationCode: 'VX-TEST',
      vaccine: '스카이셀플루4가프리필드시린지',
      manufacturer: '에스케이바이오사이언스(주)',
      lot: 'LOT-UI',
      expiryDate: '2027-11-21',
      quantity: 10,
      origin: '창고',
      destination: '병원',
      targetRange: '2 ~ 8°C',
      tempMin: 2,
      tempMax: 8,
      status: ShipmentStatus.completed,
      createdAt: at,
      source: ShipmentRecord.userInputSource,
      completedAt: at,
    );
    final ShipmentReceipt receipt = ShipmentReceipt(
      id: 1,
      shipmentId: 9,
      receiverUserId: 3,
      receiverLoginId: 'medical',
      receivedQuantity: 8,
      packageCondition: PackageCondition.needsCheck,
      note: '수량 확인',
      receivedAt: at,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShipmentReceiptPanel(
            user: medical,
            shipment: shipment,
            receipt: receipt,
            reviews: const <QualityReview>[],
            excursions: const [],
            actions: const [],
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.text('출고 수량과 도착 수량이 일치하지 않습니다.'), findsOneWidget);
    expect(find.textContaining('사용 승인'), findsOneWidget);
    expect(find.text('접종 가능'), findsNothing);
    expect(find.byKey(const Key('confirm-receipt')), findsNothing);
    expect(find.text('검토 전'), findsOneWidget);
  });
}
