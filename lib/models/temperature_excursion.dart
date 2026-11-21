/// 연속된 온도 이탈 한 건입니다. 같은 이탈이 이어지는 동안 행을 새로 만들지 않습니다.
class TemperatureExcursion {
  const TemperatureExcursion({
    required this.id,
    required this.shipmentId,
    required this.direction,
    required this.startedAt,
    required this.lastOutOfRangeAt,
    required this.recoveredAt,
    required this.minTemperature,
    required this.maxTemperature,
    required this.dataGapDetected,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  static const String aboveMax = 'above_max';
  static const String belowMin = 'below_min';
  static const String openStatus = 'open';
  static const String recoveredStatus = 'recovered';

  /// 이 시간보다 측정 간격이 길면 그 사이 온도는 추정하지 않습니다.
  static const Duration gapAfter = Duration(seconds: 15);

  final int id;
  final int shipmentId;
  final String direction;
  final DateTime startedAt;
  final DateTime lastOutOfRangeAt;
  final DateTime? recoveredAt;
  final double minTemperature;
  final double maxTemperature;
  final bool dataGapDetected;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen => status == openStatus;

  bool get isAbove => direction == aboveMax;

  String get directionLabel => isAbove ? '상한 이탈' : '하한 이탈';

  String get statusLabel {
    if (isOpen) {
      return directionLabel;
    }
    return '정상 범위 복귀';
  }

  /// 관측된 구간만 계산합니다. 공백이 있으면 지속시간을 단정하지 않습니다.
  String get durationLabel {
    if (dataGapDetected) {
      return '지속시간 확인 필요';
    }
    final Duration observed = lastOutOfRangeAt.difference(startedAt);
    if (observed.inSeconds <= 0) {
      return '확인 가능한 이탈 1회 측정';
    }
    if (observed.inSeconds < 60) {
      return '확인 가능한 이탈 ${observed.inSeconds}초';
    }
    final int minutes = observed.inMinutes;
    final int seconds = observed.inSeconds % 60;
    return '확인 가능한 이탈 $minutes분 $seconds초';
  }
}

/// 측정 시각을 초 단위로 보여 줍니다.
String formatMeasurementTime(DateTime? value) {
  if (value == null) {
    return '없음';
  }
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
