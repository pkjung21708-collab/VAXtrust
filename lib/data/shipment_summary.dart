import '../models/excursion_action.dart';
import '../models/quality_review.dart';
import '../models/shipment_record.dart';
import 'shipment_analytics.dart';

/// 저장된 운송 기록만으로 의료진용 문장을 만듭니다.
/// 외부 AI를 호출하지 않고, 없는 원인이나 접종 가능 여부를 만들지 않습니다.
String buildShipmentNarrative({
  required ShipmentRecord shipment,
  required ShipmentInsight insight,
  QualityReview? latestReview,
  List<ExcursionAction> actions = const <ExcursionAction>[],
}) {
  final List<String> sentences = <String>[
    '${shipment.displayId} ${shipment.vaccine} 운송은 ${shipment.status.label} 상태입니다. '
        '설정 온도 범위는 ${shipment.temperatureRangeLabel}입니다.',
  ];
  if (insight.readingCount == 0) {
    sentences.add('현재 분석 가능한 온도 기록이 없습니다.');
    sentences.add(
      '운영 위험 수준은 평가 불가입니다. '
      '이 수준은 시연용 운영 지표이며 백신의 품질 적합성이나 접종 가능 여부를 의미하지 않습니다.',
    );
  } else {
    if (insight.excursions.count == 0) {
      sentences.add('현재 확인된 운송 기록에서 설정 범위를 벗어난 온도 이탈은 확인되지 않았습니다.');
      sentences.add(
        '다만 이는 시연용 가상 온도 데이터를 기준으로 한 결과이며, '
        '실제 백신의 품질이나 사용 가능 여부를 의미하지 않습니다.',
      );
    } else {
      if (insight.excursions.aboveCount > 0) {
        final double? excess = insight.excursions.maxAboveExcess;
        sentences.add(
          '설정 온도 상한을 초과한 기록이 ${insight.excursions.aboveCount}회 확인되었습니다.'
          '${excess == null ? '' : ' 최대 초과 정도는 ${excess.toStringAsFixed(1)}°C입니다.'}',
        );
      }
      if (insight.excursions.belowCount > 0) {
        final double? shortfall = insight.excursions.maxBelowShortfall;
        sentences.add(
          '설정 온도 하한에 미달한 기록이 ${insight.excursions.belowCount}회 확인되었습니다.'
          '${shortfall == null ? '' : ' 최대 미달 정도는 ${shortfall.toStringAsFixed(1)}°C입니다.'}',
        );
      }
      sentences.add('${insight.excursions.durationLabel}.');
      if (insight.excursions.missingAction) {
        sentences.add('운송자의 원인 및 조치 기록은 없습니다.');
        sentences.add('현재 해당 이탈에 대한 운송자 조치 기록은 확인되지 않았습니다. 품질관리자의 확인이 필요합니다.');
      } else {
        sentences.add('운송자의 원인 및 조치 기록이 등록되어 있습니다.');
        sentences.add(
          '운송 중 온도 이탈이 기록되었으며, 운송자가 관련 조치 내용을 기록했습니다. 조치 내용과 품질관리자 검토 상태를 함께 확인해 주세요.',
        );
        sentences.add(_contactSentence(actions));
        sentences.add(_holdSentence(actions));
      }
    }
    if (insight.hasGap) {
      sentences.add('측정 데이터가 누락된 구간이 있어 해당 시간의 온도 상태를 확인할 수 없습니다.');
    }
    sentences.add(
      '운영 위험 수준은 ${insight.risk.level.label}입니다. '
      '이 수준은 시연용 운영 지표이며 백신의 품질 적합성이나 접종 가능 여부를 의미하지 않습니다.',
    );
  }
  final QualityReviewStatus status =
      latestReview?.status ?? QualityReviewStatus.notReviewed;
  if (latestReview == null || status == QualityReviewStatus.notReviewed) {
    sentences.add('현재 품질관리자의 검토 기록이 없습니다.');
  } else {
    sentences.add('품질 검토 상태는 ${status.label}입니다.');
    if (status == QualityReviewStatus.reviewCompleted) {
      sentences.add(
        '운송 중 발생한 이상 상황에 대한 품질관리자의 검토가 완료된 것으로 기록되어 있습니다. '
        '검토 완료는 백신의 사용 가능 여부나 접종 적합성 승인을 의미하지 않습니다.',
      );
    }
  }
  return sentences.join(' ');
}

String _contactSentence(List<ExcursionAction> actions) {
  if (actions.isEmpty ||
      actions.every(
        (ExcursionAction action) => action.responsibleContacted == null,
      )) {
    return '책임자 연락 여부는 확인되지 않았습니다.';
  }
  if (actions.any(
    (ExcursionAction action) => action.responsibleContacted == true,
  )) {
    return '책임자 연락이 기록되어 있습니다.';
  }
  return '책임자에게 연락하지 않은 것으로 기록되어 있습니다.';
}

String _holdSentence(List<ExcursionAction> actions) {
  if (actions.any(
    (ExcursionAction action) => action.holdActionCompleted == true,
  )) {
    return '실제 사용 보류 조치가 기록되어 있습니다. 앱이 격리 완료를 대신 판단하지 않습니다.';
  }
  if (actions.any(
    (ExcursionAction action) => action.holdGuidanceGiven == true,
  )) {
    return '사용 보류 안내가 기록되어 있습니다. 안내만으로 격리 완료를 의미하지 않습니다.';
  }
  return '실제 사용 보류 조치 완료는 확인되지 않았습니다.';
}
