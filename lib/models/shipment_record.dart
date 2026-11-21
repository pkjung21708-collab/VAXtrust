import 'vaccine_product.dart';

/// 운송 건의 진행 상태입니다.
/// 등록과 운송 시작, 운송 완료는 서로 다른 상태입니다.
enum ShipmentStatus {
  registered,
  inTransit,
  completed;

  static const String registeredStorage = 'registered';
  static const String inTransitStorage = 'in_transit';
  static const String completedStorage = 'completed';

  String get storageValue => switch (this) {
    ShipmentStatus.registered => registeredStorage,
    ShipmentStatus.inTransit => inTransitStorage,
    ShipmentStatus.completed => completedStorage,
  };

  String get label => switch (this) {
    ShipmentStatus.registered => '등록됨',
    ShipmentStatus.inTransit => '운송 중',
    ShipmentStatus.completed => '운송 완료',
  };

  static ShipmentStatus fromStorage(String value) {
    for (final ShipmentStatus status in ShipmentStatus.values) {
      if (status.storageValue == value) {
        return status;
      }
    }
    throw FormatException('저장할 수 없는 운송 상태입니다: $value');
  }
}

/// 설정 온도의 하한과 상한입니다. 측정된 온도가 아닙니다.
class TemperatureBounds {
  const TemperatureBounds({required this.min, required this.max});

  static final RegExp _pattern = RegExp(
    r'(-?\d+(?:\.\d+)?)\s*[~～]\s*(-?\d+(?:\.\d+)?)',
  );

  final double min;
  final double max;

  static TemperatureBounds? tryParse(String value) {
    final RegExpMatch? match = _pattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final double? min = double.tryParse(match.group(1)!);
    final double? max = double.tryParse(match.group(2)!);
    if (min == null || max == null || min > max) {
      return null;
    }
    return TemperatureBounds(min: min, max: max);
  }

  static String formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }

  static String formatCelsius(double value) => '${formatNumber(value)}°C';

  String get label => '${formatNumber(min)} ~ ${formatNumber(max)}°C';
}

/// 운송자가 입력한 운송 건입니다.
/// 측정 온도는 이 행에 넣지 않고 별도 온도 기록으로 저장합니다.
/// 적합도와 투여 가능 여부는 저장하지 않습니다.
class ShipmentRecord {
  const ShipmentRecord({
    required this.id,
    required this.ownerUserId,
    required this.assigneeUserId,
    required this.participationCode,
    required this.vaccine,
    required this.manufacturer,
    required this.lot,
    required this.expiryDate,
    required this.quantity,
    required this.origin,
    required this.destination,
    required this.targetRange,
    required this.tempMin,
    required this.tempMax,
    required this.status,
    required this.createdAt,
    required this.source,
    this.startedAt,
    this.completedAt,
    this.vaccineProductId,
    this.storageProfileId,
    this.selectedProductName,
    this.selectedManufacturer,
    this.selectedStorageStage,
    this.recommendedMin,
    this.recommendedMax,
    this.actualMin,
    this.actualMax,
    this.storageProfileReference,
    this.handlingNotesSnapshot,
    this.timeLimitNotesSnapshot,
    this.demoMode,
    this.autoGapSkips = 0,
    this.autoCooldownUntilCount = 0,
    this.autoCompletedEvents = 0,
    this.releaseRequired = false,
  });

  /// 사용자가 앱에 입력한 데이터라는 표시입니다.
  /// 시뮬레이션 목록은 이 값으로 저장하지 않습니다.
  static const String userInputSource = 'user_input';

  /// 화면에 보여주는 운송 건 ID입니다. 참여 코드(VX-)와 다른 형식입니다.
  static String displayIdFor(int id) => 'VT-${id.toString().padLeft(5, '0')}';

  final int id;
  final int ownerUserId;

  /// 현재 담당 운송자입니다. 인수인계 전에는 등록한 운송자와 같습니다.
  final int assigneeUserId;
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
  final double? tempMin;
  final double? tempMax;
  final ShipmentStatus status;
  final DateTime createdAt;
  final String source;

  /// 담당 운송자가 운송 시작을 누른 시각입니다.
  final DateTime? startedAt;

  /// 담당 운송자가 운송 완료를 누른 시각입니다.
  final DateTime? completedAt;

  /// 등록 당시 백신 목록의 제품입니다. 예전 수동 등록 건은 비어 있습니다.
  final int? vaccineProductId;
  final int? storageProfileId;
  final String? selectedProductName;
  final String? selectedManufacturer;
  final String? selectedStorageStage;
  final double? recommendedMin;
  final double? recommendedMax;

  /// 이탈 감지에 쓰는 적용 범위의 사본입니다. 측정은 tempMin, tempMax를 봅니다.
  final double? actualMin;
  final double? actualMax;
  final String? storageProfileReference;
  final String? handlingNotesSnapshot;
  final String? timeLimitNotesSnapshot;

  /// null이면 기존 수동 시연입니다. probabilistic, presentation만 자동입니다.
  final String? demoMode;

  /// 자동 데이터 공백으로 아직 건너뛸 측정 횟수입니다.
  final int autoGapSkips;

  /// 이 측정 개수 전에는 다음 자동 이상을 시작하지 않습니다.
  final int autoCooldownUntilCount;

  /// 이미 끝난 자동 이상 상황의 개수입니다. 발표용 순서를 이어 가는 데 씁니다.
  final int autoCompletedEvents;

  /// 이번 등록 화면에서 만든 운송 건은 출고 확인 뒤에만 운송을 시작합니다.
  /// 예전 운송 건은 false이며, 출고 기록을 소급해서 요구하지 않습니다.
  final bool releaseRequired;

  String get displayId => displayIdFor(id);

  /// 백신 목록에 연결하지 않은 기존 운송 건입니다.
  bool get isLegacyManualRegistration => vaccineProductId == null;

  String get temperatureRangeLabel {
    final double? min = tempMin;
    final double? max = tempMax;
    if (min == null || max == null) {
      return targetRange;
    }
    return TemperatureBounds(min: min, max: max).label;
  }

  String? get recommendedRangeLabel {
    final double? min = recommendedMin;
    final double? max = recommendedMax;
    if (min == null || max == null) {
      return null;
    }
    return TemperatureBounds(min: min, max: max).label;
  }

  bool get appliedRangeDiffersFromRecommendation {
    final double? recommendedLow = recommendedMin;
    final double? recommendedHigh = recommendedMax;
    final double? appliedLow = tempMin;
    final double? appliedHigh = tempMax;
    if (recommendedLow == null ||
        recommendedHigh == null ||
        appliedLow == null ||
        appliedHigh == null) {
      return false;
    }
    return temperatureRangesDiffer(
      recommendedMin: recommendedLow,
      recommendedMax: recommendedHigh,
      actualMin: appliedLow,
      actualMax: appliedHigh,
    );
  }
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
    this.tempMin,
    this.tempMax,
    this.vaccineProductId,
    this.storageProfileId,
  });

  final String vaccine;
  final String manufacturer;
  final String lot;
  final String expiryDate;
  final int quantity;
  final String origin;
  final String destination;
  final String targetRange;
  final double? tempMin;
  final double? tempMax;
  final int? vaccineProductId;
  final int? storageProfileId;
}
