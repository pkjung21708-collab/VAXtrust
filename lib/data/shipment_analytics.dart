import '../models/shipment_record.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import 'demo_risk_settings.dart';

/// 한 운송 건의 이탈 집계입니다. 저장하지 않고 기록에서 계산합니다.
class ExcursionAnalysis {
  const ExcursionAnalysis({
    required this.count,
    required this.aboveCount,
    required this.belowCount,
    required this.maxAboveExcess,
    required this.maxBelowShortfall,
    required this.observedDuration,
    required this.confirmableEventCount,
    required this.gap,
    required this.open,
    required this.missingAction,
  });

  final int count;
  final int aboveCount;
  final int belowCount;
  final double? maxAboveExcess;
  final double? maxBelowShortfall;
  final Duration? observedDuration;
  final int confirmableEventCount;
  final bool gap;
  final bool open;
  final bool missingAction;

  String get durationLabel {
    if (count == 0) {
      return '해당 없음';
    }
    final Duration? observed = observedDuration;
    if (observed == null) {
      return '이탈 지속시간 확인 필요';
    }
    final String measured = '관측된 이탈 지속시간 ${observed.inSeconds}초';
    if (gap) {
      return '$measured · 이탈 지속시간 확인 필요';
    }
    return measured;
  }
}

class OperationalRisk {
  const OperationalRisk({
    required this.level,
    required this.reasons,
    required this.gapLimitsJudgement,
  });

  final OperationalRiskLevel level;
  final List<String> reasons;
  final bool gapLimitsJudgement;
}

class ShipmentInsight {
  const ShipmentInsight({
    required this.shipmentId,
    required this.readingCount,
    required this.readingGap,
    required this.temperature,
    required this.excursions,
    required this.risk,
    required this.review,
  });

  final int shipmentId;
  final int readingCount;
  final bool readingGap;
  final TemperatureCondition temperature;
  final ExcursionAnalysis excursions;
  final OperationalRisk risk;
  final QualityReviewState review;

  bool get hasGap => readingGap || excursions.gap;
}

class FleetSummary {
  const FleetSummary({
    required this.shipmentCount,
    required this.inTransitCount,
    required this.completedCount,
    required this.readingCount,
    required this.excursionEventCount,
    required this.shipmentsWithExcursion,
    required this.reviewNeededCount,
    required this.gapShipmentCount,
    required this.openExcursionShipmentCount,
  });

  final int shipmentCount;
  final int inTransitCount;
  final int completedCount;
  final int readingCount;
  final int excursionEventCount;
  final int shipmentsWithExcursion;
  final int reviewNeededCount;
  final int gapShipmentCount;
  final int openExcursionShipmentCount;

  static const FleetSummary empty = FleetSummary(
    shipmentCount: 0,
    inTransitCount: 0,
    completedCount: 0,
    readingCount: 0,
    excursionEventCount: 0,
    shipmentsWithExcursion: 0,
    reviewNeededCount: 0,
    gapShipmentCount: 0,
    openExcursionShipmentCount: 0,
  );
}

/// 대시보드와 상세 화면이 같이 쓰는 계산입니다.
/// 결과는 저장하지 않고, 품질 승인과 접종 가능 여부를 만들지 않습니다.
class ShipmentAnalytics {
  const ShipmentAnalytics({this.settings = const DemoRiskSettings()});

  final DemoRiskSettings settings;

  ShipmentInsight inspect({
    required ShipmentRecord shipment,
    required List<TemperatureReading> readings,
    required List<TemperatureExcursion> excursions,
    Map<int, bool> actionRecorded = const <int, bool>{},
  }) {
    final List<TemperatureReading> ordered =
        List<TemperatureReading>.of(readings)
          ..sort((TemperatureReading a, TemperatureReading b) {
            final int byTime = a.measuredAt.compareTo(b.measuredAt);
            if (byTime != 0) {
              return byTime;
            }
            return a.id.compareTo(b.id);
          });
    final bool readingGap = _hasReadingGap(ordered);
    final ExcursionAnalysis analysis = _excursions(
      shipment: shipment,
      excursions: excursions,
      actionRecorded: actionRecorded,
    );
    return ShipmentInsight(
      shipmentId: shipment.id,
      readingCount: ordered.length,
      readingGap: readingGap,
      temperature: _temperature(shipment, ordered, analysis.count),
      excursions: analysis,
      risk: _risk(
        readingCount: ordered.length,
        readingGap: readingGap,
        analysis: analysis,
      ),
      review: analysis.count > 0
          ? QualityReviewState.needed
          : QualityReviewState.notStarted,
    );
  }

