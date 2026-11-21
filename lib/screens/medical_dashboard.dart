import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/demo_temperature_session.dart';
import '../data/shipment_analytics.dart';
import '../models/demo_scenario.dart';
import '../models/quality_review.dart';
import '../models/temperature_excursion.dart';
import '../models/shipment_record.dart';
import '../models/temperature_reading.dart';
import '../navigation/logout.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/shipment_widgets.dart';
import '../widgets/vax_logo.dart';
import 'shipment_detail_screen.dart';

class MedicalDashboard extends StatefulWidget {
  const MedicalDashboard({super.key});

  @override
  State<MedicalDashboard> createState() => _MedicalDashboardState();
}

class _MedicalDashboardState extends State<MedicalDashboard> {
  List<ShipmentRecord> _shipments = const <ShipmentRecord>[];
  Map<int, TemperatureReading> _latest = const <int, TemperatureReading>{};
  Map<int, ExcursionSummary> _excursions = const <int, ExcursionSummary>{};
  Map<int, ShipmentInsight> _insights = const <int, ShipmentInsight>{};
  FleetSummary _summary = FleetSummary.empty;
  QualityReviewCounts _reviewCounts = QualityReviewCounts.empty;
  Map<int, QualityReview> _reviews = const <int, QualityReview>{};
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    DemoTemperatureSession.instance.addListener(_onTemperature);
    unawaited(_load());
  }

  @override
  void dispose() {
    DemoTemperatureSession.instance.removeListener(_onTemperature);
    super.dispose();
  }

  void _onTemperature() {
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final user = await AppDatabase.instance.currentSessionUser();
      if (!mounted) {
        return;
      }
      if (user == null) {
        setState(() {
          _shipments = const <ShipmentRecord>[];
          _latest = const <int, TemperatureReading>{};
          _excursions = const <int, ExcursionSummary>{};
          _insights = const <int, ShipmentInsight>{};
          _summary = FleetSummary.empty;
          _reviewCounts = QualityReviewCounts.empty;
          _reviews = const <int, QualityReview>{};
          _loading = false;
          _loadError = null;
        });
        return;
      }
      final List<ShipmentRecord> shipments = await AppDatabase.instance
          .shipmentsJoinedBy(user.id);
      final List<int> ids = shipments
          .map((ShipmentRecord shipment) => shipment.id)
          .toList();
      final Map<int, TemperatureReading> latest = await AppDatabase.instance
          .latestTemperatures(ids);
      final Map<int, ExcursionSummary> excursions = await AppDatabase.instance
          .excursionSummaries(ids);
      final List<TemperatureReading> readings = await AppDatabase.instance
          .temperaturesForShipments(ids);
      final Map<int, List<TemperatureExcursion>> events = await AppDatabase
          .instance
          .excursionsByShipment(ids);
      const ShipmentAnalytics analytics = ShipmentAnalytics();
      final Map<int, bool> actions = await AppDatabase.instance
          .recordedExcursionActions(ids);
      final Map<int, QualityReview> reviews = await AppDatabase.instance
          .latestQualityReviews(ids);
      final Map<int, ShipmentInsight> insights = analytics.inspectAll(
        shipments: shipments,
        readings: readings,
        excursions: events,
        actionRecorded: actions,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _shipments = shipments;
        _latest = latest;
        _excursions = excursions;
        _insights = insights;
        _summary = analytics.summarize(
          shipments: shipments,
          insights: insights.values.toList(),
        );
        _reviews = reviews;
        _reviewCounts = QualityReviewCounts.fromLatest(ids, reviews);
        _loading = false;
        _loadError = null;
      });
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
        _shipments = const <ShipmentRecord>[];
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = '운송 건을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _openDetail(int shipmentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ShipmentDetailScreen(shipmentId: shipmentId),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const VaxLogo(compact: true, light: true),
        actions: const <Widget>[LogoutAction()],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const DemoBanner(),
          const SizedBox(height: 16),
          const Text(
            '의료진 대시보드',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '품질 검토와 물품 인수를 확인합니다. 인수는 사용 승인이 아닙니다.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: '연결 운송 건',
                  value: '${_summary.shipmentCount}건',
                  icon: Icons.vaccines_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricCard(
                  label: '검토 전',
                  value: '${_reviewCounts.notReviewed}건',
                  icon: Icons.fact_check_outlined,
                  alert: _reviewCounts.notReviewed > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '검토 중 ${_reviewCounts.inReview}건 · 추가 확인 필요 ${_reviewCounts.needsInformation}건 · '
            '사용 보류 ${_reviewCounts.onHold}건 · 검토 완료 ${_reviewCounts.completed}건',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ParticipationCodeJoinCard(onChanged: () => unawaited(_load())),
          const SizedBox(height: 20),
          const SectionTitle(title: '연결된 운송 건', caption: '저장된 데이터'),
          const SizedBox(height: 10),
          if (_loading)
            const Text('불러오는 중')
          else if (_loadError != null)
            Text(_loadError!, style: const TextStyle(color: AppColors.danger))
          else if (_shipments.isEmpty)
            const Text('연결된 운송 건이 없습니다.')
          else
            ..._shipments.map(
              (ShipmentRecord shipment) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: StoredShipmentCard(
                  shipment: shipment,
                  kind: ShipmentCardKind.medical,
                  latest: _latest[shipment.id],
                  excursion: _excursions[shipment.id],
                  insight: _insights[shipment.id],
                  review: _reviews[shipment.id],
                  onTap: () => _openDetail(shipment.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
