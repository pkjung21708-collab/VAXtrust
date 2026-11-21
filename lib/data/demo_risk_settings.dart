/// 시연용 운영 위험도 기준입니다.
///
/// 백신 안정성 자료나 과학적 안전 기준이 아닙니다.
/// 같은 입력이면 항상 같은 수준이 나오도록 숫자만 모아 둡니다.
/// 실제 자료를 받은 뒤에는 이 값만 바꾸면 됩니다.
class DemoRiskSettings {
  const DemoRiskSettings({
    this.minorDeviationCelsius = 1.0,
    this.repeatedExcursionCount = 2,
    this.minimumSamplesForLow = 3,
    this.longObservedDuration = const Duration(seconds: 60),
  });

  static const String title = '시연용 운영 위험도 기준';

  static const String limitation =
      '본 위험 수준은 시연용 온도 이탈 데이터를 기반으로 한 운영 위험 지표이며, 백신의 품질 적합성 또는 접종 가능 여부를 의미하지 않습니다.';

  /// 60초는 시연 화면을 검증하는 임시 기준입니다. 백신 안정성 기준이 아닙니다.
  static const String durationBasis =
      '관측된 이탈 지속시간 60초 이상은 시연 기능을 검증하기 위한 임시 운영 기준이며, 실제 백신 안정성이나 품질 판정 기준이 아닙니다.';

  /// 한 번의 이탈에서 이 값보다 크게 벗어나면 시연 기준의 큰 편차로 봅니다.
  final double minorDeviationCelsius;

  /// 이 횟수 이상이면 반복 이탈로 봅니다.
  final int repeatedExcursionCount;

  /// 이탈이 없을 때 낮음으로 보려면 이 횟수 이상 측정이 있어야 합니다.
  final int minimumSamplesForLow;

  /// 공백 없이 관측된 이탈 시간이 이 값 이상이면 시연 기준의 높음으로 봅니다.
  final Duration longObservedDuration;
}

enum OperationalRiskLevel {
  low,
  caution,
  high,
  unknown;

  String get label => switch (this) {
    OperationalRiskLevel.low => '낮음',
    OperationalRiskLevel.caution => '주의',
    OperationalRiskLevel.high => '높음',
    OperationalRiskLevel.unknown => '평가 불가',
  };
}

enum TemperatureCondition {
  none,
  inRange,
  aboveMax,
  belowMin,
  recovered;

  String get label => switch (this) {
    TemperatureCondition.none => '측정 데이터 없음',
    TemperatureCondition.inRange => '정상 범위',
    TemperatureCondition.aboveMax => '상한 이탈',
    TemperatureCondition.belowMin => '하한 이탈',
    TemperatureCondition.recovered => '정상 범위 복귀',
  };
}

enum QualityReviewState {
  notStarted,
  needed;

  String get label => switch (this) {
    QualityReviewState.notStarted => '검토 전',
    QualityReviewState.needed => '검토 필요',
  };
}
