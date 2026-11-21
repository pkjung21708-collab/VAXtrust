import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/demo_temperature_session.dart';
import '../data/shipment_analytics.dart';
import '../models/demo_scenario.dart';
import '../models/quality_review.dart';
import '../models/temperature_excursion.dart';
import '../models/shipment_record.dart';
import '../models/shipment_transfer.dart';
import '../models/temperature_reading.dart';
import '../navigation/logout.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/shipment_widgets.dart';
import '../widgets/temperature_measurement_list.dart';
import '../widgets/vax_logo.dart';
import 'shipment_detail_screen.dart';
import 'shipment_setup_screen.dart';

class TransporterDashboard extends StatefulWidget {
  const TransporterDashboard({super.key});

  @override
  State<TransporterDashboard> createState() => _TransporterDashboardState();
}

class _TransporterDashboardState extends State<TransporterDashboard> {
  List<ShipmentRecord> _assigned = const <ShipmentRecord>[];
  List<ShipmentRecord> _owned = const <ShipmentRecord>[];
  List<ShipmentRecord> _past = const <ShipmentRecord>[];
  List<ShipmentTransfer> _incoming = const <ShipmentTransfer>[];
  List<ShipmentTransfer> _outgoing = const <ShipmentTransfer>[];
  List<ShipmentTransfer> _history = const <ShipmentTransfer>[];
  Map<int, TemperatureReading> _latest = const <int, TemperatureReading>{};
  Map<int, ExcursionSummary> _excursions = const <int, ExcursionSummary>{};
  Map<int, ShipmentInsight> _insights = const <int, ShipmentInsight>{};
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
          _assigned = const <ShipmentRecord>[];
          _owned = const <ShipmentRecord>[];
          _past = const <ShipmentRecord>[];
          _incoming = const <ShipmentTransfer>[];
          _outgoing = const <ShipmentTransfer>[];
          _history = const <ShipmentTransfer>[];
          _latest = const <int, TemperatureReading>{};
          _excursions = const <int, ExcursionSummary>{};
          _insights = const <int, ShipmentInsight>{};
          _reviews = const <int, QualityReview>{};
          _loading = false;
          _loadError = null;
        });
        return;
      }
      final List<ShipmentRecord> assigned = await AppDatabase.instance
          .shipmentsAssignedTo(user.id);
      final List<ShipmentRecord> owned = await AppDatabase.instance
          .shipmentsOwnedBy(user.id);
      final List<ShipmentRecord> past = await AppDatabase.instance
          .shipmentsPreviouslyAssigned(user.id);
      final List<ShipmentTransfer> incoming = await AppDatabase.instance
          .incomingHandovers(user.id);
      final List<ShipmentTransfer> outgoing = await AppDatabase.instance
          .outgoingHandovers(user.id);
      final List<ShipmentTransfer> history = await AppDatabase.instance
          .handoverHistoryForUser(user.id);
      final List<int> ids = <int>{
        ...assigned.map((ShipmentRecord shipment) => shipment.id),
        ...owned.map((ShipmentRecord shipment) => shipment.id),
        ...past.map((ShipmentRecord shipment) => shipment.id),
      }.toList();
      final Map<int, TemperatureReading> latest = await AppDatabase.instance
          .latestTemperatures(ids);
      final Map<int, ExcursionSummary> excursions = await AppDatabase.instance
          .excursionSummaries(ids);
      final List<ShipmentRecord> visible = <ShipmentRecord>[
        ...assigned,
        ...owned,
        ...past,
      ];
      final List<TemperatureReading> readings = await AppDatabase.instance
          .temperaturesForShipments(ids);
      final Map<int, List<TemperatureExcursion>> events = await AppDatabase
          .instance
          .excursionsByShipment(ids);
      final Map<int, bool> actions = await AppDatabase.instance
          .recordedExcursionActions(ids);
      final Map<int, QualityReview> reviews = await AppDatabase.instance
          .latestQualityReviews(ids);
      final Map<int, ShipmentInsight> insights = const ShipmentAnalytics()
          .inspectAll(
            shipments: visible,
            readings: readings,
            excursions: events,
            actionRecorded: actions,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _assigned = assigned;
        _owned = owned;
        _past = past;
        _incoming = incoming;
        _outgoing = outgoing;
        _history = history;
        _latest = latest;
        _excursions = excursions;
        _insights = insights;
        _reviews = reviews;
        _loading = false;
        _loadError = null;
      });
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
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

  String _currentTemperatureLabel() {
    TemperatureReading? newest;
    for (final ShipmentRecord shipment in _assigned) {
      final TemperatureReading? reading = _latest[shipment.id];
      if (reading == null) {
        continue;
      }
      if (newest == null || reading.measuredAt.isAfter(newest.measuredAt)) {
        newest = reading;
      }
    }
    return newest == null ? '측정 전' : newest.temperatureLabel;
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            const ShipmentSetupScreen(returnToList: true),
      ),
    );
    if (mounted) {
      await _load();
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

  Future<void> _accept(ShipmentTransfer transfer) async {
    await _runTransfer(() async {
      final user = await AppDatabase.instance.currentSessionUser();
      if (user == null) {
        throw const TransferException('로그인 정보가 없습니다.');
      }
      await AppDatabase.instance.acceptHandover(
        actorUserId: user.id,
        transferId: transfer.id,
      );
    }, '인수인계를 수락했습니다.');
  }

  Future<void> _reject(ShipmentTransfer transfer) async {
    final String? reason = await _askRejectionReason();
    if (reason == null || !mounted) {
      return;
    }
    await _runTransfer(() async {
      final user = await AppDatabase.instance.currentSessionUser();
      if (user == null) {
        throw const TransferException('로그인 정보가 없습니다.');
      }
      await AppDatabase.instance.rejectHandover(
        actorUserId: user.id,
        transferId: transfer.id,
        reason: reason,
      );
    }, '인수인계를 거절했습니다. 기존 담당자는 유지됩니다.');
  }

  Future<void> _cancel(ShipmentTransfer transfer) async {
    await _runTransfer(() async {
      final user = await AppDatabase.instance.currentSessionUser();
      if (user == null) {
        throw const TransferException('로그인 정보가 없습니다.');
      }
      await AppDatabase.instance.cancelHandover(
        actorUserId: user.id,
        transferId: transfer.id,
      );
    }, '인수인계 요청을 취소했습니다.');
  }

  Future<String?> _askRejectionReason() {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('인수 거절'),
          content: TextField(
            key: const Key('reject-reason'),
            controller: controller,
            decoration: const InputDecoration(labelText: '거절 사유 (선택)'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('닫기'),
            ),
            TextButton(
              key: const Key('confirm-reject'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('거절'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _runTransfer(
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } on TransferException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('인수인계를 처리하지 못했습니다.')));
    }
  }

  ShipmentRecord? _activeTransit() {
    for (final ShipmentRecord shipment in _assigned) {
      if (shipment.status == ShipmentStatus.inTransit) {
        return shipment;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ShipmentRecord? active = _activeTransit();
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
            '운송자 대시보드',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text('현재 운송 상태를 확인하고 필요한 조치를 진행합니다.'),
          const SizedBox(height: 16),
          if (active != null) ...[
            _ActiveTransitCard(
              shipment: active,
              latest: _latest[active.id],
              excursion: _excursions[active.id],
              onOpen: () => _openDetail(active.id),
            ),
            const SizedBox(height: 16),
          ],
          if (active == null)
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: '현재 온도',
                    value: _currentTemperatureLabel(),
                    icon: Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: '현재 담당',
                    value: _loading ? '…' : '${_assigned.length}건',
                    icon: Icons.route_outlined,
                  ),
                ),
              ],
            )
          else
            MetricCard(
              label: '현재 담당',
              value: _loading ? '…' : '${_assigned.length}건',
              icon: Icons.route_outlined,
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('open-shipment-setup'),
              onPressed: _openSetup,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text(
                '새로운 운송 건 등록',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _shipmentSection(
            title: '현재 담당 운송 건',
            caption: '저장된 데이터',
            empty: '현재 담당 운송 건이 없습니다.',
            shipments: _assigned,
          ),
          _shipmentSection(
            title: '내가 등록한 운송 건',
            caption: '저장된 데이터',
            empty: '등록한 운송 건이 없습니다.',
            shipments: _owned,
          ),
          const SectionTitle(title: '나에게 도착한 인수 요청', caption: '저장된 데이터'),
          const SizedBox(height: 10),
          if (_loading)
            const Text('불러오는 중')
          else if (_loadError != null)
            Text(_loadError!, style: const TextStyle(color: AppColors.danger))
          else if (_incoming.isEmpty)
            const Text('도착한 인수 요청이 없습니다.')
          else
            ..._incoming.map(
              (ShipmentTransfer transfer) => _TransferCard(
                transfer: transfer,
                actions: <Widget>[
                  TextButton(
                    key: Key('accept-handover-${transfer.id}'),
                    onPressed: () => _accept(transfer),
                    child: const Text('수락'),
                  ),
                  TextButton(
                    key: Key('reject-handover-${transfer.id}'),
                    onPressed: () => _reject(transfer),
                    child: const Text('거절'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const SectionTitle(title: '내가 보낸 인계 요청', caption: '저장된 데이터'),
          const SizedBox(height: 10),
          if (!_loading && _loadError == null && _outgoing.isEmpty)
            const Text('보낸 인계 요청이 없습니다.')
          else
            ..._outgoing.map(
              (ShipmentTransfer transfer) => _TransferCard(
                transfer: transfer,
                actions: <Widget>[
                  TextButton(
                    key: Key('cancel-handover-${transfer.id}'),
                    onPressed: () => _cancel(transfer),
                    child: const Text('요청 취소'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          _shipmentSection(
            title: '과거 담당 운송 건',
            caption: '저장된 데이터',
            empty: '과거 담당 운송 건이 없습니다.',
            shipments: _past,
          ),
          const SectionTitle(title: '인수인계 이력', caption: '저장된 데이터'),
          const SizedBox(height: 10),
          if (!_loading && _loadError == null && _history.isEmpty)
            const Text('인수인계 이력이 없습니다.')
          else
            ..._history.map(
              (ShipmentTransfer transfer) => _TransferCard(transfer: transfer),
            ),
        ],
      ),
    );
  }

  Widget _shipmentSection({
    required String title,
    required String caption,
    required String empty,
    required List<ShipmentRecord> shipments,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title, caption: caption),
        const SizedBox(height: 10),
        if (_loading)
          const Text('불러오는 중')
        else if (_loadError != null)
          Text(_loadError!, style: const TextStyle(color: AppColors.danger))
        else if (shipments.isEmpty)
          Text(empty)
        else
          ...shipments.map(
            (ShipmentRecord shipment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StoredShipmentCard(
                shipment: shipment,
                kind: ShipmentCardKind.transporter,
                latest: _latest[shipment.id],
                excursion: _excursions[shipment.id],
                insight: _insights[shipment.id],
                review: _reviews[shipment.id],
                onTap: () => _openDetail(shipment.id),
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _ActiveTransitCard extends StatelessWidget {
  const _ActiveTransitCard({
    required this.shipment,
    required this.latest,
    required this.excursion,
    required this.onOpen,
  });

  final ShipmentRecord shipment;
  final TemperatureReading? latest;
  final ExcursionSummary? excursion;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bool open = excursion?.open ?? false;
    final String state = latest == null
        ? '측정 전'
        : measurementRangeStatus(
            celsius: latest!.celsius,
            min: shipment.tempMin,
            max: shipment.tempMax,
          );
    final Color stateColor = state == '고온 이탈' || state == '저온 이탈'
        ? AppColors.danger
        : state == '측정 전'
        ? AppColors.textSecondary
        : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: open ? AppColors.danger : const Color(0xFFE1EAED),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shipment.vaccine,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            shipment.displayId,
            style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '현재 온도',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          Text(
            latest == null ? '측정 전' : latest!.temperatureLabel,
            style: TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: open ? AppColors.danger : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            latest == null
                ? '현재 온도 상태: $state'
                : '현재 온도 상태: $state (${latest!.temperatureLabel})',
            style: TextStyle(fontWeight: FontWeight.w800, color: stateColor),
          ),
          Text('허용 범위 ${shipment.temperatureRangeLabel}'),
          Text(
            '마지막 측정 ${latest == null ? '없음' : formatMeasurementTime(latest!.measuredAt)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onOpen,
              child: const Text('운송 상세'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: const Text('대응 기록'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: const Text('운송 완료'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfer,
    this.actions = const <Widget>[],
  });

  final ShipmentTransfer transfer;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final String schedule = transfer.scheduledAt == null
        ? '예정 시각 미정'
        : '예정 ${formatHandoverTime(transfer.scheduledAt)}';
    return Container(
      key: Key('transfer-${transfer.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  transfer.shipmentDisplayId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                  ),
                ),
              ),
              StatusChip(label: transfer.status.label),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            transfer.vaccine,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('LOT ${transfer.lot}'),
          Text('${transfer.fromLoginId} → ${transfer.toLoginId}'),
          Text(transfer.location.isEmpty ? '장소 미기록' : transfer.location),
          Text(schedule),
          Text('운송 상태 ${transfer.shipmentStatus.label}'),
          if (transfer.note != null) Text('메모 ${transfer.note}'),
          if (transfer.rejectionReason != null)
            Text('거절 사유 ${transfer.rejectionReason}'),
          Text(
            '인계 온도 ${transfer.handoverTempC == null ? '기록 없음' : TemperatureBounds.formatCelsius(transfer.handoverTempC!)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (actions.isNotEmpty)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
  }
}
