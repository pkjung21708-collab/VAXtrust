import '../models/excursion_action.dart';
import '../models/quality_review.dart';
import '../models/shipment_receipt.dart';
import '../models/shipment_record.dart';
import '../models/shipment_release.dart';
import '../models/shipment_transfer.dart';
import '../models/temperature_excursion.dart';

/// 전주기 이력의 한 줄입니다. 저장되지 않은 사건은 만들지 않습니다.
class ShipmentHistoryEntry {
  const ShipmentHistoryEntry({
    required this.at,
    required this.title,
    required this.detail,
    required this.order,
  });

  final DateTime at;
  final String title;
  final String detail;

  /// 같은 시각이면 출고보다 운송 시작이 뒤에 오도록 하는 순서입니다.
  final int order;
}

List<ShipmentHistoryEntry> buildShipmentHistory({
  required ShipmentRecord shipment,
  required ShipmentRelease? release,
  required List<ShipmentTransfer> transfers,
  required List<TemperatureExcursion> excursions,
  required List<ExcursionAction> actions,
  required List<QualityReview> reviews,
  required ShipmentReceipt? receipt,
}) {
  final List<ShipmentHistoryEntry> entries = <ShipmentHistoryEntry>[
    ShipmentHistoryEntry(
      at: shipment.createdAt,
      title: '운송 건 등록',
      detail:
          '${shipment.vaccine} · LOT ${shipment.lot} · ${shipment.quantity}개',
      order: 10,
    ),
  ];
  final ShipmentRelease? confirmed = release;
  if (confirmed != null) {
    final String note = confirmed.note ?? '메모 없음';
    entries.add(
      ShipmentHistoryEntry(
        at: confirmed.confirmedAt,
        title: '출고 확인',
        detail: '${confirmed.confirmedByLoginId} · $note',
        order: 20,
      ),
    );
  }
  final DateTime? startedAt = shipment.startedAt;
  if (startedAt != null) {
    entries.add(
      ShipmentHistoryEntry(
        at: startedAt,
        title: '운송 시작',
        detail: '온도 기록 생성을 시작했습니다.',
        order: 30,
      ),
    );
  }
  for (final ShipmentTransfer transfer in transfers) {
    if (transfer.status == TransferStatus.cancelled) {
      continue;
    }
    entries.add(
      ShipmentHistoryEntry(
        at: transfer.respondedAt ?? transfer.requestedAt,
        title: '운송자 인수인계',
        detail:
            '${transfer.fromLoginId} → ${transfer.toLoginId} · ${transfer.status.label}',
        order: 40,
      ),
    );
  }
  for (final TemperatureExcursion excursion in excursions) {
    entries.add(
      ShipmentHistoryEntry(
        at: excursion.startedAt,
        title: excursion.isAbove ? '고온 이탈 감지' : '저온 이탈 감지',
        detail:
            '최저 ${excursion.minTemperature}°C · 최고 ${excursion.maxTemperature}°C',
        order: 50,
      ),
    );
    final DateTime? recoveredAt = excursion.recoveredAt;
    if (recoveredAt != null) {
      entries.add(
        ShipmentHistoryEntry(
          at: recoveredAt,
          title: '정상 온도 복귀',
          detail: excursion.directionLabel,
          order: 60,
        ),
      );
    }
  }
  for (final ExcursionAction action in actions) {
    entries.add(
      ShipmentHistoryEntry(
        at: action.createdAt,
        title: '운송자 대응 기록',
        detail: action.actionTaken,
        order: 70,
      ),
    );
  }
  final DateTime? completedAt = shipment.completedAt;
  if (completedAt != null) {
    entries.add(
      ShipmentHistoryEntry(
        at: completedAt,
        title: '운송 완료',
        detail: '온도 생성을 멈췄습니다. 의료기관 인수와는 별개입니다.',
        order: 80,
      ),
    );
  }
  for (final QualityReview review in reviews) {
    entries.add(
      ShipmentHistoryEntry(
        at: review.createdAt,
        title: review.status == QualityReviewStatus.reviewCompleted
            ? '품질 검토 완료'
            : '품질 검토 · ${review.status.label}',
        detail: review.comment.isEmpty
            ? review.status.medicalMessage
            : review.comment,
        order: 90,
      ),
    );
  }
  final ShipmentReceipt? received = receipt;
  if (received != null) {
    entries.add(
      ShipmentHistoryEntry(
        at: received.receivedAt,
        title: '의료기관 인수',
        detail:
            '도착 ${received.receivedQuantity}개 · ${received.packageLabel} · 물품 수령이며 사용 승인이 아닙니다.',
        order: 100,
      ),
    );
  }
  entries.sort((ShipmentHistoryEntry a, ShipmentHistoryEntry b) {
    final int byTime = a.at.compareTo(b.at);
    if (byTime != 0) {
      return byTime;
    }
    return a.order.compareTo(b.order);
  });
  return entries;
}

String historyClock(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
