import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaxtrust/data/app_database.dart';
import 'package:vaxtrust/data/auto_demo_policy.dart';
import 'package:vaxtrust/data/demo_risk_settings.dart';
import 'package:vaxtrust/data/demo_temperature_session.dart';
import 'package:vaxtrust/data/shipment_analytics.dart';
import 'package:vaxtrust/data/temperature_chart_model.dart';
import 'package:vaxtrust/data/temperature_policy.dart';
import 'package:vaxtrust/data/vaccine_catalog.dart';
import 'package:vaxtrust/models/app_user.dart';
import 'package:vaxtrust/models/demo_scenario.dart';
import 'package:vaxtrust/models/excursion_action.dart';
import 'package:vaxtrust/models/shipment_record.dart';
import 'package:vaxtrust/models/temperature_excursion.dart';
import 'package:vaxtrust/models/temperature_reading.dart';
import 'package:vaxtrust/models/user_role.dart';
import 'package:vaxtrust/widgets/response_record_panel.dart';
import 'package:vaxtrust/widgets/temperature_measurement_list.dart';
import 'package:vaxtrust/widgets/temperature_status_card.dart';

double _tenth(double value) => (value * 10).round() / 10;

void main() {
  late Directory tempDir;
  late String databasePath;
  late AppDatabase database;
  late DateTime now;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vaxtrust_auto_demo_');
    databasePath = '${tempDir.path}${Platform.pathSeparator}vaxtrust.db';
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    now = DateTime.now().toUtc();
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const NewShipment refrigerated = NewShipment(
    vaccine: '스카이셀플루4가프리필드시린지',
    manufacturer: '에스케이바이오사이언스(주)',
    lot: 'LOT-AUTO',
    expiryDate: '2027-11-20',
    quantity: 10,
    origin: '창고',
    destination: '병원',
    targetRange: '2 ~ 8°C',
    tempMin: 2,
    tempMax: 8,
  );

  Future<AppUser> courier() {
    return database.createUser(
      loginId: 'courier',
      password: 'demo1234',
      role: UserRole.transporter,
    );
  }

  Future<ShipmentRecord> start(
    AppUser user,
    NewShipment draft, {
    String? mode,
  }) async {
    final ShipmentRecord created = await database.createShipment(
      ownerUserId: user.id,
      draft: draft,
    );
    return database.startTransport(
      actorUserId: user.id,
      shipmentId: created.id,
      demoMode: mode,
    );
  }

  Future<TemperatureReading?> tick(
    ShipmentRecord shipment, {
    AutoDemoSettings settings = const AutoDemoSettings(),
    PresentationSettings presentation = const PresentationSettings(),
    DemoRoll? roll,
    InRangeTemperaturePolicy? policy,
  }) {
    now = now.add(const Duration(seconds: 5));
    return database.recordDemoSample(
      shipmentId: shipment.id,
      at: now,
      policy: policy ?? InRangeTemperaturePolicy(),
      minimumGap: const Duration(seconds: 4),
      autoSettings: settings,
      presentation: presentation,
      autoRoll: roll,
    );
  }

  test('일반 자동 시연은 처음 구간을 설정 범위 안에 둔다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.probabilistic,
    );
    const AutoDemoSettings settings = AutoDemoSettings(eventChance: 1);
    final DemoRoll always = DemoRoll(unit: () => 0, pick: (int max) => 0);
    final List<TemperatureReading> samples = <TemperatureReading>[
      (await database.latestTemperature(shipment.id))!,
    ];
    for (var index = 0; index < settings.minimumNormalSamples - 1; index++) {
      samples.add((await tick(shipment, settings: settings, roll: always))!);
    }
    expect(samples, hasLength(settings.minimumNormalSamples));
    expect(
      samples.every(
        (TemperatureReading sample) =>
            sample.celsius >= 2 && sample.celsius <= 8,
      ),
      isTrue,
    );
    expect(await database.tableRows('excursion_actions'), isEmpty);
  });

  test('일반 자동 시연은 확률에 따라 고온 이탈을 만들고 복귀한다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.probabilistic,
    );
    const AutoDemoSettings settings = AutoDemoSettings(
      minimumNormalSamples: 2,
      cooldownSamples: 30,
      eventChance: 1,
      holdSamples: 2,
    );
    final DemoRoll high = DemoRoll(unit: () => 0, pick: (int max) => 0);
    final List<double> values = <double>[];
    for (var index = 0; index < 20; index++) {
      final TemperatureReading? sample = await tick(
        shipment,
        settings: settings,
        roll: high,
      );
      if (sample != null) {
        values.add(sample.celsius);
      }
    }
    expect(values.any((double value) => value > 8), isTrue);
    expect(values.last <= 8 && values.last >= 2, isTrue);
    final List<TemperatureExcursion> excursions = await database.excursionsFor(
      userId: user.id,
      shipmentId: shipment.id,
    );
    expect(excursions, isNotEmpty);
    expect(
      excursions.every((TemperatureExcursion item) => item.isAbove),
      isTrue,
    );
    expect(await database.tableRows('quality_reviews'), isEmpty);
    expect(await database.tableRows('excursion_actions'), isEmpty);
  });

  test('정상 온도는 허용 범위 안에서 조금씩 변하고 한 값에 고정되지 않는다', () async {
    final AppUser user = await courier();
    const PresentationSettings quiet = PresentationSettings(
      openingMinSamples: 40,
      openingSpan: 1,
      quietSamples: 48,
    );
    final ShipmentRecord fridge = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    final ShipmentRecord frozen = await start(
      user,
      const NewShipment(
        vaccine: '코미나티제이엔원주',
        manufacturer: '한국화이자제약(주)',
        lot: 'LOT-FROZEN-NORMAL',
        expiryDate: '2027-11-20',
        quantity: 5,
        origin: '창고',
        destination: '병원',
        targetRange: '-90 ~ -60°C',
        tempMin: -90,
        tempMax: -60,
      ),
      mode: DemoMode.presentation,
    );
    final List<double> warm = <double>[
      (await database.latestTemperature(fridge.id))!.celsius,
    ];
    final List<double> cold = <double>[
      (await database.latestTemperature(frozen.id))!.celsius,
    ];
    for (var index = 0; index < 24; index++) {
      warm.add((await tick(fridge, presentation: quiet))!.celsius);
      cold.add((await tick(frozen, presentation: quiet))!.celsius);
    }
    expect(warm.every((double value) => value >= 2 && value <= 8), isTrue);
    expect(cold.every((double value) => value >= -90 && value <= -60), isTrue);
    expect(warm.toSet().length, greaterThan(3));
    expect(cold.toSet().length, greaterThan(3));
    expect(warm.where((double value) => value == 5).length, lessThan(20));
    expect(cold.where((double value) => value == -75).length, lessThan(20));
    for (var index = 1; index < warm.length; index++) {
      expect(
        _tenth(warm[index] - warm[index - 1]).abs(),
        lessThanOrEqualTo(0.3),
      );
      expect(
        _tenth(cold[index] - cold[index - 1]).abs(),
        lessThanOrEqualTo(0.3),
      );
    }
    expect(warm, isNot(cold));
    final double again = VariedTemperature.next(
      previous: warm.last,
      min: 2,
      max: 8,
      sampleIndex: warm.length,
      seed: fridge.id,
    );
    expect(
      VariedTemperature.next(
        previous: warm.last,
        min: 2,
        max: 8,
        sampleIndex: warm.length,
        seed: fridge.id,
      ),
      again,
    );
    const PresentationSettings production = PresentationSettings();
    expect(production.openingMinSamples, 12);
    expect(production.openingMinSamples + production.openingSpan - 1, 36);
    expect(production.quietSamples, inInclusiveRange(36, 60));
    expect(production.firstSampleIndex(fridge.id), inInclusiveRange(12, 36));
    expect(
      production.sequenceFor(fridge.id),
      production.sequenceFor(fridge.id),
    );
    expect(const AutoDemoSettings().eventChance, 0.08);
    expect(const AutoDemoSettings().cooldownSamples, inInclusiveRange(36, 60));
    expect(
      const AutoDemoSettings().minimumNormalSamples,
      greaterThanOrEqualTo(12),
    );
  });

  test('5초 저장 경로는 점진적 고온 이탈 뒤 정상 유지 구간을 둔다', () async {
    final AppUser user = await courier();
    DateTime clock = DateTime.now().toUtc();
    final DemoTemperatureSession session = DemoTemperatureSession(
      database: database,
      clock: () => clock,
      interval: const Duration(seconds: 5),
    );
    const PresentationSettings show = PresentationSettings(
      openingMinSamples: 3,
      openingSpan: 1,
      quietSamples: 8,
      scriptedEvents: <String>[DemoScenario.doorOpen, DemoScenario.overcool],
    );
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    final TemperatureReading started = (await database.latestTemperature(
      shipment.id,
    ))!;
    expect(started.celsius, PresentationSettings.midpoint(2, 8));
    clock = started.measuredAt.toUtc();

    Future<void> advance(int steps) async {
      for (var index = 0; index < steps; index++) {
        clock = clock.add(const Duration(seconds: 5));
        await session.recordDue(presentation: show);
      }
    }

    await advance(2);
    final List<TemperatureReading> opening = await database
        .temperaturesForShipment(shipment.id);
    expect(opening, hasLength(3));
    expect(
      opening.map((TemperatureReading sample) => sample.celsius),
      everyElement(inInclusiveRange(2, 8)),
    );
    expect(
      opening.map((TemperatureReading sample) => sample.celsius).toSet().length,
      greaterThan(1),
    );

    var recovered = false;
    for (var index = 0; index < 40 && !recovered; index++) {
      await advance(1);
      final List<TemperatureExcursion> events = await database.excursionsFor(
        userId: user.id,
        shipmentId: shipment.id,
      );
      final TemperatureReading? latest = await database.latestTemperature(
        shipment.id,
      );
      recovered =
          events.length == 1 &&
          events.single.recoveredAt != null &&
          latest != null &&
          latest.celsius >= 2 &&
          latest.celsius <= 8;
    }
    expect(recovered, isTrue);
    final List<TemperatureReading> readings = await database
        .temperaturesForShipment(shipment.id);
    for (var index = 1; index < readings.length; index++) {
      expect(
        _tenth(readings[index].celsius - readings[index - 1].celsius).abs(),
        lessThanOrEqualTo(0.6),
      );
    }
    final int breach = readings.indexWhere(
      (TemperatureReading sample) => sample.celsius > 8,
    );
    expect(breach, greaterThan(2));
    expect(readings[breach - 1].celsius, lessThanOrEqualTo(8));
    final List<TemperatureExcursion> excursions = await database.excursionsFor(
      userId: user.id,
      shipmentId: shipment.id,
    );
    expect(excursions.single.isAbove, isTrue);
    expect(
      readings.map((TemperatureReading sample) => sample.measuredAt.toUtc()),
      containsAll(<DateTime>[
        excursions.single.startedAt.toUtc(),
        excursions.single.recoveredAt!.toUtc(),
      ]),
    );
    final int countAtRecovery = readings.length;
    final ShipmentRecord coolingDown = (await database.shipmentVisibleTo(
      userId: user.id,
      shipmentId: shipment.id,
    ))!;
    expect(coolingDown.autoCompletedEvents, 1);
    expect(coolingDown.autoCooldownUntilCount, greaterThan(countAtRecovery));

    await advance(6);
    final List<TemperatureReading> quiet = await database
        .temperaturesForShipment(shipment.id);
    expect(quiet, hasLength(countAtRecovery + 6));
    expect(
      quiet
          .skip(countAtRecovery)
          .every(
            (TemperatureReading sample) =>
                sample.celsius >= 2 && sample.celsius <= 8,
          ),
      isTrue,
    );
    expect(
      await database.excursionsFor(userId: user.id, shipmentId: shipment.id),
      hasLength(1),
    );
    expect(quiet.first.measuredAt.isBefore(quiet.last.measuredAt), isTrue);
    final List<TemperatureReading> newest = await database.recentTemperatures(
      shipment.id,
      limit: 20,
    );
    expect(newest, hasLength(20));
    expect(
      newest.first.measuredAt.isAfter(newest.last.measuredAt) ||
          (newest.first.measuredAt == newest.last.measuredAt &&
              newest.first.id > newest.last.id),
      isTrue,
    );
    expect(newest.first.id, quiet.last.id);

    final int cooldown = coolingDown.autoCooldownUntilCount;
    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    final ShipmentRecord restored = (await database.shipmentVisibleTo(
      userId: user.id,
      shipmentId: shipment.id,
    ))!;
    expect(restored.demoMode, DemoMode.presentation);
    expect(restored.autoCooldownUntilCount, cooldown);
    expect(restored.autoCompletedEvents, 1);
    expect(await database.temperatureCount(shipment.id), quiet.length);
    final DemoTemperatureSession resumed = DemoTemperatureSession(
      database: database,
      clock: () => clock,
      interval: const Duration(seconds: 5),
    );
    clock = clock.add(const Duration(seconds: 5));
    await resumed.recordDue();
    expect(await database.temperatureCount(shipment.id), quiet.length + 1);
    final List<TemperatureReading> after = await database
        .temperaturesForShipment(shipment.id);
    expect(
      after.take(quiet.length).map((TemperatureReading item) => item.id),
      quiet.map((TemperatureReading item) => item.id),
    );
    expect(after.last.celsius, inInclusiveRange(2, 8));
  });

  test('발표용 저온 이탈은 점진적으로 하한을 넘고 복귀한다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    const PresentationSettings show = PresentationSettings(
      openingMinSamples: 2,
      openingSpan: 1,
      quietSamples: 8,
      scriptedEvents: <String>[DemoScenario.overcool],
    );
    final List<double> values = <double>[
      (await database.latestTemperature(shipment.id))!.celsius,
    ];
    for (var index = 0; index < 30; index++) {
      final TemperatureReading? sample = await tick(
        shipment,
        presentation: show,
      );
      if (sample != null) {
        values.add(sample.celsius);
      }
      final List<TemperatureExcursion> events = await database.excursionsFor(
        userId: user.id,
        shipmentId: shipment.id,
      );
      if (events.length == 1 &&
          events.single.recoveredAt != null &&
          values.last >= 2 &&
          values.last <= 8) {
        break;
      }
    }
    final int breach = values.indexWhere((double value) => value < 2);
    expect(breach, greaterThan(1));
    expect(values[breach - 1], greaterThanOrEqualTo(2));
    expect(
      _tenth(values[breach] - values[breach - 1]).abs(),
      lessThanOrEqualTo(0.6),
    );
    expect(values.last, inInclusiveRange(2, 8));
    final List<TemperatureExcursion> excursions = await database.excursionsFor(
      userId: user.id,
      shipmentId: shipment.id,
    );
    expect(excursions.single.isAbove, isFalse);
    expect(excursions.single.recoveredAt, isNotNull);
    final ShipmentRecord stored = (await database.shipmentVisibleTo(
      userId: user.id,
      shipmentId: shipment.id,
    ))!;
    expect(stored.autoCompletedEvents, 1);
    for (var index = 0; index < 6; index++) {
      final TemperatureReading? sample = await tick(
        shipment,
        presentation: show,
      );
      expect(sample!.celsius, inInclusiveRange(2, 8));
    }
    expect(
      await database.excursionsFor(userId: user.id, shipmentId: shipment.id),
      hasLength(1),
    );
  });

  test('가상 냉각 장치 이상은 온도가 범위를 벗어날 때만 이탈이 된다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    const PresentationSettings show = PresentationSettings(
      openingMinSamples: 1,
      openingSpan: 1,
      quietSamples: 8,
      scriptedEvents: <String>[DemoScenario.coolingFault],
    );
    final TemperatureReading? first = await tick(shipment, presentation: show);
    expect(first!.celsius, lessThanOrEqualTo(8));
    final List<Map<String, Object?>> scenarios = await database.tableRows(
      'demo_temperature_scenarios',
    );
    expect(scenarios.single['scenario_type'], DemoScenario.coolingFault);
    expect(scenarios.single['trigger_source'], DemoScenario.autoTrigger);
    expect(
      await database.excursionsFor(userId: user.id, shipmentId: shipment.id),
      isEmpty,
    );
    TemperatureReading? outside;
    for (var index = 0; index < 20 && outside == null; index++) {
      final TemperatureReading? sample = await tick(
        shipment,
        presentation: show,
      );
      if (sample != null && sample.celsius > 8) {
        outside = sample;
      }
    }
    expect(outside, isNotNull);
    final List<TemperatureExcursion> excursions = await database.excursionsFor(
      userId: user.id,
      shipmentId: shipment.id,
    );
    expect(excursions.single.isAbove, isTrue);
    expect(excursions.single.startedAt.toUtc(), outside!.measuredAt.toUtc());
  });

  test('발표용 데이터 공백은 측정값과 이탈 이벤트를 만들지 않는다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    const PresentationSettings show = PresentationSettings(
      openingMinSamples: 1,
      openingSpan: 1,
      quietSamples: 8,
      scriptedEvents: <String>[PresentationSettings.dataGap],
    );
    const AutoDemoSettings settings = AutoDemoSettings(gapSkips: 4);
    final int before = await database.temperatureCount(shipment.id);
    expect(
      await tick(shipment, presentation: show, settings: settings),
      isNull,
    );
    expect(await database.temperatureCount(shipment.id), before);
    for (var index = 0; index < 3; index++) {
      expect(
        await tick(shipment, presentation: show, settings: settings),
        isNull,
      );
    }
    final TemperatureReading? resumed = await tick(
      shipment,
      presentation: show,
      settings: settings,
    );
    expect(resumed, isNotNull);
    expect(resumed!.celsius, inInclusiveRange(2, 8));
    expect(
      await database.excursionsFor(userId: user.id, shipmentId: shipment.id),
      isEmpty,
    );
  });

  test('앱을 다시 열어도 진행 중인 이상과 정상 유지 시간이 이어진다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    const PresentationSettings show = PresentationSettings(
      openingMinSamples: 1,
      openingSpan: 1,
      quietSamples: 10,
      scriptedEvents: <String>[DemoScenario.doorOpen],
    );
    TemperatureReading? rising;
    for (var index = 0; index < 8 && rising == null; index++) {
      final TemperatureReading? sample = await tick(
        shipment,
        presentation: show,
      );
      if (sample != null && sample.celsius > 5 && sample.celsius <= 8) {
        rising = sample;
      }
    }
    expect(rising, isNotNull);
    final List<TemperatureReading> before = await database
        .temperaturesForShipment(shipment.id);
    await database.close();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await database.open();
    final ShipmentRecord restored = (await database.shipmentVisibleTo(
      userId: user.id,
      shipmentId: shipment.id,
    ))!;
    expect(restored.demoMode, DemoMode.presentation);
    final TemperatureReading? next = await tick(shipment, presentation: show);
    final List<TemperatureReading> after = await database
        .temperaturesForShipment(shipment.id);
    expect(after.length, before.length + 1);
    expect(
      after.take(before.length).map((TemperatureReading item) => item.id),
      before.map((TemperatureReading item) => item.id),
    );
    expect(
      _tenth(next!.celsius - rising!.celsius).abs(),
      lessThanOrEqualTo(0.6),
    );
    expect(next.celsius, greaterThan(rising.celsius));
  });

  test('운송을 완료하면 자동 온도 생성이 멈춘다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.presentation,
    );
    final int before = await database.temperatureCount(shipment.id);
    await database.completeTransport(
      actorUserId: user.id,
      shipmentId: shipment.id,
    );
    expect(await tick(shipment), isNull);
    expect(await database.temperatureCount(shipment.id), before);
  });

  test('수동 시연과 자동 시연이 동시에 온도를 바꾸지 않는다', () async {
    final AppUser user = await courier();
    final ShipmentRecord quiet = await start(
      user,
      refrigerated,
      mode: DemoMode.probabilistic,
    );
    await database.startDemoScenario(
      actorUserId: user.id,
      shipmentId: quiet.id,
      type: DemoScenario.doorOpen,
    );
    const AutoDemoSettings settings = AutoDemoSettings(
      minimumNormalSamples: 1,
      eventChance: 1,
    );
    await tick(
      quiet,
      settings: settings,
      roll: DemoRoll(unit: () => 0, pick: (int max) => 1),
    );
    final List<Map<String, Object?>> scenarios = await database.tableRows(
      'demo_temperature_scenarios',
    );
    expect(scenarios, hasLength(1));
    expect(scenarios.single['scenario_type'], DemoScenario.doorOpen);
    expect(scenarios.single['trigger_source'], DemoScenario.manualTrigger);

    final ShipmentRecord presented = await start(
      user,
      const NewShipment(
        vaccine: '스카이셀플루4가프리필드시린지',
        manufacturer: '에스케이바이오사이언스(주)',
        lot: 'LOT-SHOW',
        expiryDate: '2027-11-20',
        quantity: 10,
        origin: '창고',
        destination: '병원',
        targetRange: '2 ~ 8°C',
        tempMin: 2,
        tempMax: 8,
      ),
      mode: DemoMode.presentation,
    );
    const PresentationSettings show = PresentationSettings(
      openingMinSamples: 0,
      openingSpan: 1,
      quietSamples: 12,
      scriptedEvents: <String>[DemoScenario.doorOpen],
    );
    await tick(presented, presentation: show);
    expect(
      () => database.startDemoScenario(
        actorUserId: user.id,
        shipmentId: presented.id,
        type: DemoScenario.overcool,
      ),
      throwsA(isA<ExcursionException>()),
    );
    expect(
      await database.tableRows('demo_temperature_scenarios'),
      hasLength(2),
    );
  });

  test('데이터 공백은 온도 이탈로 기록하지 않는다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(
      user,
      refrigerated,
      mode: DemoMode.probabilistic,
    );
    const AutoDemoSettings settings = AutoDemoSettings(
      minimumNormalSamples: 1,
      eventChance: 1,
      gapSkips: 4,
      cooldownSamples: 20,
    );
    final DemoRoll gap = DemoRoll(unit: () => 0, pick: (int max) => 3);
    final TemperatureReading? skipped = await tick(
      shipment,
      settings: settings,
      roll: gap,
    );
    expect(skipped, isNull);
    for (var index = 0; index < 3; index++) {
      expect(await tick(shipment, settings: settings, roll: gap), isNull);
    }
    final TemperatureReading? resumed = await tick(
      shipment,
      settings: settings,
      roll: gap,
    );
    expect(resumed, isNotNull);
    expect(resumed!.celsius >= 2 && resumed.celsius <= 8, isTrue);
    expect(
      await database.excursionsFor(userId: user.id, shipmentId: shipment.id),
      isEmpty,
    );
    final ShipmentInsight insight = const ShipmentAnalytics().inspect(
      shipment: shipment,
      readings: await database.temperaturesForShipment(shipment.id),
      excursions: const <TemperatureExcursion>[],
    );
    expect(insight.hasGap, isTrue);
    expect(insight.excursions.count, 0);
  });

  test('기존 방식 운송 건의 온도와 모드는 유지된다', () async {
    final AppUser user = await courier();
    final ShipmentRecord legacy = await start(user, refrigerated);
    final TemperatureReading kept = (await database.recordMeasuredSample(
      shipmentId: legacy.id,
      at: now.add(const Duration(seconds: 5)),
      celsius: 4,
    ))!;
    final ShipmentRecord other = await start(
      user,
      const NewShipment(
        vaccine: '스카이셀플루4가프리필드시린지',
        manufacturer: '에스케이바이오사이언스(주)',
        lot: 'LOT-OTHER',
        expiryDate: '2027-11-20',
        quantity: 10,
        origin: '창고',
        destination: '병원',
        targetRange: '2 ~ 8°C',
        tempMin: 2,
        tempMax: 8,
      ),
      mode: DemoMode.presentation,
    );
    await tick(other);
    final TemperatureReading? latest = await database.latestTemperature(
      legacy.id,
    );
    expect(latest!.id, kept.id);
    expect(latest.celsius, 4);
    final ShipmentRecord stored = (await database.shipmentVisibleTo(
      userId: user.id,
      shipmentId: legacy.id,
    ))!;
    expect(stored.demoMode, isNull);
    expect(stored.tempMin, 2);
    expect(stored.tempMax, 8);
    expect(await database.userVersion(), 11);
    expect((await database.vaccineProducts()).length, 2);
    expect(VaccineCatalogSeed.selectableProductNames, <String>{
      '코미나티제이엔원주',
      '스카이셀플루4가프리필드시린지',
    });
    expect(const DemoRiskSettings().minorDeviationCelsius, 1);
    expect(const DemoRiskSettings().repeatedExcursionCount, 2);
    expect(const DemoRiskSettings().minimumSamplesForLow, 3);
    expect(
      const DemoRiskSettings().longObservedDuration,
      const Duration(seconds: 60),
    );
    final TemperatureChartModel chart = buildTemperatureChart(
      readings: await database.temperaturesForShipment(other.id),
      minBound: 2,
      maxBound: 8,
    );
    expect(chart.sourceCount, await database.temperatureCount(other.id));
    expect(chart.displayCount, chart.sourceCount);
    if (chart.points.length > 1) {
      expect(
        chart.points.first.measuredAt.isBefore(chart.points.last.measuredAt),
        isTrue,
      );
    }
  });

  test('최근 20건은 최신 측정이 앞에 오고 더 보기는 이전 기록을 포함한다', () async {
    final AppUser user = await courier();
    final ShipmentRecord shipment = await start(user, refrigerated);
    final TemperatureReading started = (await database.latestTemperature(
      shipment.id,
    ))!;
    DateTime at = started.measuredAt;
    for (var index = 0; index < 24; index++) {
      at = at.add(const Duration(seconds: 5));
      await database.recordMeasuredSample(
        shipmentId: shipment.id,
        at: at,
        celsius: 4 + (index % 4) * 0.1,
      );
    }
    final List<TemperatureReading> page = await database.recentTemperatures(
      shipment.id,
    );
    final List<TemperatureReading> chart = await database
        .temperaturesForShipment(shipment.id);
    expect(page, hasLength(20));
    expect(chart, hasLength(25));
    expect(page.first.id, chart.last.id);
    expect(page.last.id, isNot(chart.first.id));
    expect(page.first.measuredAt.isAfter(page.last.measuredAt), isTrue);
    expect(chart.first.measuredAt.isBefore(chart.last.measuredAt), isTrue);
    final List<TemperatureReading> more = await database.recentTemperatures(
      shipment.id,
      limit: 40,
    );
    expect(more, hasLength(25));
    expect(more.last.id, chart.first.id);
    expect(
      more.map((TemperatureReading item) => item.id).toSet(),
      hasLength(25),
    );
  });

  testWidgets('측정 기록 목록은 시각과 상태만 보여주고 최신을 위에 둔다', (tester) async {
    var loaded = false;
    final DateTime newer = DateTime(2026, 11, 21, 16, 45, 9);
    final DateTime older = DateTime(2026, 11, 20, 9, 0, 4);
    final TemperatureReading high = TemperatureReading(
      id: 30,
      shipmentId: 1,
      celsius: 8.4,
      measuredAt: newer,
      recordedAt: newer,
      source: TemperatureReading.demoVirtualSource,
      assigneeUserId: 1,
    );
    final TemperatureReading normal = TemperatureReading(
      id: 20,
      shipmentId: 1,
      celsius: 5.1,
      measuredAt: newer.subtract(const Duration(seconds: 5)),
      recordedAt: newer,
      source: TemperatureReading.demoVirtualSource,
      assigneeUserId: 1,
    );
    final TemperatureReading previousDay = TemperatureReading(
      id: 10,
      shipmentId: 1,
      celsius: 1.4,
      measuredAt: older,
      recordedAt: older,
      source: TemperatureReading.demoVirtualSource,
      assigneeUserId: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemperatureMeasurementList(
            readings: <TemperatureReading>[high, normal, high, previousDay],
            tempMin: 2,
            tempMax: 8,
            totalCount: 21,
            onLoadMore: () => loaded = true,
          ),
        ),
      ),
    );
    expect(find.text('시연용 가상 데이터 · 5초 간격 측정'), findsOneWidget);
    expect(find.textContaining('시연용 가상 데이터입니다'), findsNothing);
    expect(find.byKey(const Key('temperature-row-30')), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('고온 이탈')).dy,
      lessThan(tester.getTopLeft(find.textContaining('저온 이탈')).dy),
    );
    expect(find.textContaining('16:45:09'), findsOneWidget);
    expect(find.textContaining('16:45:04'), findsOneWidget);
    expect(find.textContaining('정상'), findsOneWidget);
    expect(find.text('2026-11-20'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('정상')).dy,
      lessThan(tester.getTopLeft(find.textContaining('저온 이탈')).dy),
    );
    await tester.tap(find.byKey(const Key('load-older-temperatures')));
    await tester.pump();
    expect(loaded, isTrue);
  });

  testWidgets('대응 기록은 역할별로 보이고 빈 값은 확인되지 않음이다', (tester) async {
    final DateTime at = DateTime.utc(2026, 11, 20, 2);
    final ExcursionAction unlinked = ExcursionAction(
      id: 4,
      shipmentId: 3,
      excursionId: null,
      authorUserId: 1,
      authorLoginId: 'courier',
      causeCategory: 'other',
      causeCertainty: ExcursionAction.suspected,
      description: '기존 원인',
      discoveredAt: null,
      responseStartedAt: null,
      actionTaken: '기존 조치',
      reportedTo: null,
      reportedAt: null,
      note: null,
      createdAt: at,
    );
    final TemperatureExcursion excursion = TemperatureExcursion(
      id: 9,
      shipmentId: 3,
      direction: TemperatureExcursion.aboveMax,
      startedAt: at,
      lastOutOfRangeAt: at,
      recoveredAt: null,
      minTemperature: 9,
      maxTemperature: 9.4,
      dataGapDetected: false,
      status: TemperatureExcursion.openStatus,
      createdAt: at,
      updatedAt: at,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResponseRecordPanel(
            title: '운송자 대응 보고',
            sectionKey: Key('transporter-response-report'),
            actions: <ExcursionAction>[unlinked],
            excursions: <TemperatureExcursion>[excursion],
            emptyLabel: '등록된 대응 기록이 없습니다.',
            noticeUnlinkedExcursions: true,
          ),
        ),
      ),
    );
    expect(find.text('운송자 대응 보고'), findsOneWidget);
    expect(find.textContaining('확인되지 않음'), findsWidgets);
    expect(find.textContaining('기존 조치'), findsOneWidget);
    expect(find.byKey(const Key('unlinked-response-record')), findsOneWidget);
    expect(find.textContaining('별도 상황 보고'), findsOneWidget);
    expect(find.byKey(const Key('missing-linked-report')), findsOneWidget);
    expect(find.textContaining('접종 가능'), findsNothing);

    final ShipmentRecord shipment = ShipmentRecord(
      id: 3,
      ownerUserId: 1,
      assigneeUserId: 1,
      participationCode: 'VX-TEST',
      vaccine: '인플루엔자 4가',
      manufacturer: '제조사',
      lot: 'LOT',
      expiryDate: '2027-11-20',
      quantity: 1,
      origin: '창고',
      destination: '병원',
      targetRange: '2 ~ 8°C',
      tempMin: 2,
      tempMax: 8,
      status: ShipmentStatus.inTransit,
      createdAt: at,
      source: ShipmentRecord.userInputSource,
    );
    final AppUser quality = AppUser(
      id: 2,
      loginId: 'quality',
      role: UserRole.qualityManager,
      createdAt: at,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TemperatureStatusCard(
            user: quality,
            shipment: shipment,
            latest: null,
            excursions: const <TemperatureExcursion>[],
            latestActions: const <int, ExcursionAction>{},
            scenario: null,
            onChanged: () async {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('response-manual-button')), findsNothing);
    expect(find.textContaining('온도 이탈 감지'), findsNothing);
  });
}
