import '../models/shipment_record.dart';

/// 제공 자료 기반의 시연용 대응 안내입니다.
/// 열람만으로 조치 완료나 품질 검토 완료가 되지 않습니다.
class ResponseManualEntry {
  const ResponseManualEntry({
    required this.manualId,
    required this.scenarioType,
    required this.applicableStorageStage,
    required this.title,
    required this.shortDescription,
    required this.immediateActions,
    required this.detailedActions,
    required this.reportingGuidance,
    required this.documentationGuidance,
    required this.handlingPrecautions,
    required this.sourceReference,
    required this.sourceVersion,
  });

  final String manualId;
  final String scenarioType;
  final String applicableStorageStage;
  final String title;
  final String shortDescription;
  final List<String> immediateActions;
  final List<String> detailedActions;
  final String reportingGuidance;
  final String documentationGuidance;
  final List<String> handlingPrecautions;
  final String sourceReference;
  final String sourceVersion;
}

class ManualScenario {
  const ManualScenario._();

  static const String aboveMax = 'above_max';
  static const String belowMin = 'below_min';
  static const String coolingFault = 'cooling_fault';
  static const String dataGap = 'data_gap';
  static const String transportDelay = 'transport_delay';
  static const String physicalShock = 'physical_shock';
  static const String theftLoss = 'theft_loss';

  static const List<String> values = <String>[
    aboveMax,
    belowMin,
    coolingFault,
    dataGap,
    transportDelay,
    physicalShock,
    theftLoss,
  ];

  static bool isTemperatureExcursion(String scenarioType) {
    return scenarioType == aboveMax || scenarioType == belowMin;
  }
}

class ManualStage {
  const ManualStage._();

  static const String frozen = 'frozen';
  static const String thawedRefrigerated = 'thawed_refrigerated';
  static const String refrigerated = 'refrigerated';
  static const String general = 'general';
}

class ResponseManualCatalog {
  const ResponseManualCatalog._();

  static const String disclaimer =
      '제공 자료 기반 시연용 대응 안내이며, 실제 업무에서는 최신 허가사항 및 기관별 SOP 확인이 필요합니다.';

  static const String sourceReference =
      '사용자 제공 자료 「백신 보관·취급 조건 및 운송자 현장 행동 매뉴얼」, 「백신 조사」, 「백신」. '
      '참고 기관으로 식품의약품안전처, 질병관리청, 국가법령정보센터가 적혀 있습니다. '
      '이 앱은 해당 원문을 이번 단계에서 다시 대조하지 않았고, 현재 시행 중인 법적 의무로 확정하지 않습니다.';

  static const String sourceVersion = 'provided-materials-2026-11-20';

  static const String viewDoesNotCompleteAction =
      '매뉴얼을 연 것은 조치 기록이나 품질 검토 완료가 아닙니다.';

  static String stageFor(ShipmentRecord shipment) {
    if (shipment.isLegacyManualRegistration) {
      return ManualStage.general;
    }
    return switch (shipment.selectedStorageStage) {
      '냉동 보관' => ManualStage.frozen,
      '해동 후 냉장 보관' => ManualStage.thawedRefrigerated,
      '냉장 보관' => ManualStage.refrigerated,
      _ => ManualStage.general,
    };
  }

  static ResponseManualEntry select({
    required String scenarioType,
    required ShipmentRecord shipment,
  }) {
    final String stage = stageFor(shipment);
    for (final ResponseManualEntry entry in entries) {
      if (entry.scenarioType == scenarioType &&
          entry.applicableStorageStage == stage) {
        return entry;
      }
    }
    for (final ResponseManualEntry entry in entries) {
      if (entry.scenarioType == scenarioType &&
          entry.applicableStorageStage == ManualStage.general) {
        return entry;
      }
    }
    throw ArgumentError('대응 매뉴얼을 찾을 수 없습니다.');
  }

