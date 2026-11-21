import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';

/// 그래프에 그릴 점입니다. 원본 온도 기록의 복사본이며 저장값을 바꾸지 않습니다.
class TemperatureChartPoint {
  const TemperatureChartPoint({
    required this.measuredAt,
    required this.celsius,
    required this.readingId,
  });

  final DateTime measuredAt;
  final double celsius;
  final int readingId;
}

class TemperatureChartGap {
  const TemperatureChartGap({required this.from, required this.to});

  final DateTime from;
  final DateTime to;
}

class TemperatureChartModel {
  const TemperatureChartModel({
    required this.segments,
    required this.gaps,
    required this.sourceCount,
  });

  final List<List<TemperatureChartPoint>> segments;
  final List<TemperatureChartGap> gaps;
  final int sourceCount;

  int get displayCount {
    int count = 0;
    for (final List<TemperatureChartPoint> segment in segments) {
      count += segment.length;
    }
    return count;
  }

  List<TemperatureChartPoint> get points {
    return <TemperatureChartPoint>[
      for (final List<TemperatureChartPoint> segment in segments) ...segment,
    ];
  }
}

/// 측정 간격이 길면 선을 끊고, 점을 줄여도 최고·최저와 경계 통과 점은 남깁니다.
TemperatureChartModel buildTemperatureChart({
  required List<TemperatureReading> readings,
  required double? minBound,
  required double? maxBound,
  List<TemperatureExcursion> excursions = const <TemperatureExcursion>[],
  int maxPoints = 360,
  Duration gapAfter = TemperatureExcursion.gapAfter,
}) {
  final List<TemperatureReading> ordered = List<TemperatureReading>.of(readings)
    ..sort((TemperatureReading a, TemperatureReading b) {
      final int byTime = a.measuredAt.compareTo(b.measuredAt);
      if (byTime != 0) {
        return byTime;
      }
      return a.id.compareTo(b.id);
    });
  if (ordered.isEmpty) {
    return const TemperatureChartModel(
      segments: <List<TemperatureChartPoint>>[],
      gaps: <TemperatureChartGap>[],
      sourceCount: 0,
    );
  }
  final List<List<TemperatureReading>> groups = <List<TemperatureReading>>[
    <TemperatureReading>[ordered.first],
  ];
  final List<TemperatureChartGap> gaps = <TemperatureChartGap>[];
  for (int index = 1; index < ordered.length; index++) {
    final TemperatureReading previous = ordered[index - 1];
    final TemperatureReading current = ordered[index];
    final Duration gap = current.measuredAt.toUtc().difference(
      previous.measuredAt.toUtc(),
    );
    if (gap > gapAfter) {
      gaps.add(
        TemperatureChartGap(from: previous.measuredAt, to: current.measuredAt),
      );
      groups.add(<TemperatureReading>[current]);
    } else {
      groups.last.add(current);
    }
  }
  final int budget = maxPoints < groups.length ? groups.length : maxPoints;
  int remaining = budget;
  final List<List<TemperatureChartPoint>> segments =
      <List<TemperatureChartPoint>>[];
  for (int index = 0; index < groups.length; index++) {
    final int slots = index == groups.length - 1
        ? remaining
        : (remaining / (groups.length - index)).ceil();
    final int used = slots < 1 ? 1 : slots;
    remaining -= used;
    if (remaining < 0) {
      remaining = 0;
    }
    segments.add(
      _downsample(
        groups[index],
        used,
        minBound: minBound,
        maxBound: maxBound,
        excursions: excursions,
      ),
    );
  }
  return TemperatureChartModel(
    segments: segments,
    gaps: gaps,
    sourceCount: ordered.length,
  );
}

List<TemperatureChartPoint> _downsample(
  List<TemperatureReading> readings,
  int maxPoints, {
  required double? minBound,
  required double? maxBound,
  required List<TemperatureExcursion> excursions,
}) {
  if (readings.length <= maxPoints) {
    return readings.map(_point).toList();
  }
  final Set<int> keep = <int>{0, readings.length - 1};
  int minIndex = 0;
  int maxIndex = 0;
  for (int index = 1; index < readings.length; index++) {
    if (readings[index].celsius < readings[minIndex].celsius) {
      minIndex = index;
    }
    if (readings[index].celsius > readings[maxIndex].celsius) {
      maxIndex = index;
    }
    final double previous = readings[index - 1].celsius;
    final double current = readings[index].celsius;
    if (_crossed(previous, current, minBound) ||
        _crossed(previous, current, maxBound)) {
      keep.add(index - 1);
      keep.add(index);
    }
  }
  keep.add(minIndex);
  keep.add(maxIndex);
  for (final TemperatureExcursion excursion in excursions) {
    final int? low = _closestExtreme(
      readings,
      excursion.minTemperature,
      excursion,
    );
    final int? high = _closestExtreme(
      readings,
      excursion.maxTemperature,
      excursion,
    );
    if (low != null) {
      keep.add(low);
    }
    if (high != null) {
      keep.add(high);
    }
    final int? started = _indexAtOrAfter(readings, excursion.startedAt);
    if (started != null &&
        !readings[started].measuredAt.toUtc().isAfter(
          excursion.lastOutOfRangeAt.toUtc(),
        )) {
      keep.add(started);
    }
    final DateTime? recovered = excursion.recoveredAt;
    if (recovered != null) {
      final int? back = _indexAtOrAfter(readings, recovered);
      if (back != null) {
        keep.add(back);
      }
    }
  }
  if (keep.length < maxPoints) {
    final int stride = (readings.length / (maxPoints - keep.length)).ceil();
    for (int index = 0; index < readings.length; index += stride) {
      keep.add(index);
      if (keep.length >= maxPoints) {
        break;
      }
    }
  }
  final List<int> ordered = keep.toList()..sort();
  return ordered.map((int index) => _point(readings[index])).toList();
}

bool _crossed(double previous, double current, double? bound) {
  if (bound == null) {
    return false;
  }
  return (previous - bound) * (current - bound) < 0 ||
      previous == bound ||
      current == bound && previous != bound;
}

int? _indexAtOrAfter(List<TemperatureReading> readings, DateTime time) {
  final DateTime target = time.toUtc();
  for (int index = 0; index < readings.length; index++) {
    if (!readings[index].measuredAt.toUtc().isBefore(target)) {
      return index;
    }
  }
  return null;
}

int? _closestExtreme(
  List<TemperatureReading> readings,
  double target,
  TemperatureExcursion excursion,
) {
  int? best;
  double bestDistance = double.infinity;
  for (int index = 0; index < readings.length; index++) {
    final DateTime at = readings[index].measuredAt.toUtc();
    if (at.isBefore(excursion.startedAt.toUtc()) ||
        at.isAfter(excursion.lastOutOfRangeAt.toUtc())) {
      continue;
    }
    final double distance = (readings[index].celsius - target).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index;
    }
  }
  return best;
}

TemperatureChartPoint _point(TemperatureReading reading) {
  return TemperatureChartPoint(
    measuredAt: reading.measuredAt,
    celsius: reading.celsius,
    readingId: reading.id,
  );
}
