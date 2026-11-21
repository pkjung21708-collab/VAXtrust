import 'package:flutter/material.dart';

import '../models/excursion_action.dart';
import '../models/temperature_excursion.dart';
import '../theme/app_theme.dart';

/// 운송자와 품질관리자가 같은 조치 기록을 역할에 맞는 제목으로 봅니다.
class ResponseRecordPanel extends StatelessWidget {
  const ResponseRecordPanel({
    super.key,
    required this.title,
    required this.sectionKey,
    required this.actions,
    required this.excursions,
    required this.emptyLabel,
    this.noticeUnlinkedExcursions = false,
  });

  final String title;
  final Key sectionKey;
  final List<ExcursionAction> actions;
  final List<TemperatureExcursion> excursions;
  final String emptyLabel;
  final bool noticeUnlinkedExcursions;

  @override
  Widget build(BuildContext context) {
    final List<ExcursionAction> unlinked = actions
        .where((ExcursionAction action) => action.excursionId == null)
        .toList();
    final bool missingLink =
        noticeUnlinkedExcursions &&
        excursions.any(
          (TemperatureExcursion excursion) => !actions.any(
            (ExcursionAction action) => action.excursionId == excursion.id,
          ),
        );
    return Container(
      key: sectionKey,
      width: double.infinity,
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
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '시연용 가상 온도에 대해 사람이 입력한 기록입니다. 매뉴얼을 열거나 이상이 발생한 것만으로 조치가 완료되지 않습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (actions.isEmpty)
            Text(emptyLabel)
          else
            for (final ExcursionAction action in actions)
              if (action.excursionId != null)
                _ActionBlock(
                  action: action,
                  excursion: _match(action.excursionId),
                ),
          if (unlinked.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '이벤트에 연결되지 않은 기록',
              key: Key('unlinked-response-record'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final ExcursionAction action in unlinked)
              _ActionBlock(action: action, excursion: null),
          ],
          if (missingLink)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '온도 이탈이 기록되었으나 연결된 운송자 대응 보고는 없습니다.',
                key: Key('missing-linked-report'),
              ),
            ),
        ],
      ),
    );
  }

  TemperatureExcursion? _match(int? id) {
    for (final TemperatureExcursion excursion in excursions) {
      if (excursion.id == id) {
        return excursion;
      }
    }
    return null;
  }
}

class _ActionBlock extends StatelessWidget {
  const _ActionBlock({required this.action, required this.excursion});

  final ExcursionAction action;
  final TemperatureExcursion? excursion;

  @override
  Widget build(BuildContext context) {
    final TemperatureExcursion? linked = excursion;
    final String link = action.excursionId == null
        ? '별도 상황 보고'
        : linked == null
        ? '연결된 온도 이탈 이벤트 ${action.excursionId}'
        : '연결된 온도 이탈: ${linked.directionLabel} · '
              '${formatMeasurementTime(linked.startedAt)} · '
              '최저 ${linked.minTemperature.toStringAsFixed(1)}°C · '
              '최고 ${linked.maxTemperature.toStringAsFixed(1)}°C';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '${formatMeasurementTime(action.createdAt)}\n'
        '상황 유형: ${action.situationType == null ? '확인되지 않음' : action.situationLabel}\n'
        '$link\n'
        '원인: ${action.description}\n'
        '조치: ${action.actionTaken}\n'
        '${action.contactLabel}\n'
        '${action.holdLabel}',
        key: Key('response-record-${action.id}'),
      ),
    );
  }
}
