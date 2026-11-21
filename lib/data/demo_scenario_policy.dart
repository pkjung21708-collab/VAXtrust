import '../models/demo_scenario.dart';

/// 시연 시나리오의 온도 변화 속도입니다.
/// 일반 운송의 0.3°C 제한과 분리되어 있고, 한 번에 크게 뛰지 않습니다.
class DemoScenarioSettings {
  const DemoScenarioSettings({
    this.stepCelsius = 0.5,
    this.holdSamples = 4,
    this.breachMargin = 0.4,
  });

  /// 5초마다 움직이는 폭입니다.
  final double stepCelsius;

  /// 문 열림·과냉각이 범위를 벗어난 뒤 유지하는 측정 횟수입니다.
  final int holdSamples;

  /// 유지 단계에서 범위 밖에 머무는 여유입니다.
  final double breachMargin;
}

class ScenarioStep {
  const ScenarioStep({
    required this.celsius,
    required this.phase,
    required this.holdSamples,
  });

  final double celsius;
  final String phase;
  final int holdSamples;

  bool get ended => phase == DemoScenario.ended;
}

/// 시나리오 진행에 따른 다음 온도입니다.
/// 범위를 벗어나는 값은 여기서 만들고, 이탈 이벤트는 저장 시점에 판정합니다.
class DemoScenarioPolicy {
  static ScenarioStep advance({
    required String type,
    required String phase,
    required int holdSamples,
    required double? previous,
    required double min,
    required double max,
    DemoScenarioSettings settings = const DemoScenarioSettings(),
    bool recoverCooling = false,
  }) {
    final double origin = previous ?? ((min + max) / 2);
    final double step = settings.stepCelsius;
    if (phase == DemoScenario.rising) {
      final double value = _round(
        type == DemoScenario.overcool ? origin - step : origin + step,
      );
      final bool breached = type == DemoScenario.overcool
          ? value < min
          : value > max;
      return ScenarioStep(
        celsius: value,
        phase: breached ? DemoScenario.holding : DemoScenario.rising,
        holdSamples: holdSamples,
      );
    }
    if (phase == DemoScenario.holding) {
      final double target = type == DemoScenario.overcool
          ? min - settings.breachMargin
          : max + settings.breachMargin;
      final int nextHold = holdSamples + 1;
      final bool coolingMayRecover =
          type != DemoScenario.coolingFault || recoverCooling;
      final bool autoRecover =
          coolingMayRecover && nextHold >= settings.holdSamples;
      return ScenarioStep(
        celsius: _toward(origin, target, step),
        phase: autoRecover ? DemoScenario.recovering : DemoScenario.holding,
        holdSamples: nextHold,
      );
    }
    if (phase == DemoScenario.recovering) {
      final double mid = (min + max) / 2;
      final double value = _toward(origin, mid, step);
      final bool inside = value >= min && value <= max;
      return ScenarioStep(
        celsius: value,
        phase: inside ? DemoScenario.ended : DemoScenario.recovering,
        holdSamples: holdSamples,
      );
    }
    return ScenarioStep(
      celsius: _round(origin),
      phase: DemoScenario.ended,
      holdSamples: holdSamples,
    );
  }

  static double _toward(double origin, double target, double step) {
    final double delta = target - origin;
    if (delta.abs() <= step) {
      return _round(target);
    }
    return _round(origin + step * (delta.isNegative ? -1 : 1));
  }

  static double _round(double value) => (value * 10).round() / 10;
}
