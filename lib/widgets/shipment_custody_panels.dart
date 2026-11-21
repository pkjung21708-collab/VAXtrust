import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/shipment_history.dart';
import '../models/app_user.dart';
import '../models/excursion_action.dart';
import '../models/quality_review.dart';
import '../models/shipment_receipt.dart';
import '../models/shipment_record.dart';
import '../models/shipment_release.dart';
import '../models/shipment_transfer.dart';
import '../models/temperature_excursion.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import 'shipment_widgets.dart';

class ShipmentReleasePanel extends StatefulWidget {
  const ShipmentReleasePanel({
    super.key,
    required this.user,
    required this.shipment,
    required this.release,
    required this.onChanged,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final ShipmentRelease? release;
  final Future<void> Function() onChanged;

  @override
  State<ShipmentReleasePanel> createState() => _ShipmentReleasePanelState();
}

class _ShipmentReleasePanelState extends State<ShipmentReleasePanel> {
  final TextEditingController _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      widget.user.role == UserRole.transporter &&
      widget.user.id == widget.shipment.assigneeUserId &&
      widget.shipment.status == ShipmentStatus.registered &&
      widget.release == null;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await AppDatabase.instance.confirmRelease(
        actorUserId: widget.user.id,
        shipmentId: widget.shipment.id,
        note: _note.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('출고를 확인했습니다.')));
      await widget.onChanged();
    } on CustodyException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShipmentRelease? release = widget.release;
    return _CustodyCard(
      title: '출고 확인',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShipmentInfoRow(label: '백신', value: widget.shipment.vaccine),
          ShipmentInfoRow(label: '제조사', value: widget.shipment.manufacturer),
          ShipmentInfoRow(label: 'LOT', value: widget.shipment.lot),
          ShipmentInfoRow(label: '유효기간', value: widget.shipment.expiryDate),
          ShipmentInfoRow(
            label: '출고 예정 수량',
            value: '${widget.shipment.quantity}',
          ),
          ShipmentInfoRow(label: '출발지', value: widget.shipment.origin),
          ShipmentInfoRow(label: '목적지', value: widget.shipment.destination),
          if (release == null)
            const Text(
              '출고 확인 기록 없음',
              key: Key('release-missing'),
              style: TextStyle(color: AppColors.textSecondary),
            )
          else ...[
            ShipmentInfoRow(
              label: '출고 담당자',
              value: release.confirmedByLoginId,
              valueKey: const Key('release-user'),
            ),
            ShipmentInfoRow(
              label: '출고 확인 시각',
              value: historyClock(release.confirmedAt),
              valueKey: const Key('release-time'),
            ),
            ShipmentInfoRow(label: '출고 메모', value: release.note ?? '없음'),
          ],
          if (widget.shipment.releaseRequired && release == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '운송 시작 전에 출고 확인이 필요합니다.',
                key: Key('release-required-note'),
                style: TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          if (_canConfirm) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('release-note'),
              controller: _note,
              decoration: const InputDecoration(
                labelText: '출고 메모',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const Key('confirm-release'),
              onPressed: _busy ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('출고 확인'),
            ),
          ],
        ],
      ),
    );
  }
}

