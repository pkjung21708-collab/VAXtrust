import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/auto_demo_policy.dart';
import '../data/demo_risk_settings.dart';
import '../data/response_manual.dart';
import '../screens/response_manual_screen.dart';
import '../data/shipment_analytics.dart';
import '../models/app_user.dart';
import '../models/demo_scenario.dart';
import '../models/excursion_action.dart';
import '../models/shipment_record.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import '../models/user_role.dart';
import '../screens/excursion_action_screen.dart';
import '../theme/app_theme.dart';
import 'dashboard_widgets.dart';

/// 운송 건 상세 상단의 온도 상태입니다.
class TemperatureStatusCard extends StatelessWidget {
  const TemperatureStatusCard({
    super.key,
    required this.user,
    required this.shipment,
    required this.latest,
    required this.excursions,
    required this.latestActions,
    required this.scenario,
    required this.onChanged,
    this.insight,
    this.onOpenRecords,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final TemperatureReading? latest;
  final List<TemperatureExcursion> excursions;
  final Map<int, ExcursionAction> latestActions;
  final DemoScenario? scenario;
  final Future<void> Function() onChanged;
  final ShipmentInsight? insight;
  final VoidCallback? onOpenRecords;

  bool get _isAssignee => user.id == shipment.assigneeUserId;

  bool get _canOperate => user.role == UserRole.transporter && _isAssignee;

  TemperatureExcursion? get _open {
    for (final TemperatureExcursion excursion in excursions) {
      if (excursion.isOpen) {
        return excursion;
      }
    }
    return null;
  }

  String _currentStatusLabel(TemperatureReading? latest) {
    if (latest == null) {
      return '측정 전';
    }
    if (shipment.tempMax != null && latest.celsius > shipment.tempMax!) {
      return '고온 이탈 (${latest.temperatureLabel})';
    }
    if (shipment.tempMin != null && latest.celsius < shipment.tempMin!) {
      return '저온 이탈 (${latest.temperatureLabel})';
    }
    return '정상 (${latest.temperatureLabel})';
  }

  bool _readingInRange(TemperatureReading? latest) {
    if (latest == null) {
      return false;
    }
    if (shipment.tempMax != null && latest.celsius > shipment.tempMax!) {
      return false;
    }
    if (shipment.tempMin != null && latest.celsius < shipment.tempMin!) {
      return false;
    }
    return true;
  }

  bool _showPastExcursionNote(TemperatureReading? latest) {
    final OperationalRiskLevel? level = insight?.risk.level;
    return _readingInRange(latest) &&
        excursions.isNotEmpty &&
        _open == null &&
        (level == OperationalRiskLevel.caution ||
            level == OperationalRiskLevel.high);
  }

  Color _riskColor(OperationalRiskLevel level) {
    return switch (level) {
      OperationalRiskLevel.low => AppColors.success,
      OperationalRiskLevel.caution => AppColors.warning,
      OperationalRiskLevel.high => AppColors.danger,
      OperationalRiskLevel.unknown => AppColors.textSecondary,
    };
  }

  Color get _statusColor {
    if (_open != null) {
      return AppColors.danger;
    }
    if (excursions.isNotEmpty) {
      return AppColors.warning;
    }
    if (latest == null) {
      return AppColors.textSecondary;
    }
    return AppColors.success;
  }

  Future<void> _start(BuildContext context, String type) async {
    Navigator.of(context).pop();
    try {
      await AppDatabase.instance.startDemoScenario(
        actorUserId: user.id,
        shipmentId: shipment.id,
        type: type,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시연을 시작했습니다. 온도가 범위를 벗어나면 이탈로 기록됩니다.')),
      );
      await onChanged();
    } on ExcursionException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _chooseScenario(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('scenario-door-open'),
                title: const Text('운송 용기 문 열림'),
                subtitle: const Text('잠시 상한을 넘긴 뒤 정상 범위로 돌아옵니다.'),
                onTap: () => _start(sheetContext, DemoScenario.doorOpen),
              ),
              ListTile(
                key: const Key('scenario-cooling-fault'),
                title: const Text('냉각 장치 이상'),
                subtitle: const Text('종료할 때까지 상한 이탈을 유지합니다.'),
                onTap: () => _start(sheetContext, DemoScenario.coolingFault),
              ),
              ListTile(
                key: const Key('scenario-overcool'),
                title: const Text('과냉각'),
                subtitle: const Text('잠시 하한 아래로 내려간 뒤 정상 범위로 돌아옵니다.'),
                onTap: () => _start(sheetContext, DemoScenario.overcool),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _end(BuildContext context) async {
    try {
      await AppDatabase.instance.endDemoScenario(
        actorUserId: user.id,
        shipmentId: shipment.id,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시연을 종료합니다. 온도는 정상 범위로 천천히 돌아옵니다.')),
      );
      await onChanged();
    } on ExcursionException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _record(BuildContext context) async {
    final TemperatureExcursion? open = _open;
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ExcursionActionScreen(
          excursionId: open?.id,
          shipmentId: shipment.id,
          initialSituationType: open == null
              ? null
              : open.isAbove
              ? ManualScenario.aboveMax
              : ManualScenario.belowMin,
          canEdit: _canOperate,
        ),
      ),
    );
    if (saved == true) {
      await onChanged();
    }
  }

  Future<void> _openAction(
    BuildContext context,
    TemperatureExcursion excursion,
  ) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ExcursionActionScreen(
          excursionId: excursion.id,
          canEdit: _canOperate,
        ),
      ),
    );
    if (saved == true) {
      await onChanged();
    }
  }

