import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/auto_demo_policy.dart';
import '../data/demo_temperature_session.dart';
import '../data/shipment_analytics.dart';
import '../models/app_user.dart';
import '../models/demo_scenario.dart';
import '../models/excursion_action.dart';
import '../models/quality_review.dart';
import '../models/shipment_receipt.dart';
import '../models/shipment_record.dart';
import '../models/shipment_release.dart';
import '../models/shipment_transfer.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/quality_review_panel.dart';
import '../widgets/response_record_panel.dart';
import '../widgets/shipment_custody_panels.dart';
import '../widgets/shipment_widgets.dart';
import '../widgets/storage_condition_panel.dart';
import '../widgets/temperature_chart_view.dart';
import '../widgets/temperature_measurement_list.dart';
import '../widgets/temperature_status_card.dart';
import '../widgets/vax_logo.dart';
import 'handover_request_screen.dart';

/// 세 역할이 같은 shipment_id의 저장 데이터를 보는 화면입니다.
class ShipmentDetailScreen extends StatefulWidget {
  const ShipmentDetailScreen({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  AppUser? _user;
  ShipmentRecord? _shipment;
  String _assigneeLoginId = '';
  List<ShipmentTransfer> _history = const <ShipmentTransfer>[];
  ShipmentTransfer? _pending;
  List<TemperatureReading> _readings = const <TemperatureReading>[];
  List<TemperatureReading> _chartReadings = const <TemperatureReading>[];
  ShipmentInsight? _insight;
  List<TemperatureExcursion> _excursions = const <TemperatureExcursion>[];
  List<ExcursionAction> _actions = const <ExcursionAction>[];
  Map<int, ExcursionAction> _latestActions = const <int, ExcursionAction>{};
  DemoScenario? _scenario;
  List<QualityReview> _reviews = const <QualityReview>[];
  ShipmentRelease? _release;
  ShipmentReceipt? _receipt;
  int _readingCount = 0;
  int _readingLimit = 20;
  bool _loading = true;
  String? _error;
  final GlobalKey _recordsKey = GlobalKey();

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
      final AppUser? user = await AppDatabase.instance.currentSessionUser();
      if (!mounted) {
        return;
      }
      if (user == null) {
        setState(() {
          _loading = false;
          _error = '로그인 정보가 없습니다.';
        });
        return;
      }
      final ShipmentRecord? shipment = await AppDatabase.instance
          .shipmentVisibleTo(userId: user.id, shipmentId: widget.shipmentId);
      if (shipment == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _user = user;
          _shipment = null;
          _loading = false;
          _error = '운송 건을 찾을 수 없거나 접근할 수 없습니다.';
        });
        return;
      }
      final AppUser? assignee = await AppDatabase.instance.userById(
        shipment.assigneeUserId,
      );
      final List<ShipmentTransfer> history = await AppDatabase.instance
          .handoverHistoryForShipment(shipment.id);
      final ShipmentTransfer? pending = await AppDatabase.instance
          .pendingHandoverForShipment(shipment.id);
      final List<TemperatureReading> readings = await AppDatabase.instance
          .recentTemperatures(shipment.id, limit: _readingLimit);
      final int readingCount = await AppDatabase.instance.temperatureCount(
        shipment.id,
      );
      final List<TemperatureExcursion> excursions = await AppDatabase.instance
          .excursionsFor(userId: user.id, shipmentId: shipment.id);
      final Map<int, ExcursionAction> latestActions = await AppDatabase.instance
          .latestActionsForShipment(shipment.id);
      final List<ExcursionAction> actions = await AppDatabase.instance
          .actionsForShipment(userId: user.id, shipmentId: shipment.id);
      final DemoScenario? scenario = await AppDatabase.instance
          .activeScenarioFor(userId: user.id, shipmentId: shipment.id);
      final List<TemperatureReading> chartReadings = await AppDatabase.instance
          .temperaturesForShipment(shipment.id);
      final List<QualityReview> reviews = await AppDatabase.instance
          .qualityReviewsFor(userId: user.id, shipmentId: shipment.id);
      final ShipmentRelease? release = await AppDatabase.instance.releaseFor(
        userId: user.id,
        shipmentId: shipment.id,
      );
      final ShipmentReceipt? receipt = await AppDatabase.instance.receiptFor(
        userId: user.id,
        shipmentId: shipment.id,
      );
      final ShipmentInsight insight = const ShipmentAnalytics().inspect(
        shipment: shipment,
        readings: chartReadings,
        excursions: excursions,
        actionRecorded: <int, bool>{
          for (final MapEntry<int, ExcursionAction> entry
              in latestActions.entries)
            entry.key: true,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _user = user;
        _shipment = shipment;
        _assigneeLoginId = assignee?.loginId ?? '알 수 없음';
        _history = history;
        _pending = pending;
        _readings = readings;
        _chartReadings = chartReadings;
        _insight = insight;
        _excursions = excursions;
        _actions = actions;
        _latestActions = latestActions;
        _scenario = scenario;
        _reviews = reviews;
        _release = release;
        _receipt = receipt;
        _readingCount = readingCount;
        _loading = false;
        _error = null;
      });
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '로컬 저장소를 열 수 없습니다.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '운송 건을 불러오지 못했습니다.';
      });
    }
  }

  void _backToList() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Widget _transportPanel({
    bool includeSummary = true,
    bool includeList = true,
  }) {
    return _TransportPanel(
      user: _user!,
      shipment: _shipment!,
      readings: _readings,
      readingCount: _readingCount,
      release: _release,
      onChanged: _load,
      onLoadMore: () async {
        setState(() => _readingLimit += 20);
        await _load();
      },
      includeSummary: includeSummary,
      includeList: includeList,
    );
  }

  List<Widget> _detailSections() {
    final AppUser user = _user!;
    final ShipmentRecord shipment = _shipment!;
    final bool medical = user.role == UserRole.medicalStaff;
    final bool quality = user.role == UserRole.qualityManager;
    final Widget status = TemperatureStatusCard(
      user: user,
      shipment: shipment,
      latest: _readings.isEmpty ? null : _readings.first,
      excursions: _excursions,
      latestActions: _latestActions,
      scenario: _scenario,
      insight: _insight,
      onChanged: _load,
      onOpenRecords: user.role == UserRole.transporter
          ? () {
              final BuildContext? target = _recordsKey.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(target);
              }
            }
          : null,
    );
    final Widget summary = _DetailCard(
      user: user,
      shipment: shipment,
      assigneeLoginId: _assigneeLoginId,
      reviewLabel: _reviews.isEmpty
          ? QualityReviewStatus.notReviewed.label
          : _reviews.last.status.label,
    );
    final Widget release = ShipmentReleasePanel(
      user: user,
      shipment: shipment,
      release: _release,
      onChanged: _load,
    );
    final Widget receipt = ShipmentReceiptPanel(
      user: user,
      shipment: shipment,
      receipt: _receipt,
      reviews: _reviews,
      excursions: _excursions,
      actions: _actions,
      onChanged: _load,
    );
    final Widget chart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quality)
          const Text(
            '온도 이탈 분석',
            key: Key('temperature-excursion-analysis'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        TemperatureChartView(
          readings: _chartReadings,
          minBound: shipment.tempMin,
          maxBound: shipment.tempMax,
          excursions: _excursions,
          compact: user.role == UserRole.transporter,
        ),
      ],
    );
    final Widget qualityReview = QualityReviewPanel(
      user: user,
      shipment: shipment,
      insight: _insight!,
      latest: _readings.isEmpty ? null : _readings.first,
      reviews: _reviews,
      actions: _actions,
      onChanged: _load,
    );
    final Widget records = _transportPanel();
    final bool transporter = user.role == UserRole.transporter;
    final Widget response = ResponseRecordPanel(
      key: _recordsKey,
      title: transporter ? '내 대응 기록' : '운송자 대응 보고',
      sectionKey: Key(
        transporter ? 'my-response-records' : 'transporter-response-report',
      ),
      actions: _actions,
      excursions: _excursions,
      emptyLabel: '등록된 대응 기록이 없습니다.',
      noticeUnlinkedExcursions: quality,
    );
    final Widget handover = _HandoverPanel(
      user: user,
      shipment: shipment,
      pending: _pending,
      history: _history,
      onChanged: _load,
    );
    final Widget history = ShipmentHistoryPanel(
      shipment: shipment,
      release: _release,
      transfers: _history,
      excursions: _excursions,
      actions: _actions,
      reviews: _reviews,
      receipt: _receipt,
    );
    final Widget storage = StorageConditionPanel(user: user, shipment: shipment);
    final List<Widget> ordered = <Widget>[
      if (transporter) ...<Widget>[
        status,
        _transportPanel(includeList: false),
        summary,
        chart,
        response,
      ],
      if (quality) ...<Widget>[
        summary,
        status,
        chart,
        response,
        qualityReview,
      ],
      if (medical) ...<Widget>[
        summary,
        qualityReview,
        receipt,
        status,
        DisclosureBlock(
          label: '온도 그래프와 측정 기록',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[chart, const SizedBox(height: 12), records],
          ),
        ),
      ],
      history,
      if (transporter) release,
      if (quality) release,
      if (quality) receipt,
      if (medical) release,
      storage,
      if (transporter) _transportPanel(includeSummary: false),
      if (quality) records,
      if (transporter || _pending != null || _history.isNotEmpty) handover,
    ];
    final List<Widget> spaced = <Widget>[];
    for (final Widget section in ordered) {
      if (spaced.isNotEmpty) {
        spaced.add(const SizedBox(height: 16));
      }
      spaced.add(section);
    }
    return spaced;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '운송 건 목록',
          onPressed: _backToList,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const VaxLogo(compact: true, light: true),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const Text(
            '운송 건 상세',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text('저장된 운송 건 정보를 확인합니다.'),
          const SizedBox(height: 16),
          if (_loading)
            const Text('불러오는 중')
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger))
          else
            ..._detailSections(),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.user,
    required this.shipment,
    required this.assigneeLoginId,
    required this.reviewLabel,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final String assigneeLoginId;
  final String reviewLabel;

  List<Widget> _foldedShipmentRows(String assigneeLoginId) {
    return [
      ShipmentInfoRow(
        label: '제조사',
        value: shipment.manufacturer,
        valueKey: const Key('shipment-manufacturer'),
      ),
      ShipmentInfoRow(
        label: 'LOT 번호',
        value: shipment.lot,
        valueKey: const Key('shipment-lot'),
      ),
      ShipmentInfoRow(
        label: '유효기간',
        value: shipment.expiryDate,
        valueKey: const Key('shipment-expiry'),
      ),
      ShipmentInfoRow(
        label: '수량',
        value: '${shipment.quantity} 회분',
        valueKey: const Key('shipment-quantity'),
      ),
      ShipmentInfoRow(
        label: '출발지',
        value: shipment.origin,
        valueKey: const Key('shipment-origin'),
      ),
      ShipmentInfoRow(
        label: '도착지',
        value: shipment.destination,
        valueKey: const Key('shipment-destination'),
      ),
      ShipmentInfoRow(
        label: '설정 온도 범위',
        value: shipment.temperatureRangeLabel,
        valueKey: const Key('shipment-temp-range'),
      ),
      if (shipment.startedAt != null)
        ShipmentInfoRow(
          label: '운송 시작',
          value: formatHandoverTime(shipment.startedAt),
          valueKey: const Key('transport-started-at'),
        ),
      if (shipment.completedAt != null)
        ShipmentInfoRow(
          label: '운송 완료',
          value: formatHandoverTime(shipment.completedAt),
          valueKey: const Key('transport-completed-at'),
        ),
      ShipmentInfoRow(
        label: '현재 담당 운송자',
        value: assigneeLoginId,
        valueKey: const Key('assignee-login'),
      ),
      if (DemoMode.label(shipment.demoMode) != null)
        ShipmentInfoRow(
          label: '시연 방식',
          value: DemoMode.label(shipment.demoMode)!,
          valueKey: const Key('shipment-demo-mode'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool isTransporter = user.role == UserRole.transporter;
    final bool isMedical = user.role == UserRole.medicalStaff;
    final double? tempMin = shipment.tempMin;
    final double? tempMax = shipment.tempMax;

    return Container(
      key: const Key('shipment-detail'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMedical) ...[
            ShipmentInfoRow(
              label: '백신명',
              value: shipment.vaccine,
              valueKey: const Key('shipment-vaccine'),
            ),
            ShipmentInfoRow(
              label: '운송 건 ID',
              value: shipment.displayId,
              valueKey: const Key('shipment-display-id'),
            ),
            ShipmentInfoRow(
              label: '운송 상태',
              value: shipment.status.label,
              valueKey: const Key('shipment-status'),
            ),
            ShipmentInfoRow(
              label: '품질 검토',
              value: reviewLabel,
              valueKey: const Key('quality-review-state'),
            ),
            const SizedBox(height: 8),
            const Text(
              '온도 측정과 품질 검토 전에는 투여 가능 여부를 판단하지 않습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            DisclosureBlock(
              label: '운송 정보 자세히 보기',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _foldedShipmentRows(assigneeLoginId),
              ),
            ),
          ],
          if (!isMedical) ...[
          ShipmentInfoRow(
            label: '운송 건 ID',
            value: shipment.displayId,
            valueKey: const Key('shipment-display-id'),
          ),
          if (isTransporter)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 108,
                    child: Text(
                      '참여 코드',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      shipment.participationCode,
                      key: const Key('participation-code-value'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: '참여 코드 복사',
                    child: IconButton(
                      key: const Key('copy-participation-code'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => copyParticipationCode(
                        context,
                        shipment.participationCode,
                      ),
                      icon: const Icon(Icons.copy, color: AppColors.teal),
                    ),
                  ),
                ],
              ),
            ),
          ShipmentInfoRow(
            label: '백신명',
            value: shipment.vaccine,
            valueKey: const Key('shipment-vaccine'),
          ),
          ShipmentInfoRow(
            label: '제조사',
            value: shipment.manufacturer,
            valueKey: const Key('shipment-manufacturer'),
          ),
          ShipmentInfoRow(
            label: 'LOT 번호',
            value: shipment.lot,
            valueKey: const Key('shipment-lot'),
          ),
          ShipmentInfoRow(
            label: '유효기간',
            value: shipment.expiryDate,
            valueKey: const Key('shipment-expiry'),
          ),
          ShipmentInfoRow(
            label: '수량',
            value: '${shipment.quantity} 회분',
            valueKey: const Key('shipment-quantity'),
          ),
          ShipmentInfoRow(
            label: '출발지',
            value: shipment.origin,
            valueKey: const Key('shipment-origin'),
          ),
          ShipmentInfoRow(
            label: '도착지',
            value: shipment.destination,
            valueKey: const Key('shipment-destination'),
          ),
          ShipmentInfoRow(
            label: '설정 온도 범위',
            value: shipment.temperatureRangeLabel,
            valueKey: const Key('shipment-temp-range'),
          ),
          if (shipment.startedAt != null)
            ShipmentInfoRow(
              label: '운송 시작',
              value: formatHandoverTime(shipment.startedAt),
              valueKey: const Key('transport-started-at'),
            ),
          if (shipment.completedAt != null)
            ShipmentInfoRow(
              label: '운송 완료',
              value: formatHandoverTime(shipment.completedAt),
              valueKey: const Key('transport-completed-at'),
            ),
          if (user.role == UserRole.qualityManager) ...[
            ShipmentInfoRow(
              label: '온도 하한',
              value: tempMin == null
                  ? '미입력'
                  : TemperatureBounds.formatCelsius(tempMin),
            ),
            ShipmentInfoRow(
              label: '온도 상한',
              value: tempMax == null
                  ? '미입력'
                  : TemperatureBounds.formatCelsius(tempMax),
            ),
          ],
          ShipmentInfoRow(
            label: '현재 담당 운송자',
            value: assigneeLoginId,
            valueKey: const Key('assignee-login'),
          ),
          ShipmentInfoRow(
            label: '운송 상태',
            value: shipment.status.label,
            valueKey: const Key('shipment-status'),
          ),
          if (DemoMode.label(shipment.demoMode) != null)
            ShipmentInfoRow(
              label: '시연 방식',
              value: DemoMode.label(shipment.demoMode)!,
              valueKey: const Key('shipment-demo-mode'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransportPanel extends StatefulWidget {
  const _TransportPanel({
    required this.user,
    required this.shipment,
    required this.readings,
    required this.readingCount,
    required this.release,
    required this.onChanged,
    required this.onLoadMore,
    this.includeSummary = true,
    this.includeList = true,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final List<TemperatureReading> readings;
  final int readingCount;
  final ShipmentRelease? release;
  final Future<void> Function() onChanged;
  final Future<void> Function() onLoadMore;
  final bool includeSummary;
  final bool includeList;

  @override
  State<_TransportPanel> createState() => _TransportPanelState();
}

class _TransportPanelState extends State<_TransportPanel> {
  bool _busy = false;

  bool get _isAssignee => widget.user.id == widget.shipment.assigneeUserId;

  bool get _showList => widget.user.role != UserRole.medicalStaff;

  Future<void> _start() async {
    if (widget.shipment.releaseRequired && widget.release == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('출고 확인을 먼저 해 주세요.')));
      return;
    }
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('자동 시연 방식'),
          content: const Text(
            '시연용 가상 온도입니다. 실제 센서 값이 아닙니다. '
            '기존 운송 건은 기존 방식을 유지할 수 있습니다. '
            '이상 발생만으로 조치 기록이나 품질 검토가 완료되지 않습니다.',
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('demo-mode-probabilistic'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(DemoMode.probabilistic),
              child: const Text('일반 자동 시연'),
            ),
            TextButton(
              key: const Key('demo-mode-presentation'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(DemoMode.presentation),
              child: const Text('발표용 자동 시연'),
            ),
            TextButton(
              key: const Key('demo-mode-legacy'),
              onPressed: () => Navigator.of(dialogContext).pop('legacy'),
              child: const Text('기존 방식'),
            ),
          ],
        );
      },
    );
    if (choice == null || !mounted) {
      return;
    }
    await _run(() async {
      await AppDatabase.instance.startTransport(
        actorUserId: widget.user.id,
        shipmentId: widget.shipment.id,
        demoMode: choice == 'legacy' ? null : choice,
      );
      DemoTemperatureSession.instance.ensureRunning();
      DemoTemperatureSession.instance.notifySamplesChanged();
    }, '운송을 시작했습니다. 시연용 온도 기록을 저장합니다.');
  }

  Future<void> _complete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('운송 완료'),
          content: const Text(
            '운송을 완료하면 시연용 온도 생성이 멈추고 다시 시작할 수 없습니다. 이미 저장된 온도 기록은 남습니다.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              key: const Key('confirm-complete'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('운송 완료'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(() async {
      await AppDatabase.instance.completeTransport(
        actorUserId: widget.user.id,
        shipmentId: widget.shipment.id,
      );
      await DemoTemperatureSession.instance.restore();
      DemoTemperatureSession.instance.notifySamplesChanged();
    }, '운송을 완료했습니다. 온도 기록이 유지됩니다.');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      await widget.onChanged();
    } on TransportException catch (error) {
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
          .showSnackBar(const SnackBar(content: Text('운송 상태를 저장하지 못했습니다.')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TemperatureReading? latest = widget.readings.isEmpty
        ? null
        : widget.readings.first;
    final bool canStart =
        _isAssignee &&
        widget.user.role == UserRole.transporter &&
        widget.shipment.status == ShipmentStatus.registered &&
        !_busy;
    final bool canComplete =
        _isAssignee &&
        widget.user.role == UserRole.transporter &&
        widget.shipment.status == ShipmentStatus.inTransit &&
        !_busy;

    final Widget measurementList = TemperatureMeasurementList(
      readings: widget.readings,
      tempMin: widget.shipment.tempMin,
      tempMax: widget.shipment.tempMax,
      totalCount: widget.readingCount,
      onLoadMore: widget.onLoadMore,
    );
    if (!widget.includeSummary) {
      return measurementList;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('온도 기록', style: TextStyle(fontWeight: FontWeight.w700)),
        if (!_showList) ...[
          const SizedBox(height: 4),
          const Text(
            '시연용 가상 데이터 · 5초 간격 측정',
            key: Key('temperature-record-header'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
        ShipmentInfoRow(
          label: '최신 온도',
          value: latest == null ? '측정 전' : latest.temperatureLabel,
          valueKey: const Key('temperature-data-state'),
        ),
        ShipmentInfoRow(
          label: '마지막 측정',
          value: latest == null
              ? '없음'
              : formatMeasurementTime(latest.measuredAt),
          valueKey: const Key('temperature-measured-at'),
        ),
        ShipmentInfoRow(
          label: '데이터 출처',
          value: latest == null ? '없음' : latest.sourceLabel,
          valueKey: const Key('temperature-source'),
        ),
        if (widget.user.role == UserRole.medicalStaff)
          ShipmentInfoRow(
            label: '온도 기록',
            value: widget.readingCount == 0
                ? '없음'
                : '${widget.readingCount}건 있음',
            valueKey: const Key('temperature-record-presence'),
          ),
        if (canStart)
          ElevatedButton(
            key: const Key('start-transport'),
            onPressed: _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('운송 시작'),
          ),
        if (canComplete)
          ElevatedButton(
            key: const Key('complete-transport'),
            onPressed: _complete,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('운송 완료'),
          ),
        if (widget.includeList && _showList) ...[
          const SizedBox(height: 8),
          measurementList,
        ],
      ],
    );
  }
}

class _HandoverPanel extends StatelessWidget {
  const _HandoverPanel({
    required this.user,
    required this.shipment,
    required this.pending,
    required this.history,
    required this.onChanged,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final ShipmentTransfer? pending;
  final List<ShipmentTransfer> history;
  final Future<void> Function() onChanged;

  bool get _isAssignee => user.id == shipment.assigneeUserId;

  bool get _detailed => user.role != UserRole.medicalStaff;

  Future<void> _request(BuildContext context) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            HandoverRequestScreen(shipmentId: shipment.id),
      ),
    );
    if (saved == true) {
      await onChanged();
    }
  }

  Future<void> _act(
    BuildContext context,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
      await onChanged();
    } on TransferException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('인수인계를 처리하지 못했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShipmentTransfer? pending = this.pending;
    final bool canRequest =
        user.role == UserRole.transporter &&
        _isAssignee &&
        shipment.status != ShipmentStatus.completed &&
        pending == null;
    final bool canCancel = pending != null && pending.fromUserId == user.id;
    final bool canRespond = pending != null && pending.toUserId == user.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pending == null ? '인수인계 없음' : '인수인계 ${pending.status.label}',
          key: const Key('handover-status'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (canRequest)
          ElevatedButton(
            key: const Key('request-handover'),
            onPressed: () => _request(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('인수인계 요청'),
          ),
        if (canCancel)
          TextButton(
            key: const Key('cancel-handover'),
            onPressed: () => _act(context, () async {
              await AppDatabase.instance.cancelHandover(
                actorUserId: user.id,
                transferId: pending.id,
              );
            }, '인수인계 요청을 취소했습니다.'),
            child: const Text('요청 취소'),
          ),
        if (canRespond)
          Row(
            children: [
              TextButton(
                key: const Key('accept-handover'),
                onPressed: () => _act(context, () async {
                  await AppDatabase.instance.acceptHandover(
                    actorUserId: user.id,
                    transferId: pending.id,
                  );
                }, '인수인계를 수락했습니다.'),
                child: const Text('수락'),
              ),
              TextButton(
                key: const Key('reject-handover'),
                onPressed: () => _act(context, () async {
                  await AppDatabase.instance.rejectHandover(
                    actorUserId: user.id,
                    transferId: pending.id,
                  );
                }, '인수인계를 거절했습니다.'),
                child: const Text('거절'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        const Text('인수인계 이력', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          '인계 당시 온도는 아직 기록하지 않습니다.',
          key: Key('handover-temperature-note'),
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Text('인수인계 이력이 없습니다.')
        else
          ...history.map(
            (ShipmentTransfer transfer) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _detailed
                  ? _DetailedHistory(transfer: transfer)
                  : _SummaryHistory(transfer: transfer),
            ),
          ),
      ],
    );
  }
}

class _DetailedHistory extends StatelessWidget {
  const _DetailedHistory({required this.transfer});

  final ShipmentTransfer transfer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(label: transfer.status.label),
        ShipmentInfoRow(label: '인계자', value: transfer.fromLoginId),
        ShipmentInfoRow(label: '인수자', value: transfer.toLoginId),
        ShipmentInfoRow(
          label: '요청 시각',
          value: formatHandoverTime(transfer.requestedAt),
        ),
        ShipmentInfoRow(
          label: '처리 시각',
          value: formatHandoverTime(transfer.respondedAt),
        ),
        ShipmentInfoRow(
          label: '장소',
          value: transfer.location.isEmpty ? '미기록' : transfer.location,
        ),
        ShipmentInfoRow(
          label: '예정 시각',
          value: formatHandoverTime(transfer.scheduledAt),
        ),
        ShipmentInfoRow(label: '처리 결과', value: transfer.status.label),
        ShipmentInfoRow(label: '메모', value: transfer.note ?? '없음'),
        if (transfer.rejectionReason != null)
          ShipmentInfoRow(label: '거절 사유', value: transfer.rejectionReason!),
      ],
    );
  }
}

class _SummaryHistory extends StatelessWidget {
  const _SummaryHistory({required this.transfer});

  final ShipmentTransfer transfer;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${transfer.fromLoginId} → ${transfer.toLoginId} · '
      '${transfer.status.label} · ${formatHandoverTime(transfer.respondedAt)}',
    );
  }
}
