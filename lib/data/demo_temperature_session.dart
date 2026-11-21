import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/shipment_record.dart';
import '../models/temperature_reading.dart';
import 'app_database.dart';
import 'auto_demo_policy.dart';
import 'temperature_policy.dart';

/// 앱이 실행 중인 동안 운송 중 건의 시연 온도를 한 타이머로 기록합니다.
///
/// 운송 건마다 타이머를 만들지 않습니다. 화면을 옮겨도 같은 앱 실행에서는
/// 이 객체가 생성을 이어 갑니다.
///
/// 로그아웃은 로그인 세션만 지웁니다. 타이머는 멈추지 않고, 이미 저장된
/// 온도 기록도 지우지 않습니다.
///
/// 앱이 백그라운드로 가거나 종료되면 생성을 보장하지 않습니다.
/// 그 구간은 데이터 공백이며, 다시 실행될 때 빈 시간을 측정값으로 채우지 않습니다.
/// 진행 중이던 시연 시나리오는 마지막 온도에서 이어 가고, 꺼진 동안의 단계는 건너뛰지 않습니다.
/// 이 기능은 실제 센서의 연속 모니터링이 아닙니다.
class DemoTemperatureSession with WidgetsBindingObserver, ChangeNotifier {
  DemoTemperatureSession({
    this.database,
    this.interval = const Duration(seconds: 5),
    DateTime Function()? clock,
    InRangeTemperaturePolicy? policy,
  }) : _clock = clock ?? DateTime.now,
       _policy = policy ?? InRangeTemperaturePolicy();

  static final DemoTemperatureSession instance = DemoTemperatureSession();

  final AppDatabase? database;
  final Duration interval;
  final DateTime Function() _clock;
  final InRangeTemperaturePolicy _policy;

  Timer? _timer;
  bool _ticking = false;
  bool _observing = false;

  AppDatabase get _db => database ?? AppDatabase.instance;

  bool get isRunning => _timer != null;

  /// 테스트에서 타이머가 하나만 있는지 확인합니다.
  int get activeTimerCount => _timer == null ? 0 : 1;

  void attach() {
    if (_observing) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  /// 이미 운송 중인 건이 있으면 지금부터 생성을 재개합니다.
  /// 종료되어 있던 시간의 온도는 만들지 않습니다.
  Future<void> restore() async {
    try {
      final List<ShipmentRecord> active = await _db.shipmentsInTransit();
      if (active.isEmpty) {
        pauseGeneration();
        return;
      }
      ensureRunning();
    } on StateError {
      pauseGeneration();
    }
  }

  void ensureRunning() {
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(interval, (Timer timer) {
      unawaited(recordDue());
    });
  }

  /// 백그라운드나 종료로 생성을 멈출 때 사용합니다. 기록은 남깁니다.
  void pauseGeneration() {
    _timer?.cancel();
    _timer = null;
  }

  /// 운송 중인 건마다 현재 시각의 온도를 최대 한 점만 추가합니다.
  /// 마지막 기록 이후 빈 시간이 길어도 그 사이를 채우지 않습니다.
  Future<void> recordDue({
    AutoDemoSettings autoSettings = const AutoDemoSettings(),
    PresentationSettings presentation = const PresentationSettings(),
    DemoRoll? autoRoll,
  }) async {
    if (_ticking) {
      return;
    }
    _ticking = true;
    var wrote = false;
    try {
      final List<ShipmentRecord> active = await _db.shipmentsInTransit();
      if (active.isEmpty) {
        pauseGeneration();
        return;
      }
      final DateTime now = _clock();
      for (final ShipmentRecord shipment in active) {
        final TemperatureReading? saved = await _db.recordDemoSample(
          shipmentId: shipment.id,
          at: now,
          policy: _policy,
          minimumGap: interval - const Duration(seconds: 1),
          autoSettings: autoSettings,
          presentation: presentation,
          autoRoll: autoRoll,
        );
        if (saved != null) {
          wrote = true;
        }
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'demo temperature',
          context: ErrorDescription('시연용 온도를 저장하는 중'),
        ),
      );
    } finally {
      _ticking = false;
    }
    if (wrote) {
      notifyListeners();
    }
  }

  void notifySamplesChanged() {
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(restore());
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        pauseGeneration();
    }
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    pauseGeneration();
    super.dispose();
  }
}
