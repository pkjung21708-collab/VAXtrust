import 'shipment_record.dart';

/// 운송 건에 쌓인 온도 한 점입니다.
///
/// [measuredAt]은 측정 시각이고 [recordedAt]은 이 기기에 저장된 시각입니다.
/// 시연용 가상 데이터는 두 시각을 생성 시점의 현재 시각으로 같이 기록합니다.
/// 앱이 꺼져 있던 시간을 과거 측정처럼 채우지 않습니다.
class TemperatureReading {
  const TemperatureReading({
    required this.id,
    required this.shipmentId,
    required this.celsius,
    required this.measuredAt,
    required this.recordedAt,
    required this.source,
    required this.assigneeUserId,
  });

  /// 실제 센서가 아닌 시연용 생성값입니다.
  static const String demoVirtualSource = 'demo_virtual';

  final int id;
  final int shipmentId;
  final double celsius;
  final DateTime measuredAt;
  final DateTime recordedAt;
  final String source;

  /// 이 값이 만들어질 때의 담당 운송자입니다.
  final int assigneeUserId;

  bool get isDemoVirtual => source == demoVirtualSource;

  String get sourceLabel => isDemoVirtual ? '시연용 가상 데이터' : '알 수 없는 출처';

  String get temperatureLabel => TemperatureBounds.formatCelsius(celsius);
}
