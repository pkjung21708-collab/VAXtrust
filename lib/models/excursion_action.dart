/// 이탈 이벤트에 연결된 원인·조치 기록입니다.
/// 고치면 기존 행을 지우지 않고 새 행을 추가합니다.
class ExcursionAction {
  const ExcursionAction({
    required this.id,
    required this.shipmentId,
    required this.excursionId,
    required this.authorUserId,
    required this.authorLoginId,
    required this.causeCategory,
    required this.causeCertainty,
    required this.description,
    required this.discoveredAt,
    required this.responseStartedAt,
    required this.actionTaken,
    required this.reportedTo,
    required this.reportedAt,
    required this.note,
    required this.createdAt,
    this.situationType,
    this.responsibleContacted,
    this.holdGuidanceGiven,
    this.holdActionCompleted,
  });

  static const List<String> categories = <String>[
    'door_open',
    'loading',
    'cooling_fault',
    'environment',
    'sensor_suspect',
    'unknown',
    'other',
  ];

  static const List<String> situationTypes = <String>[
    'above_max',
    'below_min',
    'cooling_fault',
    'data_gap',
    'transport_delay',
    'physical_shock',
    'theft_loss',
  ];

  static const String confirmed = 'confirmed';
  static const String suspected = 'suspected';

  final int id;
  final int shipmentId;
  final int? excursionId;
  final int authorUserId;
  final String authorLoginId;
  final String causeCategory;
  final String causeCertainty;
  final String description;
  final DateTime? discoveredAt;
  final DateTime? responseStartedAt;
  final String actionTaken;
  final String? reportedTo;
  final DateTime? reportedAt;
  final String? note;
  final DateTime createdAt;
  final String? situationType;
  final bool? responsibleContacted;
  final bool? holdGuidanceGiven;
  final bool? holdActionCompleted;

  String get categoryLabel => labelForCategory(causeCategory);

  String get certaintyLabel => causeCertainty == confirmed ? '확인된 원인' : '추정 원인';

  String get situationLabel => labelForSituation(situationType);

  String get contactLabel {
    if (responsibleContacted == null) {
      return '책임자 연락: 확인되지 않음';
    }
    return responsibleContacted! ? '책임자 연락: 기록됨' : '책임자 연락: 하지 않음';
  }

  String get holdLabel {
    if (holdActionCompleted == true) {
      return '실제 사용 보류 조치: 기록됨';
    }
    if (holdGuidanceGiven == true) {
      return '사용 보류 안내: 기록됨. 안내만으로 격리 완료가 아닙니다.';
    }
    if (holdGuidanceGiven == null && holdActionCompleted == null) {
      return '사용 보류: 확인되지 않음';
    }
    return '실제 사용 보류 조치: 기록되지 않음';
  }

  static String labelForSituation(String? situation) {
    return switch (situation) {
      'above_max' => '허용 온도 상한 초과',
      'below_min' => '허용 온도 하한 미달',
      'cooling_fault' => '냉각 장치 또는 전원 이상',
      'data_gap' => '온도 데이터 공백',
      'transport_delay' => '수송 지연',
      'physical_shock' => '물리적 충격',
      'theft_loss' => '도난·분실',
      _ => '상황 유형 없음',
    };
  }

  static String labelForCategory(String category) {
    return switch (category) {
      'door_open' => '운송 용기 문 열림',
      'loading' => '상하차 작업',
      'cooling_fault' => '냉각 장치 이상',
      'environment' => '외부 환경 영향',
      'sensor_suspect' => '센서 또는 측정 장치 이상 의심',
      'unknown' => '원인 미확인',
      'other' => '기타',
      _ => '기타',
    };
  }
}
