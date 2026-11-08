/// 운송자가 입력한 운송 건입니다.
/// 측정 온도, 적합도, 투여 가능 여부는 저장하지 않습니다.
class ShipmentRecord {
  const ShipmentRecord({
    required this.id,
    required this.ownerUserId,
    required this.participationCode,
    required this.vaccine,
    required this.manufacturer,
    required this.lot,
    required this.expiryDate,
    required this.quantity,
    required this.origin,
    required this.destination,
    required this.targetRange,
    required this.createdAt,
    required this.source,
  });

  /// 사용자가 앱에 입력한 데이터라는 표시입니다.
  /// 시뮬레이션 목록은 이 값으로 저장하지 않습니다.
  static const String userInputSource = 'user_input';

  final int id;
  final int ownerUserId;
  final String participationCode;
  final String vaccine;
  final String manufacturer;
  final String lot;
  final String expiryDate;
  final int quantity;
  final String origin;
  final String destination;

  /// 등록 화면에서 고른 예시 보관 범위입니다. 측정된 온도가 아닙니다.
  final String targetRange;
  final DateTime createdAt;
  final String source;
}

/// 운송 건을 등록할 때 넣는 입력값입니다.
class NewShipment {
  const NewShipment({
    required this.vaccine,
    required this.manufacturer,
    required this.lot,
    required this.expiryDate,
    required this.quantity,
    required this.origin,
    required this.destination,
    required this.targetRange,
  });

  final String vaccine;
  final String manufacturer;
  final String lot;
  final String expiryDate;
  final int quantity;
  final String origin;
  final String destination;
  final String targetRange;
}
