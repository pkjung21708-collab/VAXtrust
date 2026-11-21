/// 시연으로 이상 온도를 만드는 진행 상태입니다.
/// 시나리오 이름은 운송자가 입력한 원인 기록과 다릅니다.
class DemoScenario {
  const DemoScenario({
    required this.id,
    required this.shipmentId,
    required this.type,
    required this.phase,
    required this.startedAt,
    required this.endedAt,
    required this.startedByUserId,
    required this.holdSamples,
    this.triggerSource = manualTrigger,
  });

  static const String doorOpen = 'door_open';
  static const String coolingFault = 'cooling_fault';
  static const String overcool = 'overcool';

  static const String manualTrigger = 'manual';
  static const String autoTrigger = 'auto';

  static const String rising = 'rising';
  static const String holding = 'holding';
  static const String recovering = 'recovering';
  static const String ended = 'ended';

  final int id;
  final int shipmentId;
  final String type;
  final String phase;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int startedByUserId;
  final int holdSamples;

  /// manual은 운송자가 누른 시연이고, auto는 가상 자동 시연입니다.
  final String triggerSource;

  bool get isActive => phase != ended;

  bool get isAuto => triggerSource == autoTrigger;

  String get typeLabel => switch (type) {
    doorOpen => '운송 용기 문 열림',
    coolingFault => '냉각 장치 이상',
    overcool => '과냉각',
    _ => type,
  };

  String get phaseLabel => switch (phase) {
    rising => '온도 변화 중',
    holding => '이탈 유지 중',
    recovering => '정상 범위로 복귀 중',
    ended => '종료',
    _ => phase,
  };
}

/// 목록 카드에 보여줄 이탈 집계입니다.
class ExcursionSummary {
  const ExcursionSummary({
    required this.count,
    required this.open,
    required this.gap,
  });

  final int count;
  final bool open;
  final bool gap;
}