class ShipmentReceiptPanel extends StatefulWidget {
  const ShipmentReceiptPanel({
    super.key,
    required this.user,
    required this.shipment,
    required this.receipt,
    required this.reviews,
    required this.excursions,
    required this.actions,
    required this.onChanged,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final ShipmentReceipt? receipt;
  final List<QualityReview> reviews;
  final List<TemperatureExcursion> excursions;
  final List<ExcursionAction> actions;
  final Future<void> Function() onChanged;

  @override
  State<ShipmentReceiptPanel> createState() => _ShipmentReceiptPanelState();
}

class _ShipmentReceiptPanelState extends State<ShipmentReceiptPanel> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _package = PackageCondition.intact;
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  QualityReviewStatus get _reviewStatus => widget.reviews.isEmpty
      ? QualityReviewStatus.notReviewed
      : widget.reviews.last.status;

  bool get _canConfirm =>
      widget.user.role == UserRole.medicalStaff &&
      widget.shipment.status == ShipmentStatus.completed &&
      widget.receipt == null;

  Future<void> _confirm() async {
    final int? quantity = int.tryParse(_quantity.text.trim());
    if (quantity == null || quantity < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('도착 수량을 숫자로 입력해 주세요.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDatabase.instance.confirmReceipt(
        actorUserId: widget.user.id,
        shipmentId: widget.shipment.id,
        receivedQuantity: quantity,
        packageCondition: _package,
        note: _note.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('물품 수령을 기록했습니다.')));
      await widget.onChanged();
    } on CustodyException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShipmentReceipt? receipt = widget.receipt;
    final int typed = int.tryParse(_quantity.text.trim()) ?? -1;
    final bool draftMismatch =
        _canConfirm && typed >= 0 && typed != widget.shipment.quantity;
    final bool savedMismatch =
        receipt != null &&
        receipt.quantityDiffersFrom(widget.shipment.quantity);
    final bool attention =
        (receipt?.needsSeparateCheck(widget.shipment.quantity) ?? false) ||
        draftMismatch ||
        (_canConfirm && _package != PackageCondition.intact);
    final String actionSummary = widget.actions.isEmpty
        ? '대응 기록 없음'
        : '${widget.actions.length}건 · ${widget.actions.last.actionTaken}';
    return _CustodyCard(
      title: '의료기관 인수',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '인수는 물품 수령입니다. 품질 적합, 사용 승인, 접종 가능을 뜻하지 않습니다.',
            key: Key('receipt-not-approval'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          ShipmentInfoRow(label: '운송 건 ID', value: widget.shipment.displayId),
          ShipmentInfoRow(label: '백신', value: widget.shipment.vaccine),
          ShipmentInfoRow(label: '제조사', value: widget.shipment.manufacturer),
          ShipmentInfoRow(label: 'LOT', value: widget.shipment.lot),
          ShipmentInfoRow(label: '유효기간', value: widget.shipment.expiryDate),
          ShipmentInfoRow(
            label: '출고 수량',
            value: '${widget.shipment.quantity}',
            valueKey: const Key('shipped-quantity'),
          ),
          ShipmentInfoRow(
            label: '운송 완료',
            value: widget.shipment.completedAt == null
                ? '운송 미완료'
                : historyClock(widget.shipment.completedAt!),
          ),
          ShipmentInfoRow(
            label: '온도 이탈',
            value: widget.excursions.isEmpty ? '없음' : '있음',
            valueKey: const Key('receipt-excursion-state'),
          ),
          ShipmentInfoRow(
            label: '품질 검토',
            value: _reviewStatus.label,
            valueKey: const Key('receipt-review-state'),
          ),
          if (_reviewStatus != QualityReviewStatus.reviewCompleted)
            Text(
              _reviewStatus.medicalMessage,
              key: const Key('receipt-review-warning'),
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ShipmentInfoRow(label: '대응 기록', value: actionSummary),
          if (receipt == null)
            const Text(
              '미인수',
              key: Key('receipt-missing'),
              style: TextStyle(color: AppColors.textSecondary),
            )
          else ...[
            ShipmentInfoRow(
              label: '도착 수량',
              value: '${receipt.receivedQuantity}',
              valueKey: const Key('received-quantity'),
            ),
            ShipmentInfoRow(
              label: '포장 상태',
              value: receipt.packageLabel,
              valueKey: const Key('received-package'),
            ),
            ShipmentInfoRow(
              label: '인수 담당',
              value: receipt.receiverLoginId,
              valueKey: const Key('receipt-user'),
            ),
            ShipmentInfoRow(
              label: '인수 시각',
              value: historyClock(receipt.receivedAt),
              valueKey: const Key('receipt-time'),
            ),
            ShipmentInfoRow(label: '인수 메모', value: receipt.note ?? '없음'),
          ],
          if (savedMismatch || draftMismatch)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '출고 수량과 도착 수량이 일치하지 않습니다.',
                key: Key('receipt-mismatch'),
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          if (attention)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '수량 불일치 또는 포장 이상은 별도 확인이 필요합니다.',
                key: Key('receipt-attention'),
                style: TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          if (widget.shipment.status != ShipmentStatus.completed &&
              receipt == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('운송이 완료된 뒤 인수할 수 있습니다.'),
            ),
          if (_canConfirm) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('receipt-quantity'),
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '실제 도착 수량',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('receipt-package'),
              initialValue: _package,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '포장 상태'),
              items: <DropdownMenuItem<String>>[
                for (final String value in PackageCondition.values)
                  DropdownMenuItem<String>(
                    value: value,
                    child: Text(PackageCondition.label(value)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (String? value) {
                      if (value != null) {
                        setState(() => _package = value);
                      }
                    },
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('receipt-note'),
              controller: _note,
              decoration: const InputDecoration(
                labelText: '인수 메모',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const Key('confirm-receipt'),
              onPressed: _busy ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('인수 확인'),
            ),
          ],
        ],
      ),
    );
  }
}

class ShipmentHistoryPanel extends StatefulWidget {
  const ShipmentHistoryPanel({
    super.key,
    required this.shipment,
    required this.release,
    required this.transfers,
    required this.excursions,
    required this.actions,
    required this.reviews,
    required this.receipt,
  });

  final ShipmentRecord shipment;
  final ShipmentRelease? release;
  final List<ShipmentTransfer> transfers;
  final List<TemperatureExcursion> excursions;
  final List<ExcursionAction> actions;
  final List<QualityReview> reviews;
  final ShipmentReceipt? receipt;

  @override
  State<ShipmentHistoryPanel> createState() => _ShipmentHistoryPanelState();
}

class _ShipmentHistoryPanelState extends State<ShipmentHistoryPanel> {
  int? _openIndex;

  @override
  Widget build(BuildContext context) {
    final List<ShipmentHistoryEntry> entries = buildShipmentHistory(
      shipment: widget.shipment,
      release: widget.release,
      transfers: widget.transfers,
      excursions: widget.excursions,
      actions: widget.actions,
      reviews: widget.reviews,
      receipt: widget.receipt,
    );
    return _CustodyCard(
      title: '운송 이력',
      child: Column(
        key: const Key('shipment-history'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < entries.length; index++)
            _HistoryRow(
              entry: entries[index],
              expanded: _openIndex == index,
              onTap: () {
                setState(() {
                  _openIndex = _openIndex == index ? null : index;
                });
              },
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final ShipmentHistoryEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('history-${entry.title}-${entry.at.toUtc().toIso8601String()}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${historyClock(entry.at)} · ${entry.title}'),
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 8),
                child: Text(
                  entry.detail,
                  key: Key('history-detail-${entry.title}'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustodyCard extends StatelessWidget {
  const _CustodyCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE1EAED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}