  Map<int, ShipmentInsight> inspectAll({
    required List<ShipmentRecord> shipments,
    required List<TemperatureReading> readings,
    required Map<int, List<TemperatureExcursion>> excursions,
    Map<int, bool> actionRecorded = const <int, bool>{},
  }) {
    final Map<int, List<TemperatureReading>> byShipment =
        <int, List<TemperatureReading>>{};
    for (final TemperatureReading reading in readings) {
      byShipment
          .putIfAbsent(reading.shipmentId, () => <TemperatureReading>[])
          .add(reading);
    }
    return <int, ShipmentInsight>{
      for (final ShipmentRecord shipment in shipments)
        shipment.id: inspect(
          shipment: shipment,
          readings: byShipment[shipment.id] ?? const <TemperatureReading>[],
          excursions: excursions[shipment.id] ?? const <TemperatureExcursion>[],
          actionRecorded: actionRecorded,
        ),
    };
  }

  FleetSummary summarize({
    required List<ShipmentRecord> shipments,
    required List<ShipmentInsight> insights,
  }) {
    final Map<int, ShipmentInsight> byId = <int, ShipmentInsight>{
      for (final ShipmentInsight insight in insights)
        insight.shipmentId: insight,
    };
    int inTransit = 0;
    int completed = 0;
    int readings = 0;
    int events = 0;
    int withExcursion = 0;
    int gaps = 0;
    int open = 0;
    for (final ShipmentRecord shipment in shipments) {
      if (shipment.status == ShipmentStatus.inTransit) {
        inTransit += 1;
      }
      if (shipment.status == ShipmentStatus.completed) {
        completed += 1;
      }
      final ShipmentInsight? insight = byId[shipment.id];
      if (insight == null) {
        continue;
      }
      readings += insight.readingCount;
      events += insight.excursions.count;
      if (insight.excursions.count > 0) {
        withExcursion += 1;
      }
      if (insight.hasGap) {
        gaps += 1;
      }
      if (insight.excursions.open) {
        open += 1;
      }
    }
    return FleetSummary(
      shipmentCount: shipments.length,
      inTransitCount: inTransit,
      completedCount: completed,
      readingCount: readings,
      excursionEventCount: events,
      shipmentsWithExcursion: withExcursion,
      reviewNeededCount: withExcursion,
      gapShipmentCount: gaps,
      openExcursionShipmentCount: open,
    );
  }

  bool _hasReadingGap(List<TemperatureReading> ordered) {
    for (int index = 1; index < ordered.length; index++) {
      final Duration gap = ordered[index].measuredAt.toUtc().difference(
        ordered[index - 1].measuredAt.toUtc(),
      );
      if (gap > TemperatureExcursion.gapAfter) {
        return true;
      }
    }
    return false;
  }

  TemperatureCondition _temperature(
    ShipmentRecord shipment,
    List<TemperatureReading> ordered,
    int excursionCount,
  ) {
    if (ordered.isEmpty) {
      return TemperatureCondition.none;
    }
    final double? min = shipment.tempMin;
    final double? max = shipment.tempMax;
    final double celsius = ordered.last.celsius;
    if (min == null || max == null) {
      return TemperatureCondition.none;
    }
    if (celsius > max) {
      return TemperatureCondition.aboveMax;
    }
    if (celsius < min) {
      return TemperatureCondition.belowMin;
    }
    if (excursionCount > 0) {
      return TemperatureCondition.recovered;
    }
    return TemperatureCondition.inRange;
  }

  ExcursionAnalysis _excursions({
    required ShipmentRecord shipment,
    required List<TemperatureExcursion> excursions,
    required Map<int, bool> actionRecorded,
  }) {
    int above = 0;
    int below = 0;
    double? aboveExcess;
    double? belowShortfall;
    final List<TemperatureExcursion> confirmable =
        <TemperatureExcursion>[];
    bool gap = false;
    bool open = false;
    bool missingAction = false;
    for (final TemperatureExcursion excursion in excursions) {
      if (excursion.isAbove) {
        above += 1;
        final double? max = shipment.tempMax;
        if (max != null) {
          final double excess = excursion.maxTemperature - max;
          if (excess > 0 && (aboveExcess == null || excess > aboveExcess)) {
            aboveExcess = excess;
          }
        }
      } else {
        below += 1;
        final double? min = shipment.tempMin;
        if (min != null) {
          final double shortfall = min - excursion.minTemperature;
          if (shortfall > 0 &&
              (belowShortfall == null || shortfall > belowShortfall)) {
            belowShortfall = shortfall;
          }
        }
      }
      if (excursion.dataGapDetected) {
        gap = true;
      } else {
        confirmable.add(excursion);
      }
      if (excursion.isOpen) {
        open = true;
      }
      if (actionRecorded[excursion.id] != true) {
        missingAction = true;
      }
    }
    return ExcursionAnalysis(
      count: excursions.length,
      aboveCount: above,
      belowCount: below,
      maxAboveExcess: aboveExcess,
      maxBelowShortfall: belowShortfall,
      observedDuration: confirmable.isEmpty
          ? null
          : _observedSpan(confirmable),
      confirmableEventCount: confirmable.length,
      gap: gap,
      open: open,
      missingAction: excursions.isNotEmpty && missingAction,
    );
  }