  static final List<ResponseManualEntry> entries = <ResponseManualEntry>[
    _temperature(
      scenarioType: ManualScenario.aboveMax,
      stage: ManualStage.frozen,
      title: '냉동 보관 고온 이탈 대응',
      summary: '적용 범위보다 높은 온도가 기록되었습니다. 초저온 보관 조건을 확인합니다.',
      details: <String>[
        '냉동 수송설비의 전원, 설정, 문 닫힘 상태를 확인합니다.',
        '냉장 백신용 냉매 안내를 이 냉동 운송에 그대로 적용하지 않습니다.',
        '자동온도기록장치를 끄거나 기록을 수정하지 않습니다.',
        '이탈 시작 시각, 최고 온도, 확인 가능한 지속 시간, 조치 내용을 기록합니다.',
      ],
      precautions: <String>[
        '백신을 임의로 사용하거나 폐기하지 않습니다.',
        '해동 후 재냉동 여부를 이 화면이 판정하지 않습니다.',
      ],
    ),
    _temperature(
      scenarioType: ManualScenario.aboveMax,
      stage: ManualStage.thawedRefrigerated,
      title: '해동 후 냉장 고온 이탈 대응',
      summary: '해동 후 냉장 보관 단계의 적용 범위를 초과한 온도가 기록되었습니다.',
      details: <String>[
        '냉장 수송설비와 문 닫힘, 직사광선 노출 여부를 확인합니다.',
        '해동된 백신을 다시 냉동하지 않습니다.',
        '해동 후 보관 가능 기간은 등록된 보관 조건 참고입니다.',
        '해동 시작 시각이 없으므로 남은 시간을 계산하지 않습니다.',
        '자동온도기록장치를 끄거나 기록을 수정하지 않습니다.',
      ],
      precautions: <String>['재냉동 금지.', '사용 보류 안내는 실제 격리 완료가 아닙니다.'],
    ),
    _temperature(
      scenarioType: ManualScenario.aboveMax,
      stage: ManualStage.refrigerated,
      title: '냉장 보관 고온 이탈 대응',
      summary: '냉장 보관 적용 범위를 초과한 온도가 기록되었습니다.',
      details: <String>[
        '냉장 장치의 전원, 설정 온도, 문 닫힘, 직사광선 노출을 확인합니다.',
        '동결 금지 제품이므로 온도를 낮추는 과정에서 얼리지 않습니다.',
        '차광 상태를 확인합니다.',
        '자동온도기록장치를 끄거나 기록을 수정하지 않습니다.',
      ],
      precautions: <String>['동결 금지.', '차광.', '냉매가 백신에 직접 닿지 않게 합니다.'],
    ),
    _temperature(
      scenarioType: ManualScenario.aboveMax,
      stage: ManualStage.general,
      title: '고온 이탈 대응',
      summary: '이 운송 건에 저장된 적용 최고 온도를 초과한 기록이 있습니다.',
      details: <String>[
        '냉각 장치 전원, 문 닫힘, 설정 온도, 직사광선 노출을 확인합니다.',
        '이 운송 건을 다른 백신 제품으로 바꾸지 않습니다.',
        '자동온도기록장치를 끄거나 기록을 수정하지 않습니다.',
        '필요한 예비 수송설비는 현장 SOP와 적용 보관 조건에 따라 확인합니다.',
      ],
      precautions: <String>['백신을 임의로 사용하거나 폐기하지 않습니다.'],
    ),
    _temperature(
      scenarioType: ManualScenario.belowMin,
      stage: ManualStage.frozen,
      title: '냉동 보관 저온 이탈 대응',
      summary: '적용 최저 온도보다 낮은 온도가 기록되었습니다. 0°C 미만을 동결 사고로 보지 않습니다.',
      details: <String>[
        '초저온 설비의 설정값과 작동 상태를 확인합니다.',
        '일반 냉장 백신용 냉매 안내를 그대로 적용하지 않습니다.',
        '임의로 해동하거나 재냉동하지 않습니다.',
        '최저 온도와 확인 가능한 지속 시간을 기록합니다.',
      ],
      precautions: <String>[
        '0°C 미만이라는 이유만으로 동결 사고라고 표시하지 않습니다.',
        '제품을 임의로 폐기하지 않습니다.',
      ],
    ),
    _temperature(
      scenarioType: ManualScenario.belowMin,
      stage: ManualStage.thawedRefrigerated,
      title: '해동 후 냉장 저온 이탈 대응',
      summary: '해동 후 냉장 보관 단계의 적용 최저 온도보다 낮은 온도가 기록되었습니다.',
      details: <String>[
        '냉장 설비의 설정과 냉매 직접 접촉 여부를 확인합니다.',
        '다시 냉동하지 않습니다.',
        '남은 해동 시간을 계산하지 않습니다.',
        '최저 온도와 확인 가능한 지속 시간을 기록합니다.',
      ],
      precautions: <String>['재냉동 금지.', '제품을 임의로 폐기하지 않습니다.'],
    ),
    _temperature(
      scenarioType: ManualScenario.belowMin,
      stage: ManualStage.refrigerated,
      title: '냉장 보관 저온 이탈 대응',
      summary: '냉장 보관 적용 최저 온도보다 낮은 온도가 기록되었습니다. 동결 여부를 앱이 판정하지 않습니다.',
      details: <String>[
        '냉각 설정과 냉매가 백신 용기에 직접 닿는지 확인합니다.',
        '동결 금지. 차광 상태를 유지합니다.',
        '임의로 해동하거나 폐기하지 않습니다.',
        '최저 온도와 확인 가능한 지속 시간을 기록합니다.',
      ],
      precautions: <String>['동결 금지.', '차광.', '냉매 직접 접촉을 피합니다.'],
    ),
    _temperature(
      scenarioType: ManualScenario.belowMin,
      stage: ManualStage.general,
      title: '저온 이탈 대응',
      summary: '이 운송 건에 저장된 적용 최저 온도보다 낮은 기록이 있습니다.',
      details: <String>[
        '냉각 장치 설정과 과도한 냉각 가능성을 확인합니다.',
        '0°C 미만을 모든 백신의 동결 사고로 단정하지 않습니다.',
        '제품별 보관 조건은 이 운송 건에 저장된 범위를 봅니다.',
        '임의로 해동, 재냉동, 폐기하지 않습니다.',
      ],
      precautions: <String>['제품을 임의로 폐기하지 않습니다.'],
    ),
    _equipment(ManualStage.frozen, '냉동 수송설비의 전원과 작동을 확인합니다.'),
    _equipment(ManualStage.thawedRefrigerated, '냉장 수송설비를 확인하고 재냉동하지 않습니다.'),
    _equipment(ManualStage.refrigerated, '냉장 장치를 확인하고 동결시키지 않습니다. 차광을 유지합니다.'),
    _equipment(ManualStage.general, '이 운송 건의 적용 보관 조건에 맞는 설비인지 확인합니다.'),
    _reference(
      scenarioType: ManualScenario.dataGap,
      title: '온도 데이터 공백 대응',
      summary: '온도 기록이 비어 있는 구간이 있습니다. 이것은 고온·저온 이탈과 같지 않습니다.',
      immediate: <String>[
        '안전하게 정차한 뒤 기록 상태를 확인하세요.',
        '기록 장치의 전원과 연결 상태를 확인하세요.',
        '확인되지 않은 시간대를 책임자에게 알리고 기록하세요.',
      ],
      details: <String>[
        '누락된 시작·종료 시각과 마지막 온도 기록을 확인합니다.',
        '없는 구간의 온도값을 만들지 않습니다.',
        '기록이 없었다는 이유로 정상 온도였다고 추정하지 않습니다.',
        '기록이 없었다는 이유로 고온·저온 이탈이 있었다고 판정하지 않습니다.',
        '해당 구간의 위험도는 기존처럼 평가 불가로 둡니다.',
      ],
      reporting: '품질관리자가 기록의 완전성을 검토할 수 있게 공백 사실을 남깁니다.',
      documentation: '공백이 있었다는 사실만 기록합니다. 추정 온도는 넣지 않습니다.',
      precautions: <String>['앱은 기록 장치 고장을 진단하지 않습니다. 시연 데이터 또는 수동 확인만 표시합니다.'],
    ),
    _reference(
      scenarioType: ManualScenario.transportDelay,
      title: '수송 지연 참고',
      summary: '지연은 수동으로 보고하는 참고 상황입니다. 위치는 추적하지 않습니다.',
      immediate: <String>[
        '운송 계획과 적용 보관 조건을 확인하세요.',
        '도착 예정 시각이 바뀌었는지 확인하세요.',
        '책임자와 수령기관 연락이 필요한지 확인하고 지연 사유를 기록하세요.',
      ],
      details: <String>[
        '지연 사유와 시간을 기록합니다.',
        '지연만으로 온도 이탈이 있었다고 판정하지 않습니다.',
        'GPS 추적이나 자동 신고는 하지 않습니다.',
      ],
      reporting: '연락 대상은 기관별 SOP와 운송 계약에 따라 확인합니다.',
      documentation: '지연 사유, 시간, 연락 여부를 직접 입력합니다.',
      precautions: <String>['특정 기관 보고 절차를 모든 운송의 법적 의무로 단정하지 않습니다.'],
    ),
    _reference(
      scenarioType: ManualScenario.physicalShock,
      title: '물리적 충격 참고',
      summary: '충격은 수동으로 보고합니다. 앱이 충격을 감지하지는 않습니다.',
      immediate: <String>[
        '안전하게 정차하세요.',
        '외부 포장과 수송용기 상태를 확인하세요.',
        '손상 가능성을 책임자에게 알리고 기록하세요.',
      ],
      details: <String>[
        '사진 등 증빙을 확보했는지만 기록합니다. 앱은 사진을 첨부하지 않습니다.',
        '품질관리자 검토가 필요하면 검토 요청 사실을 기록합니다.',
        '충격만으로 폐기 여부를 정하지 않습니다.',
      ],
      reporting: '품질관리 책임자에게 제품 손상 가능성을 알립니다.',
      documentation: '발생 시각, 용기 상태, 증빙 확보 여부를 기록합니다.',
      precautions: <String>['앱은 손상이나 폐기를 판정하지 않습니다.'],
    ),
    _reference(
      scenarioType: ManualScenario.theftLoss,
      title: '도난·분실 참고',
      summary: '도난·분실은 수동 보고입니다. 자동 위치 추적이나 기관 신고를 하지 않습니다.',
      immediate: <String>[
        '현장 안전을 먼저 확보하세요.',
        '내부 책임자에게 연락하세요.',
        '발생 시각, 장소, 상황을 기록하세요.',
      ],
      details: <String>[
        '기관별 사고 대응 절차를 확인합니다.',
        '관할 기관에 자동으로 신고하지 않습니다.',
        '서버로 전송하지 않습니다.',
      ],
      reporting: '실제 연락 대상은 기관별 SOP와 운송 계약에 따라 확인합니다.',
      documentation: '발생 시각, 장소, 상황을 직접 입력합니다. 위치는 자동으로 채우지 않습니다.',
      precautions: <String>['사용자 제공 자료의 특정 보고 절차를 모든 운송의 법적 의무로 단정하지 않습니다.'],
    ),
  ];

