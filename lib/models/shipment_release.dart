/// 운송 시작과 별도로 남기는 출고 확인 기록입니다.
/// 한 운송 건에 하나만 두고, 만든 뒤에는 고치거나 지우지 않습니다.
class ShipmentRelease {
  const ShipmentRelease({
    required this.id,
    required this.shipmentId,
    required this.confirmedByUserId,
    required this.confirmedByLoginId,
    required this.confirmedAt,
    required this.note,
  });

  final int id;
  final int shipmentId;
  final int confirmedByUserId;
  final String confirmedByLoginId;
  final DateTime confirmedAt;
  final String? note;
}