  OperationalRisk _risk({
    required int readingCount,
    required bool readingGap,
    required ExcursionAnalysis analysis,
  }) {
    final bool gap = readingGap || analysis.gap;
    final List<String> reasons = <String>[];
    if (readingCount == 0) {
      reasons.add('측정 데이터가 없습니다');
      return OperationalRisk(
        level: OperationalRiskLevel.unknown,
        reasons: reasons,
        gapLimitsJudgement: false,
      );
    }
    if (gap) {
      reasons.add('데이터 공백이 있어 빈 구간의 위험도는 판단할 수 없습니다');
      reasons.add('관측되지 않은 구간이 있어 위험 평가에 한계가 있음');
    }
    if (analysis.count == 0) {
      if (gap || readingCount < settings.minimumSamplesForLow) {
        if (readingCount < settings.minimumSamplesForLow) {
          reasons.add('관측된 측정이 ${settings.minimumSamplesForLow}회 미만입니다');
        }
        return OperationalRisk(
          level: OperationalRiskLevel.unknown,
          reasons: reasons,
          gapLimitsJudgement: gap,
        );
      }
      reasons.add('저장된 측정은 설정 범위 안이고 이탈 기록이 없습니다');
      reasons.add('데이터 공백 없음');
      return OperationalRisk(
        level: OperationalRiskLevel.low,
        reasons: reasons,
        gapLimitsJudgement: false,
      );
    }
    if (analysis.aboveCount > 0) {
      reasons.add('상한 이탈 ${analysis.aboveCount}회');
      if (analysis.maxAboveExcess != null) {
        reasons.add('최대 상한 초과 ${_celsius(analysis.maxAboveExcess!)}');
      }
    }
    if (analysis.belowCount > 0) {
      reasons.add('하한 이탈 ${analysis.belowCount}회');
      if (analysis.maxBelowShortfall != null) {
        reasons.add('최대 하한 미달 ${_celsius(analysis.maxBelowShortfall!)}');
      }
    }
    reasons.add(analysis.durationLabel);
    if (gap) {
      reasons.add('확인되지 않은 시간은 위험도에 더하지 않습니다');
    } else {
      reasons.add('데이터 공백 없음');
    }
    reasons.add(
      analysis.missingAction ? '원인 및 조치 기록: 미작성' : '원인 및 조치 기록: 작성 완료',
    );
    final double peak = _peak(analysis);
    final bool repeated = analysis.count >= settings.repeatedExcursionCount;
    final bool large = peak > settings.minorDeviationCelsius;
    final bool prolonged =
        analysis.observedDuration != null &&
        analysis.observedDuration! >= settings.longObservedDuration;
    if (prolonged) {
      reasons.add(
        '시연용 기준에서 관측된 이탈 지속시간이 ${settings.longObservedDuration.inSeconds}초 이상입니다',
      );
    }
    if (repeated || large || prolonged) {
      return OperationalRisk(
        level: OperationalRiskLevel.high,
        reasons: reasons,
        gapLimitsJudgement: gap,
      );
    }
    return OperationalRisk(
      level: OperationalRiskLevel.caution,
      reasons: reasons,
      gapLimitsJudgement: gap,
    );
  }

  double _peak(ExcursionAnalysis analysis) {
    final double above = analysis.maxAboveExcess ?? 0;
    final double below = analysis.maxBelowShortfall ?? 0;
    return above > below ? above : below;
  }

  String _celsius(double value) => '${value.toStringAsFixed(1)}°C';

  /// 공백이 없는 이탈만 합칩니다. 복귀 시각은 쓰지 않고, 겹치는 구간은 한 번만 더합니다.
  Duration _observedSpan(List<TemperatureExcursion> excursions) {
    final List<List<DateTime>> spans = <List<DateTime>>[];
    for (final TemperatureExcursion excursion in excursions) {
      final DateTime start = excursion.startedAt.toUtc();
      final DateTime end = excursion.lastOutOfRangeAt.toUtc();
      if (end.isBefore(start)) {
        continue;
      }
      spans.add(<DateTime>[start, end]);
    }
    if (spans.isEmpty) {
      return Duration.zero;
    }
    spans.sort(
      (List<DateTime> a, List<DateTime> b) => a.first.compareTo(b.first),
    );
    DateTime cursorStart = spans.first.first;
    DateTime cursorEnd = spans.first.last;
    Duration total = Duration.zero;
    for (int index = 1; index < spans.length; index++) {
      final DateTime start = spans[index].first;
      final DateTime end = spans[index].last;
      if (!start.isAfter(cursorEnd)) {
        if (end.isAfter(cursorEnd)) {
          cursorEnd = end;
        }
      } else {
        total += cursorEnd.difference(cursorStart);
        cursorStart = start;
        cursorEnd = end;
      }
    }
    total += cursorEnd.difference(cursorStart);
    return total;
  }
}
