import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/temperature_chart_model.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import '../theme/app_theme.dart';

/// 저장된 온도만 잇습니다. 15초를 넘는 구간은 선으로 연결하지 않습니다.
class TemperatureChartView extends StatefulWidget {
  const TemperatureChartView({
    super.key,
    required this.readings,
    required this.minBound,
    required this.maxBound,
    this.excursions = const <TemperatureExcursion>[],
    this.compact = false,
  });

  final List<TemperatureReading> readings;
  final double? minBound;
  final double? maxBound;
  final List<TemperatureExcursion> excursions;
  final bool compact;

  @override
  State<TemperatureChartView> createState() => _TemperatureChartViewState();
}

class _TemperatureChartViewState extends State<TemperatureChartView> {
  late TemperatureChartModel _model;
  double? _viewStart;
  double? _viewEnd;
  TemperatureChartPoint? _selected;
  TemperatureChartGap? _selectedGap;

  @override
  void initState() {
    super.initState();
    _rebuild(resetWindow: true);
  }

  @override
  void didUpdateWidget(TemperatureChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readings != widget.readings ||
        oldWidget.minBound != widget.minBound ||
        oldWidget.maxBound != widget.maxBound ||
        oldWidget.excursions != widget.excursions) {
      _rebuild(resetWindow: false);
    }
  }

  void _rebuild({required bool resetWindow}) {
    _model = buildTemperatureChart(
      readings: widget.readings,
      minBound: widget.minBound,
      maxBound: widget.maxBound,
      excursions: widget.excursions,
      maxPoints: widget.compact ? 120 : 360,
    );
    final List<TemperatureChartPoint> points = _model.points;
    if (points.isEmpty) {
      _viewStart = null;
      _viewEnd = null;
      _selected = null;
      return;
    }
    final double fullStart = _ms(points.first.measuredAt);
    final double fullEnd = _ms(points.last.measuredAt);
    final double span = fullEnd - fullStart;
    final double padded = span < 10000 ? 10000 : span;
    if (resetWindow || _viewStart == null || _viewEnd == null) {
      _viewStart = fullStart - padded * 0.02;
      _viewEnd = fullEnd + padded * 0.02;
      _selected = points.last;
      _selectedGap = null;
    }
  }

  double get _fullStart => _ms(_model.points.first.measuredAt);

  double get _fullEnd => _ms(_model.points.last.measuredAt);

  void _shift(double fraction) {
    final double? start = _viewStart;
    final double? end = _viewEnd;
    if (start == null || end == null) {
      return;
    }
    final double span = end - start;
    double nextStart = start + span * fraction;
    double nextEnd = end + span * fraction;
    final double minStart = _fullStart - span * 0.05;
    final double maxEnd = _fullEnd + span * 0.05;
    if (nextStart < minStart) {
      nextEnd += minStart - nextStart;
      nextStart = minStart;
    }
    if (nextEnd > maxEnd) {
      nextStart -= nextEnd - maxEnd;
      nextEnd = maxEnd;
    }
    setState(() {
      _viewStart = nextStart;
      _viewEnd = nextEnd;
    });
  }

  void _zoom(double factor) {
    final double? start = _viewStart;
    final double? end = _viewEnd;
    if (start == null || end == null) {
      return;
    }
    final double center = (start + end) / 2;
    double span = (end - start) * factor;
    const double minimum = 15000;
    final double maximum = (_fullEnd - _fullStart) * 1.2 + 20000;
    if (span < minimum) {
      span = minimum;
    }
    if (span > maximum) {
      span = maximum;
    }
    setState(() {
      _viewStart = center - span / 2;
      _viewEnd = center + span / 2;
    });
  }

  void _selectAt(double localX, double width) {
    const double left = 36;
    final double plot = (width - left).clamp(1, double.infinity);
    final double fraction = ((localX - left) / plot).clamp(0, 1);
    final double start = _viewStart ?? _fullStart;
    final double end = _viewEnd ?? _fullEnd;
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(
      (start + (end - start) * fraction).round(),
      isUtc: true,
    );
    TemperatureChartGap? gap;
    for (final TemperatureChartGap item in _model.gaps) {
      if (!at.isBefore(item.from.toUtc()) && !at.isAfter(item.to.toUtc())) {
        gap = item;
        break;
      }
    }
    TemperatureChartPoint? nearest;
    Duration nearestGap = const Duration(days: 1);
    final Duration window = Duration(
      milliseconds: ((end - start) * 0.08).round().clamp(1000, 86400000),
    );
    for (final TemperatureChartPoint point in _model.points) {
      final Duration difference = point.measuredAt.toUtc().difference(at).abs();
      if (difference < nearestGap) {
        nearestGap = difference;
        nearest = point;
      }
    }
    setState(() {
      _selectedGap = gap;
      _selected = nearestGap <= window ? nearest : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_model.sourceCount == 0 || _viewStart == null || _viewEnd == null) {
      return const Text(
        '측정 데이터가 없습니다',
        key: Key('temperature-chart-empty'),
      );
    }
    final double? minBound = widget.minBound;
    final double? maxBound = widget.maxBound;
    final TemperatureChartPoint? selected = _selected;
    final TemperatureExcursion? excursion = selected == null
        ? null
        : _excursionAt(selected.measuredAt);
    final bool above = _model.points.any(
      (TemperatureChartPoint point) =>
          maxBound != null && point.celsius > maxBound,
    );
    final bool below = _model.points.any(
      (TemperatureChartPoint point) =>
          minBound != null && point.celsius < minBound,
    );

    return Column(
      key: const Key('temperature-chart'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.compact ? '최근 온도 변화' : '시간별 온도 변화'),
        const Text(
          '시연용 가상 데이터입니다. 측정이 없는 구간은 추정하지 않습니다.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (minBound != null)
          Text(
            '설정 하한 ${minBound.toStringAsFixed(1)}°C',
            key: const Key('temperature-bound-min'),
          ),
        if (maxBound != null)
          Text(
            '설정 상한 ${maxBound.toStringAsFixed(1)}°C',
            key: const Key('temperature-bound-max'),
          ),
        if (above) const Text('상한 이탈 구간', key: Key('temperature-chart-above')),
        if (below) const Text('하한 이탈 구간', key: Key('temperature-chart-below')),
        if (_model.gaps.isNotEmpty)
          const Text('데이터 공백 구간', key: Key('temperature-chart-gap')),
        const SizedBox(height: 6),
        const _ChartLegend(),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.compact ? 150 : 240,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return GestureDetector(
                onHorizontalDragUpdate: (DragUpdateDetails details) {
                  final double span = _viewEnd! - _viewStart!;
                  _shift(-details.delta.dx / constraints.maxWidth);
                  if (span <= 0) {
                    return;
                  }
                },
                onScaleUpdate: (ScaleUpdateDetails details) {
                  if (details.pointerCount >= 2 && details.scale != 1) {
                    _zoom(details.scale > 1 ? 0.92 : 1.08);
                  }
                },
                onTapUp: (TapUpDetails details) {
                  _selectAt(details.localPosition.dx, constraints.maxWidth);
                },
                child: LineChart(
                  LineChartData(
                    minX: _viewStart,
                    maxX: _viewEnd,
                    minY: _minY(),
                    maxY: _maxY(),
                    clipData: const FlClipData.all(),
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    titlesData: _titles(),
                    rangeAnnotations: _ranges(),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: <HorizontalLine>[
                        if (minBound != null)
                          HorizontalLine(
                            y: minBound,
                            color: AppColors.teal,
                            strokeWidth: 1,
                            dashArray: <int>[4, 4],
                          ),
                        if (maxBound != null)
                          HorizontalLine(
                            y: maxBound,
                            color: AppColors.danger,
                            strokeWidth: 1,
                            dashArray: <int>[4, 4],
                          ),
                      ],
                    ),
                    lineBarsData: _bars(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              key: const Key('chart-pan-left'),
              onPressed: () => _shift(-0.25),
              child: const Text('이전'),
            ),
            TextButton(
              key: const Key('chart-pan-right'),
              onPressed: () => _shift(0.25),
              child: const Text('다음'),
            ),
            TextButton(
              key: const Key('chart-zoom-in'),
              onPressed: () => _zoom(0.6),
              child: const Text('확대'),
            ),
            TextButton(
              key: const Key('chart-zoom-out'),
              onPressed: () => _zoom(1.6),
              child: const Text('축소'),
            ),
          ],
        ),
        Text(
          selected == null
              ? '선택 지점: 없음'
              : '선택 지점: ${selected.celsius.toStringAsFixed(1)}°C · '
                    '${formatMeasurementTime(selected.measuredAt)}',
          key: const Key('temperature-chart-selection'),
        ),
        if (_selectedGap != null)
          Text(
            '데이터 공백 '
            '${formatMeasurementTime(_selectedGap!.from)} ~ '
            '${formatMeasurementTime(_selectedGap!.to)}',
            key: const Key('temperature-chart-selected-gap'),
          ),
        if (excursion != null)
          Text(
            '관련 이탈: ${excursion.directionLabel} · '
            '시작 ${formatMeasurementTime(excursion.startedAt)} · '
            '${excursion.durationLabel}',
            key: const Key('temperature-chart-excursion'),
          ),
      ],
    );
  }

  List<LineChartBarData> _bars() {
    final List<LineChartBarData> bars = <LineChartBarData>[];
    for (final List<TemperatureChartPoint> segment in _model.segments) {
      if (segment.isEmpty) {
        continue;
      }
      List<TemperatureChartPoint> run = <TemperatureChartPoint>[segment.first];
      _Zone runZone = _zone(segment.first.celsius);
      void addRun() {
        bars.add(
          LineChartBarData(
            spots: <FlSpot>[
              for (final TemperatureChartPoint point in run)
                FlSpot(_ms(point.measuredAt), point.celsius),
            ],
            isCurved: false,
            color: _color(runZone),
            barWidth: 2,
            dotData: FlDotData(show: run.length <= 40),
          ),
        );
      }

      for (int index = 1; index < segment.length; index++) {
        final _Zone nextZone = _zone(segment[index].celsius);
        if (nextZone == runZone) {
          run.add(segment[index]);
        } else {
          addRun();
          run = <TemperatureChartPoint>[segment[index - 1], segment[index]];
          runZone = nextZone;
        }
      }
      addRun();
    }
    return bars;
  }

  RangeAnnotations _ranges() {
    final double? minBound = widget.minBound;
    final double? maxBound = widget.maxBound;
    return RangeAnnotations(
      horizontalRangeAnnotations: <HorizontalRangeAnnotation>[
        if (minBound != null && maxBound != null)
          HorizontalRangeAnnotation(
            y1: minBound,
            y2: maxBound,
            color: AppColors.mint.withValues(alpha: 0.08),
          ),
      ],
      verticalRangeAnnotations: <VerticalRangeAnnotation>[
        for (final TemperatureChartGap gap in _model.gaps)
          VerticalRangeAnnotation(
            x1: _ms(gap.from),
            x2: _ms(gap.to),
            color: const Color(0xFF5C6B76).withValues(alpha: 0.28),
          ),
        for (final TemperatureExcursion excursion in widget.excursions)
          VerticalRangeAnnotation(
            x1: _ms(excursion.startedAt),
            x2: _ms(excursion.recoveredAt ?? excursion.lastOutOfRangeAt),
            color: (excursion.isAbove ? AppColors.danger : AppColors.warning)
                .withValues(alpha: 0.18),
          ),
      ],
    );
  }

  FlTitlesData _titles() {
    final double span = (_viewEnd ?? 0) - (_viewStart ?? 0);
    final double ySpan = _maxY() - _minY();
    final List<double> drawnX = <double>[];
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        axisNameWidget: const Text(
          '°C',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        axisNameSize: 16,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: ySpan <= 0 ? 1 : (ySpan / 4).clamp(0.5, 4).toDouble(),
          getTitlesWidget: (double value, TitleMeta meta) {
            return Text(
              value.toStringAsFixed(value.abs() >= 10 ? 0 : 1),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          minIncluded: false,
          maxIncluded: false,
          interval: span <= 0 ? null : span / 3,
          getTitlesWidget: (double value, TitleMeta meta) {
            for (final double previous in drawnX) {
              if ((meta.axisPosition - previous).abs() < 64) {
                return const SizedBox.shrink();
              }
            }
            drawnX.add(meta.axisPosition);
            final DateTime time = DateTime.fromMillisecondsSinceEpoch(
              value.round(),
              isUtc: true,
            );
            final String label = formatMeasurementTime(time);
            final String clock = label.length >= 8
                ? label.substring(label.length - 8)
                : label;
            return Text(
              clock,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
            );
          },
        ),
      ),
    );
  }

  double _minY() {
    double low = widget.minBound ?? _model.points.first.celsius;
    for (final TemperatureChartPoint point in _model.points) {
      if (point.celsius < low) {
        low = point.celsius;
      }
    }
    if (widget.maxBound != null && widget.maxBound! < low) {
      low = widget.maxBound!;
    }
    return low - 0.6;
  }

  double _maxY() {
    double high = widget.maxBound ?? _model.points.first.celsius;
    for (final TemperatureChartPoint point in _model.points) {
      if (point.celsius > high) {
        high = point.celsius;
      }
    }
    if (widget.minBound != null && widget.minBound! > high) {
      high = widget.minBound!;
    }
    return high + 0.6;
  }

  _Zone _zone(double celsius) {
    final double? maxBound = widget.maxBound;
    final double? minBound = widget.minBound;
    if (maxBound != null && celsius > maxBound) {
      return _Zone.above;
    }
    if (minBound != null && celsius < minBound) {
      return _Zone.below;
    }
    return _Zone.inside;
  }

  Color _color(_Zone zone) {
    return switch (zone) {
      _Zone.above => AppColors.danger,
      _Zone.below => AppColors.warning,
      _Zone.inside => AppColors.teal,
    };
  }

  TemperatureExcursion? _excursionAt(DateTime at) {
    for (final TemperatureExcursion excursion in widget.excursions) {
      final DateTime end = excursion.recoveredAt ?? excursion.lastOutOfRangeAt;
      if (!at.toUtc().isBefore(excursion.startedAt.toUtc()) &&
          !at.toUtc().isAfter(end.toUtc())) {
        return excursion;
      }
    }
    return null;
  }

  double _ms(DateTime time) => time.toUtc().millisecondsSinceEpoch.toDouble();
}

enum _Zone { inside, above, below }

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        _LegendSwatch(color: AppColors.teal, label: '정상 범위'),
        _LegendSwatch(color: AppColors.danger, label: '상한 이탈'),
        _LegendSwatch(color: AppColors.warning, label: '하한 이탈'),
        _LegendSwatch(color: AppColors.teal, label: '설정 하한선', dashed: true),
        _LegendSwatch(color: AppColors.danger, label: '설정 상한선', dashed: true),
        _LegendSwatch(color: Color(0xFF5C6B76), label: '데이터 공백'),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: dashed ? 2 : 8,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
