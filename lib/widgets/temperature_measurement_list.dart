import 'package:flutter/material.dart';

import '../models/temperature_reading.dart';
import '../theme/app_theme.dart';

/// 저장된 온도와 운송 건의 허용 범위를 비교한 표시 상태입니다.
/// 측정값이 없는 구간은 행으로 만들지 않습니다.
String measurementRangeStatus({
  required double celsius,
  required double? min,
  required double? max,
}) {
  if (max != null && celsius > max) {
    return '고온 이탈';
  }
  if (min != null && celsius < min) {
    return '저온 이탈';
  }
  return '정상';
}

String formatMeasurementClock(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String formatMeasurementDay(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// 최신 측정이 위에 오는 온도 기록 목록입니다.
/// [readings]는 측정 시각, 같으면 기록 ID 내림차순이어야 합니다.
class TemperatureMeasurementList extends StatelessWidget {
  const TemperatureMeasurementList({
    super.key,
    required this.readings,
    required this.tempMin,
    required this.tempMax,
    required this.totalCount,
    required this.onLoadMore,
  });

  final List<TemperatureReading> readings;
  final double? tempMin;
  final double? tempMax;
  final int totalCount;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final List<TemperatureReading> unique = <TemperatureReading>[];
    final Set<int> seen = <int>{};
    for (final TemperatureReading reading in readings) {
      if (seen.add(reading.id)) {
        unique.add(reading);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '시연용 가상 데이터 · 5초 간격 측정',
          key: Key('temperature-record-header'),
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (unique.isEmpty) const Text('온도 기록이 없습니다.') else ..._rows(unique),
        if (totalCount > unique.length)
          TextButton(
            key: const Key('load-older-temperatures'),
            onPressed: onLoadMore,
            child: const Text('이전 기록 더 보기'),
          ),
      ],
    );
  }

  List<Widget> _rows(List<TemperatureReading> unique) {
    final List<Widget> rows = <Widget>[];
    DateTime? newerDay;
    for (final TemperatureReading reading in unique) {
      final DateTime day = DateTime(
        reading.measuredAt.toLocal().year,
        reading.measuredAt.toLocal().month,
        reading.measuredAt.toLocal().day,
      );
      if (newerDay != null && day != newerDay) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              formatMeasurementDay(reading.measuredAt),
              key: Key(
                'temperature-day-${formatMeasurementDay(reading.measuredAt)}',
              ),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      }
      newerDay = day;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${formatMeasurementClock(reading.measuredAt)}'
            '    ${reading.temperatureLabel}'
            '    ${measurementRangeStatus(celsius: reading.celsius, min: tempMin, max: tempMax)}',
            key: Key('temperature-row-${reading.id}'),
          ),
        ),
      );
    }
    return rows;
  }
}