  Future<void> _showManual(
    BuildContext context,
    String scenarioType, {
    TemperatureExcursion? excursion,
  }) async {
    final ResponseManualEntry manual = ResponseManualCatalog.select(
      scenarioType: scenarioType,
      shipment: shipment,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ResponseManualScreen(
          manual: manual,
          appliedRangeLabel: shipment.temperatureRangeLabel,
          canRecord: _canOperate,
          onRecord: () {
            Navigator.of(context)
                .push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (BuildContext context) => ExcursionActionScreen(
                      excursionId: excursion?.id,
                      shipmentId: shipment.id,
                      initialSituationType: scenarioType,
                      canEdit: _canOperate,
                    ),
                  ),
                )
                .then((bool? saved) async {
                  if (saved == true) {
                    await onChanged();
                  }
                });
          },
        ),
      ),
    );
  }

  Future<void> _manual(BuildContext context) async {
    final TemperatureExcursion? open = _open;
    if (open != null) {
      await _showManual(
        context,
        open.isAbove ? ManualScenario.aboveMax : ManualScenario.belowMin,
        excursion: open,
      );
      return;
    }
    if (scenario != null &&
        scenario!.isActive &&
        scenario!.type == DemoScenario.coolingFault) {
      await _showManual(context, ManualScenario.coolingFault);
      return;
    }
    if (excursions.any((TemperatureExcursion item) => item.dataGapDetected) ||
        (insight?.hasGap ?? false)) {
      await _showManual(context, ManualScenario.dataGap);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final String type in <String>[
                ManualScenario.transportDelay,
                ManualScenario.physicalShock,
                ManualScenario.theftLoss,
                ManualScenario.coolingFault,
                ManualScenario.dataGap,
              ])
                ListTile(
                  key: Key('manual-choice-$type'),
                  title: Text(ExcursionAction.labelForSituation(type)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showManual(context, type);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _medicalSummary({
    required TemperatureReading? latest,
    required TemperatureExcursion? open,
    required ExcursionAction? openAction,
  }) {
    final String excursionLabel = open != null
        ? (open.isAbove ? '고온 이탈' : '저온 이탈')
        : excursions.isEmpty
        ? '없음'
        : '있음';
    return Container(
      key: const Key('temperature-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '온도 이탈: $excursionLabel',
            key: const Key('temperature-status-label'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: open != null
                  ? AppColors.danger
                  : excursions.isEmpty
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ),
          if (open != null) ...[
            const SizedBox(height: 8),
            const Text(
              '온도 이탈 감지',
              key: Key('active-excursion-alert'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
          ],
          if (open == null &&
              excursions.any(
                (TemperatureExcursion item) => item.dataGapDetected,
              ))
            const Text(
              '데이터 공백이 있습니다. 공백은 온도 이탈과 같지 않습니다.',
              key: Key('data-gap-alert'),
            ),
          Text(
            latestActions.isEmpty ? '대응 기록: 없음' : '대응 기록: 있음',
          ),
          if (_showPastExcursionNote(latest))
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '현재 온도는 정상 범위이지만, 과거 온도 이탈 기록으로 인해 추가 품질 검토가 필요합니다.',
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            '검토 결과는 접종 가능 여부를 정하지 않습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          DisclosureBlock(
            label: '온도 상세',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latest == null
                      ? '현재 온도: 측정 전'
                      : '현재 온도: ${latest.temperatureLabel}',
                ),
                Text('허용 범위: ${shipment.temperatureRangeLabel}'),
                Text(
                  '마지막 측정: ${latest == null ? '없음' : formatMeasurementTime(latest.measuredAt)}',
                ),
                const Text('시연용 가상 데이터'),
                if (insight != null) ...[
                  Text('누적 운송 위험도: ${insight!.risk.level.label}'),
                  for (final String reason in insight!.risk.reasons)
                    Text('판단 근거: $reason'),
                  const Text(DemoRiskSettings.title),
                  const Text(DemoRiskSettings.durationBasis),
                  const Text(DemoRiskSettings.limitation),
                ],
                if (open != null && openAction != null)
                  Text('원인 기록: ${openAction.categoryLabel}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TemperatureReading? latest = this.latest;
    final TemperatureExcursion? open = _open;
    final double? min = shipment.tempMin;
    final double? max = shipment.tempMax;
    final bool canStart =
        _canOperate &&
        shipment.status == ShipmentStatus.inTransit &&
        scenario == null;
    final bool canEnd =
        _canOperate &&
        scenario != null &&
        (scenario!.phase == DemoScenario.rising ||
            scenario!.phase == DemoScenario.holding);
    final ExcursionAction? openAction = open == null
        ? null
        : latestActions[open.id];
    if (user.role == UserRole.medicalStaff) {
      return _medicalSummary(
        latest: latest,
        open: open,
        openAction: openAction,
      );
    }

    return Container(
      key: const Key('temperature-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 온도',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            latest == null ? '측정 전' : latest.temperatureLabel,
            style: TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: open == null ? AppColors.textPrimary : AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '현재 온도 상태: ${_currentStatusLabel(latest)}',
            key: const Key('temperature-status-label'),
            style: TextStyle(color: _statusColor, fontWeight: FontWeight.w800),
          ),
          Text('허용 범위: ${shipment.temperatureRangeLabel}'),
          Text(
            '마지막 측정: ${latest == null ? '없음' : formatMeasurementTime(latest.measuredAt)}',
          ),
          const Text(
            '시연용 가상 데이터',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (open != null) ...[
            const SizedBox(height: 8),
            Text(
              open.isAbove ? '고온 이탈' : '저온 이탈',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
            if (latest != null && max != null && open.isAbove)
              Text(
                '현재 ${latest.temperatureLabel} · 상한 초과 +${(latest.celsius - max).toStringAsFixed(1)}°C',
              ),
            if (latest != null && min != null && !open.isAbove)
              Text(
                '현재 ${latest.temperatureLabel} · 하한 미달 -${(min - latest.celsius).toStringAsFixed(1)}°C',
              ),
          ],
          if (insight != null)
            Text(
              '누적 운송 위험도: ${insight!.risk.level.label}',
              key: const Key('operational-risk-level'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _riskColor(insight!.risk.level),
              ),
            ),
          if (_showPastExcursionNote(latest))
            const Text(
              '현재 온도는 정상 범위이지만, 과거 온도 이탈 기록으로 인해 추가 품질 검토가 필요합니다.',
            ),
          if (open != null || insight != null)
            DisclosureBlock(
              label: '판단 근거 보기',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('설정 범위: ${shipment.temperatureRangeLabel}'),
                  Text(
                    excursions.isEmpty
                        ? '과거 온도 이탈 이력: 없음'
                        : '과거 온도 이탈 이력: ${excursions.length}건',
                  ),
                  if (DemoMode.label(shipment.demoMode) != null)
                    Text('시연 방식: ${DemoMode.label(shipment.demoMode)}'),
                  Text('데이터 출처: ${latest == null ? '없음' : latest.sourceLabel}'),
                  if (open != null)
                    Text('이탈 시작: ${formatMeasurementTime(open.startedAt)}'),
                  if (open != null)
                    Text('원인 기록: ${openAction == null ? '미작성' : '작성 완료'}'),
                  Text('온도 이탈 이력: ${excursions.isEmpty ? '없음' : '있음'}'),
                  if (insight != null) ...[
                    for (final String reason in insight!.risk.reasons)
                      Text('판단 근거: $reason'),
                    if (insight!.risk.gapLimitsJudgement)
                      const Text('데이터 공백 구간의 위험도는 판단할 수 없습니다'),
                    Text(
                      insight!.excursions.aboveCount == 0
                          ? '상한 이탈 ${insight!.excursions.aboveCount}회'
                          : '상한 이탈 ${insight!.excursions.aboveCount}회 · 최대 초과 ${insight!.excursions.maxAboveExcess?.toStringAsFixed(1) ?? '-'}°C',
                    ),
                    Text(
                      insight!.excursions.belowCount == 0
                          ? '하한 이탈 ${insight!.excursions.belowCount}회'
                          : '하한 이탈 ${insight!.excursions.belowCount}회 · 최대 미달 ${insight!.excursions.maxBelowShortfall?.toStringAsFixed(1) ?? '-'}°C',
                    ),
                    Text(insight!.excursions.durationLabel),
                    const Text(DemoRiskSettings.title),
                    const Text(DemoRiskSettings.durationBasis),
                    const Text(DemoRiskSettings.limitation),
                  ],
                ],
              ),
            ),
          if (user.role == UserRole.medicalStaff)
            const Text(
              '검토 결과는 접종 가능 여부를 정하지 않습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          if (scenario != null && scenario!.isActive)
            Text('시연: ${scenario!.typeLabel} · ${scenario!.phaseLabel}'),
          if (open != null) ...[
            const SizedBox(height: 8),
            const Text(
              '온도 이탈 감지',
              key: Key('active-excursion-alert'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
            const Text(
              '현재 온도가 허용 범위를 벗어났습니다. 시연용 가상 데이터입니다.',
            ),
          ],
          if (open == null &&
              excursions.any(
                (TemperatureExcursion item) => item.dataGapDetected,
              ))
            const Text(
              '데이터 공백이 있습니다. 공백은 온도 이탈과 같지 않습니다.',
              key: Key('data-gap-alert'),
            ),
          if (scenario != null &&
              scenario!.isActive &&
              scenario!.type == DemoScenario.coolingFault)
            Text(
              scenario!.isAuto
                  ? '냉각 장치 이상 가상 시연입니다. 앱이 실제 장비 고장을 감지한 것은 아닙니다.'
                  : '냉각 장치 이상 시연입니다. 앱이 실제 장비 고장을 감지한 것은 아닙니다.',
              key: const Key('cooling-fault-alert'),
            ),
          if (shipment.autoGapSkips > 0)
            const Text(
              '온도 데이터 공백 시연 중입니다. 가상 데이터이며 이 공백을 온도 이탈로 기록하지 않습니다.',
              key: Key('auto-gap-note'),
            ),
          const SizedBox(height: 8),
          if (_canOperate && shipment.demoMode != null && (canStart || canEnd))
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: const Key('manual-scenario-folder'),
                title: const Text('수동 시연'),
                children: [
                  if (canStart)
                    OutlinedButton(
                      key: const Key('demo-scenario-button'),
                      onPressed: () => _chooseScenario(context),
                      child: const Text('시연용 이상 상황 발생'),
                    ),
                  if (canEnd)
                    OutlinedButton(
                      key: const Key('end-demo-scenario'),
                      onPressed: () => _end(context),
                      child: const Text('시연 종료'),
                    ),
                ],
              ),
            ),
          if (_canOperate && shipment.demoMode == null && canStart)
            OutlinedButton(
              key: const Key('demo-scenario-button'),
              onPressed: () => _chooseScenario(context),
              child: const Text('시연용 이상 상황 발생'),
            ),
          if (_canOperate && shipment.demoMode == null && canEnd)
            OutlinedButton(
              key: const Key('end-demo-scenario'),
              onPressed: () => _end(context),
              child: const Text('시연 종료'),
            ),
          if (user.role == UserRole.transporter)
            open != null
                ? ElevatedButton(
                    key: const Key('response-manual-button'),
                    onPressed: () => _manual(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('대응 매뉴얼'),
                  )
                : TextButton(
                    key: const Key('response-manual-button'),
                    onPressed: () => _manual(context),
                    child: const Text('대응 매뉴얼'),
                  ),
          if (_canOperate && shipment.status == ShipmentStatus.inTransit)
            ElevatedButton(
              key: const Key('record-response-button'),
              onPressed: () => _record(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('조치 기록'),
            ),
          if (_canOperate && onOpenRecords != null)
            OutlinedButton(
              key: const Key('my-response-records-button'),
              onPressed: onOpenRecords,
              child: const Text('내 대응 기록'),
            ),
          const SizedBox(height: 8),
          ExcursionHistoryPreview(
            excursions: excursions,
            latestActions: latestActions,
            onOpen: (TemperatureExcursion excursion) =>
                _openAction(context, excursion),
          ),
          if (_canOperate && open != null)
            ElevatedButton(
              key: const Key('open-excursion-action'),
              onPressed: () => _openAction(context, open),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('원인 및 조치 기록'),
            ),
          if (user.role == UserRole.qualityManager)
            DisclosureBlock(
              label: '대응 매뉴얼',
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _manual(context),
                  child: const Text('매뉴얼 열기'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 최근 이탈이 위에 오도록 정렬합니다. 시각이 같으면 기록 ID를 사용합니다.
List<TemperatureExcursion> excursionsNewestFirst(
  List<TemperatureExcursion> source,
) {
  final List<TemperatureExcursion> sorted = List<TemperatureExcursion>.of(
    source,
  );
  sorted.sort((TemperatureExcursion a, TemperatureExcursion b) {
    final int byTime = b.startedAt.compareTo(a.startedAt);
    if (byTime != 0) {
      return byTime;
    }
    return b.id.compareTo(a.id);
  });
  return sorted;
}

class ExcursionHistoryPreview extends StatefulWidget {
  const ExcursionHistoryPreview({
    super.key,
    required this.excursions,
    required this.latestActions,
    required this.onOpen,
  });

  final List<TemperatureExcursion> excursions;
  final Map<int, ExcursionAction> latestActions;
  final ValueChanged<TemperatureExcursion> onOpen;

  @override
  State<ExcursionHistoryPreview> createState() =>
      _ExcursionHistoryPreviewState();
}

class _ExcursionHistoryPreviewState extends State<ExcursionHistoryPreview> {
  int _shown = 3;

  @override
  Widget build(BuildContext context) {
    final List<TemperatureExcursion> sorted = excursionsNewestFirst(
      widget.excursions,
    );
    final bool open = sorted.any((TemperatureExcursion item) => item.isOpen);
    final int visibleCount = _shown < sorted.length ? _shown : sorted.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '온도 이탈 ${sorted.length}건 · 진행 중 ${open ? '있음' : '없음'}',
          key: const Key('excursion-summary'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (sorted.isEmpty)
          const Text('온도 이탈 기록이 없습니다.')
        else ...[
          const SizedBox(height: 4),
          for (final TemperatureExcursion excursion
              in sorted.take(visibleCount))
            _row(excursion),
          if (sorted.length > visibleCount)
            TextButton(
              key: const Key('show-all-excursions'),
              onPressed: () => setState(() {
                _shown = _shown + 20 < sorted.length
                    ? _shown + 20
                    : sorted.length;
              }),
              child: Text(_shown == 3 ? '전체 이탈 기록 보기' : '이전 기록 더 보기'),
            ),
        ],
      ],
    );
  }

  Widget _row(TemperatureExcursion excursion) {
    final ExcursionAction? action = widget.latestActions[excursion.id];
    return Material(
      color: AppColors.card,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        key: Key('excursion-row-${excursion.id}'),
        title: Text('${excursion.statusLabel} · ${excursion.durationLabel}'),
        subtitle: Text(
          '시작 ${formatMeasurementTime(excursion.startedAt)} · '
          '${excursion.recoveredAt == null ? '진행 중' : '복귀 ${formatMeasurementTime(excursion.recoveredAt)}'}\n'
          '원인: ${action == null ? '미작성' : action.categoryLabel}',
        ),
        onTap: () => widget.onOpen(excursion),
      ),
    );
  }
}