  static ResponseManualEntry _temperature({
    required String scenarioType,
    required String stage,
    required String title,
    required String summary,
    required List<String> details,
    required List<String> precautions,
  }) {
    final bool high = scenarioType == ManualScenario.aboveMax;
    return _reference(
      scenarioType: scenarioType,
      stage: stage,
      title: title,
      summary: summary,
      immediate: <String>[
        '안전하게 정차하세요. 운전 중에는 앱을 조작하지 마세요.',
        high ? '냉각 장치와 보관 상태를 확인하세요.' : '냉각 장치와 냉매 상태를 확인하세요.',
        '책임자에게 연락하고 상황을 기록하세요.',
      ],
      details: details,
      reporting: '품질관리 책임자에게 연락합니다. 연락 대상은 기관별 SOP와 운송 계약에 따라 확인합니다. 앱이 연락을 대신하지 않습니다.',
      documentation: high
          ? '이탈 시작 시각, 최고 온도, 확인 가능한 지속 시간, 조치 내용을 기록합니다.'
          : '최저 온도, 확인 가능한 지속 시간, 조치 내용을 기록합니다. 공백이 있으면 지속 시간을 단정하지 않습니다.',
      precautions: precautions,
    );
  }

  static ResponseManualEntry _equipment(String stage, String focus) {
    return _reference(
      scenarioType: ManualScenario.coolingFault,
      stage: stage,
      title: '냉각 장치 이상 대응',
      summary: '장비 이상은 시연 시나리오 또는 수동 보고로만 표시합니다. 앱이 실제 고장을 감지하지 않습니다.',
      immediate: <String>[
        '안전하게 정차하세요.',
        '장치 전원과 작동 상태를 확인하세요.',
        '책임자에게 연락하고 승인된 예비 설비 절차를 확인하세요.',
      ],
      details: <String>[
        focus,
        '전원 연결, 작동, 문 닫힘 상태를 확인합니다.',
        '장비 이상과 온도 이탈은 서로 다른 사건입니다.',
        '온도 기록을 중단하거나 수정하지 않습니다.',
        '예비 설비는 해당 보관 조건과 현장 SOP에 따라 확인합니다.',
      ],
      reporting: '고장 시각과 확인한 상태를 책임자에게 알립니다. 앱이 센서로 고장을 진단하지 않습니다.',
      documentation: '장비 이상 시각과 온도 이탈 여부를 구분해서 기록합니다.',
      precautions: <String>['실제 센서 진단이 있는 것처럼 표시하지 않습니다.'],
    );
  }

  static ResponseManualEntry _reference({
    required String scenarioType,
    required String title,
    required String summary,
    required List<String> immediate,
    required List<String> details,
    required String reporting,
    required String documentation,
    required List<String> precautions,
    String stage = ManualStage.general,
  }) {
    return ResponseManualEntry(
      manualId: '$scenarioType-$stage',
      scenarioType: scenarioType,
      applicableStorageStage: stage,
      title: title,
      shortDescription: summary,
      immediateActions: immediate,
      detailedActions: details,
      reportingGuidance: reporting,
      documentationGuidance: documentation,
      handlingPrecautions: precautions,
      sourceReference: sourceReference,
      sourceVersion: sourceVersion,
    );
  }
}
