import 'dart:math';

/// 일반 운송의 다음 시연 온도입니다.
///
/// 설정 범위 안에서만 조금씩 움직입니다.
/// 범위를 벗어나는 시연은 시나리오 규칙이 맡습니다.
class InRangeTemperaturePolicy {
  InRangeTemperaturePolicy({Random? random}) : _random = random ?? Random();

  /// 한 번에 움직이는 최대 폭입니다. 급격한 점프를 막습니다.
  static const double maxStep = 0.3;

  final Random _random;

  double next({
    required double? previous,
    required double min,
    required double max,
  }) {
    if (min > max) {
      throw ArgumentError('설정 온도 범위가 올바르지 않습니다.');
    }
    if (max - min < 0.05) {
      return _round(min);
    }

    final double origin = previous ?? ((min + max) / 2);
    final double value;
    if (origin < min) {
      value = origin + maxStep;
    } else if (origin > max) {
      value = origin - maxStep;
    } else {
      final double direction = _random.nextBool() ? 1 : -1;
      final double magnitude = 0.1 + _random.nextDouble() * (maxStep - 0.1);
      value = origin + direction * magnitude;
    }
    return _inside(value, min, max);
  }

  double _round(double value) => (value * 10).round() / 10;

  double _inside(double value, double min, double max) {
    final double clamped = value < min ? min : (value > max ? max : value);
    final double rounded = _round(clamped);
    if (rounded < min || rounded > max) {
      return clamped;
    }
    return rounded;
  }
}
