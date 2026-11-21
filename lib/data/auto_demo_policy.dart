import 'dart:math' as math;

/// 운송 시작 때 고르는 자동 시연 방식입니다.
/// 값이 없으면 기존 운송 건의 수동 시연 방식입니다.
class DemoMode {
  const DemoMode._();

  static const String probabilistic = 'probabilistic';
  static const String presentation = 'presentation';

  static bool isKnown(String? mode) {
    return mode == probabilistic || mode == presentation;
  }

  static String? label(String? mode) {
    return switch (mode) {
      probabilistic => '일반 자동 시연',
      presentation => '발표용 자동 시연',
      _ => null,
    };
  }
}

/// 일반 자동 시연의 발생 빈도입니다. 화면 설정으로 바꾸지 않습니다.
///
/// 아래 시간과 확률은 실제 백신 운송의 사고 통계가 아니라 시연용 설정입니다.
class AutoDemoSettings {
  const AutoDemoSettings({
    this.minimumNormalSamples = 24,
    this.cooldownSamples = 48,
    this.eventChance = 0.08,
    this.gapSkips = 4,
    this.holdSamples = 4,
  });

  /// 운송 시작 직후 이 횟수 동안은 이상 상황을 만들지 않습니다.
  final int minimumNormalSamples;

  /// 한 상황이 끝난 뒤 다음 상황까지 두는 정상 측정 횟수입니다.
  final int cooldownSamples;

  /// 조용한 구간의 측정마다 이상이 시작될 확률입니다.
  final double eventChance;

  /// 온도를 남기지 않는 횟수입니다. 4회면 5초 간격에서 20초 공백이 됩니다.
  final int gapSkips;

  /// 자동 고온·저온·냉각 이상이 범위를 벗어난 뒤 유지하는 횟수입니다.
  final int holdSamples;
}

/// 이번 측정에서 새로 시작할 자동 상황입니다.
class AutoDemoStart {
  const AutoDemoStart.scenario(this.scenarioType) : gap = false;

  const AutoDemoStart.gap() : scenarioType = null, gap = true;

  final String? scenarioType;
  final bool gap;
}

/// 확률 시연에서 쓰는 난수입니다. 테스트가 순서를 고정할 수 있습니다.
class DemoRoll {
  const DemoRoll({required this.unit, required this.pick});

  factory DemoRoll.random([math.Random? random]) {
    final math.Random source = random ?? math.Random();
    return DemoRoll(unit: source.nextDouble, pick: source.nextInt);
  }

  final double Function() unit;
  final int Function(int max) pick;
}

/// 진행 중인 상황이 없을 때만 다음 이상 하나를 고릅니다.
class ProbabilisticAutoDemo {
  static AutoDemoStart? roll({
    required DemoRoll roll,
    required int readingCount,
    required int cooldownUntilCount,
    required bool scenarioActive,
    required int gapSkipsRemaining,
    AutoDemoSettings settings = const AutoDemoSettings(),
  }) {
    if (scenarioActive || gapSkipsRemaining > 0) {
      return null;
    }
    if (readingCount < settings.minimumNormalSamples) {
      return null;
    }
    if (readingCount < cooldownUntilCount) {
      return null;
    }
    if (roll.unit() >= settings.eventChance) {
      return null;
    }
    return switch (roll.pick(4)) {
      0 => const AutoDemoStart.scenario('door_open'),
      1 => const AutoDemoStart.scenario('overcool'),
      2 => const AutoDemoStart.scenario('cooling_fault'),
      _ => const AutoDemoStart.gap(),
    };
  }
}

/// 정상 구간의 시연 온도입니다.
///
/// 이전 측정값에서 0.1~0.3°C만 움직이고, 허용 범위 중앙 쪽으로 자주 되돌립니다.
/// 특정 백신의 5°C가 아니라 해당 운송 건의 하한·상한으로 계산합니다.
class VariedTemperature {
  const VariedTemperature._();

  static double round(double value) => (value * 10).round() / 10;

  static double next({
    required double? previous,
    required double min,
    required double max,
    required int sampleIndex,
    int? seed,
    math.Random? random,
  }) {
    if (min > max) {
      throw ArgumentError('허용 온도 하한이 상한보다 큽니다.');
    }
    final double mid = (min + max) / 2;
    if (max - min < 0.2) {
      return round(mid);
    }
    final double origin = previous ?? mid;
    final math.Random roll =
        random ??
        math.Random(((seed ?? 1) * 1000003 + sampleIndex * 97) & 0x7fffffff);
    final double towardCenter = mid - origin;
    final double direction = towardCenter.abs() < 0.15
        ? (roll.nextBool() ? 1.0 : -1.0)
        : (roll.nextDouble() < 0.8 ? towardCenter.sign : -towardCenter.sign);
    final double magnitude = 0.1 + roll.nextDouble() * 0.2;
    var value = origin + direction * magnitude;
    if (value < min) {
      value = min;
    }
    if (value > max) {
      value = max;
    }
    var rounded = round(value);
    if (rounded < min) {
      rounded = min;
    }
    if (rounded > max) {
      rounded = max;
    }
    return round(rounded);
  }
}

/// 발표용 자동 시연의 사건 일정입니다.
///
/// 운송 건 시드로 첫 사건과 순서를 정하므로 같은 운송 건은 다시 열어도
/// 같은 일정을 따릅니다. 온도값 자체는 [VariedTemperature]가 조금씩 바꿉니다.
/// 시간과 확률은 실제 사고 통계가 아니라 시연용 설정입니다.
class PresentationSettings {
  const PresentationSettings({
    this.openingMinSamples = 12,
    this.openingSpan = 25,
    this.quietSamples = 48,
    this.scriptedEvents,
  });

  static const String dataGap = 'data_gap';

  /// 첫 이상 전 최소 정상 측정 수입니다. 5초 간격에서 12회는 1분입니다.
  final int openingMinSamples;

  /// 첫 이상을 운송 건마다 이 폭 안에서 흩어 놓습니다. 25면 0~24회가 더해집니다.
  final int openingSpan;

  /// 사건이 끝난 뒤 새 이상을 시작하지 않는 측정 수입니다. 48회는 4분입니다.
  final int quietSamples;

  /// 테스트가 사건 순서를 고정할 때 사용합니다. 없으면 운송 건 시드로 섞습니다.
  final List<String>? scriptedEvents;

  static double midpoint(double min, double max) =>
      VariedTemperature.round((min + max) / 2);

  int firstSampleIndex(int shipmentId) {
    final int span = openingSpan < 1 ? 1 : openingSpan;
    if (span == 1) {
      return openingMinSamples;
    }
    return openingMinSamples +
        math.Random(shipmentId & 0x7fffffff).nextInt(span);
  }

  List<String> sequenceFor(int shipmentId) {
    final List<String>? script = scriptedEvents;
    if (script != null && script.isNotEmpty) {
      return script;
    }
    final List<String> events = <String>[
      'door_open',
      'overcool',
      'cooling_fault',
      dataGap,
    ];
    events.shuffle(math.Random((shipmentId * 17 + 3) & 0x7fffffff));
    return events;
  }

  /// 이번 측정에서 새로 시작할 사건입니다. 조용한 구간이면 null입니다.
  String? eventDue({
    required int shipmentId,
    required int readingCount,
    required int cooldownUntilCount,
    required int completedEvents,
  }) {
    if (readingCount < cooldownUntilCount) {
      return null;
    }
    if (completedEvents == 0 && readingCount < firstSampleIndex(shipmentId)) {
      return null;
    }
    final List<String> events = sequenceFor(shipmentId);
    return events[completedEvents % events.length];
  }
}
