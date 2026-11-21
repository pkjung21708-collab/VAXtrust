/// 의료기관이 물품을 수령했다는 기록입니다.
/// 품질 적합, 사용 승인, 접종 가능 판정이 아닙니다.
class PackageCondition {
  const PackageCondition._();

  static const String intact = 'intact';
  static const String suspectedDamage = 'suspected_damage';
  static const String needsCheck = 'needs_check';

  static const List<String> values = <String>[
    intact,
    suspectedDamage,
    needsCheck,
  ];

  static bool isKnown(String value) => values.contains(value);

  static String label(String value) => switch (value) {
    intact => '이상 없음',
    suspectedDamage => '손상 의심',
    needsCheck => '확인 필요',
    _ => '확인 필요',
  };
}

class ShipmentReceipt {
  const ShipmentReceipt({
    required this.id,
    required this.shipmentId,
    required this.receiverUserId,
    required this.receiverLoginId,
    required this.receivedQuantity,
    required this.packageCondition,
    required this.note,
    required this.receivedAt,
  });

  final int id;
  final int shipmentId;
  final int receiverUserId;
  final String receiverLoginId;
  final int receivedQuantity;
  final String packageCondition;
  final String? note;
  final DateTime receivedAt;

  bool quantityDiffersFrom(int shippedQuantity) =>
      receivedQuantity != shippedQuantity;

  bool needsSeparateCheck(int shippedQuantity) =>
      quantityDiffersFrom(shippedQuantity) ||
      packageCondition != PackageCondition.intact;

  String get packageLabel => PackageCondition.label(packageCondition);
}
