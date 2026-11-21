/// 백신 제품과 보관 단계입니다.
/// 제품명만으로 온도를 정하지 않고, 보관 프로필을 따로 둡니다.
enum StorageVerificationStatus {
  verified,
  verificationRequired,
  outdated;

  static const String verifiedStorage = 'verified';
  static const String verificationRequiredStorage = 'verification_required';
  static const String outdatedStorage = 'outdated';

  String get storageValue => switch (this) {
    StorageVerificationStatus.verified => verifiedStorage,
    StorageVerificationStatus.verificationRequired =>
      verificationRequiredStorage,
    StorageVerificationStatus.outdated => outdatedStorage,
  };

  String get label => switch (this) {
    StorageVerificationStatus.verified => '공식 자료 대조 완료',
    StorageVerificationStatus.verificationRequired => '추가 확인 필요',
    StorageVerificationStatus.outdated => '최신 정보 재확인 필요',
  };

  static StorageVerificationStatus fromStorage(String value) {
    for (final StorageVerificationStatus status
        in StorageVerificationStatus.values) {
      if (status.storageValue == value) {
        return status;
      }
    }
    throw FormatException('저장할 수 없는 검증 상태입니다: $value');
  }
}

class VaccineProduct {
  const VaccineProduct({
    required this.id,
    required this.productName,
    required this.manufacturer,
    required this.vaccineType,
    required this.authorizationReference,
    required this.authorizationItemCode,
    required this.sourceDocument,
    required this.sourceUrl,
    required this.sourceCheckedAt,
    required this.isActive,
    required this.verificationStatus,
  });

  final int id;
  final String productName;
  final String? manufacturer;
  final String? vaccineType;
  final String? authorizationReference;
  final String? authorizationItemCode;
  final String? sourceDocument;
  final String? sourceUrl;
  final String? sourceCheckedAt;
  final bool isActive;
  final StorageVerificationStatus verificationStatus;

  String get choiceLabel {
    final String? maker = manufacturer;
    if (maker == null || maker.isEmpty) {
      return '$productName · 제조사 미확인';
    }
    return '$productName · $maker';
  }
}

class VaccineStorageProfile {
  const VaccineStorageProfile({
    required this.id,
    required this.vaccineProductId,
    required this.profileName,
    required this.storageStage,
    required this.minTemperature,
    required this.maxTemperature,
    required this.freezingProhibited,
    required this.refreezingProhibited,
    required this.lightProtectionRequired,
    required this.handlingNotes,
    required this.timeLimitNotes,
    required this.sourceReference,
    required this.verificationStatus,
  });

  final int id;
  final int vaccineProductId;
  final String profileName;
  final String storageStage;
  final double minTemperature;
  final double maxTemperature;
  final bool freezingProhibited;
  final bool refreezingProhibited;
  final bool lightProtectionRequired;
  final String? handlingNotes;
  final String? timeLimitNotes;
  final String? sourceReference;
  final StorageVerificationStatus verificationStatus;

  String get rangeLabel =>
      '${_format(minTemperature)} ~ ${_format(maxTemperature)}°C';

  String get choiceLabel => '$profileName · $rangeLabel';

  static String _format(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }
}

/// 권장 범위와 입력 범위가 다른지 소수점 오차만 무시하고 비교합니다.
bool temperatureRangesDiffer({
  required double recommendedMin,
  required double recommendedMax,
  required double actualMin,
  required double actualMax,
}) {
  const double tolerance = 0.001;
  return (recommendedMin - actualMin).abs() > tolerance ||
      (recommendedMax - actualMax).abs() > tolerance;
}

const String temperatureRangeMismatchWarning =
    '선택한 백신의 참고 보관 조건과 입력한 운송 온도 범위가 다릅니다. 적용 조건을 다시 확인해 주세요.';
