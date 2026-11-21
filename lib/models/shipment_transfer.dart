import 'shipment_record.dart';

/// 인수인계 요청의 처리 상태입니다. 기록은 지우지 않고 상태만 바꿉니다.
enum TransferStatus {
  requested,
  accepted,
  rejected,
  cancelled;

  String get storageValue => switch (this) {
    TransferStatus.requested => 'requested',
    TransferStatus.accepted => 'accepted',
    TransferStatus.rejected => 'rejected',
    TransferStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    TransferStatus.requested => '요청됨',
    TransferStatus.accepted => '수락',
    TransferStatus.rejected => '거절',
    TransferStatus.cancelled => '취소',
  };

  static TransferStatus fromStorage(String value) {
    for (final TransferStatus status in TransferStatus.values) {
      if (status.storageValue == value) {
        return status;
      }
    }
    throw FormatException('저장할 수 없는 인수인계 상태입니다: $value');
  }
}

/// 운송자 사이의 인수인계 한 건입니다.
///
/// [handoverTempC]는 이후 온도 기록을 연결하기 위한 자리입니다.
/// 이번 단계에서는 측정값이 없으므로 항상 비워 둡니다.
class ShipmentTransfer {
  const ShipmentTransfer({
    required this.id,
    required this.shipmentId,
    required this.fromUserId,
    required this.toUserId,
    required this.fromLoginId,
    required this.toLoginId,
    required this.status,
    required this.requestedAt,
    required this.respondedAt,
    required this.location,
    required this.scheduledAt,
    required this.note,
    required this.rejectionReason,
    required this.handoverTempC,
    required this.vaccine,
    required this.lot,
    required this.shipmentStatus,
  });

  final int id;
  final int shipmentId;
  final int fromUserId;
  final int toUserId;
  final String fromLoginId;
  final String toLoginId;
  final TransferStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;
  final String location;
  final DateTime? scheduledAt;
  final String? note;
  final String? rejectionReason;

  /// 인계 당시 측정 온도. 온도 기능 전에는 null입니다.
  final double? handoverTempC;
  final String vaccine;
  final String lot;
  final ShipmentStatus shipmentStatus;

  String get shipmentDisplayId => ShipmentRecord.displayIdFor(shipmentId);

  bool get isOpen => status == TransferStatus.requested;
}

/// 인수인계 시각을 화면용으로 바꿉니다. 값이 없으면 미정입니다.
String formatHandoverTime(DateTime? value) {
  if (value == null) {
    return '미정';
  }
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
