import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/shipment_analytics.dart';
import '../data/shipment_summary.dart';
import '../models/app_user.dart';
import '../models/excursion_action.dart';
import '../models/quality_review.dart';
import '../models/shipment_record.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import 'dashboard_widgets.dart';

/// 품질 검토 입력과 이력입니다. 온도 기록과 위험도 계산은 바꾸지 않습니다.
class QualityReviewPanel extends StatefulWidget {
  const QualityReviewPanel({
    super.key,
    required this.user,
    required this.shipment,
    required this.insight,
    required this.latest,
    required this.reviews,
    this.actions = const <ExcursionAction>[],
    required this.onChanged,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final ShipmentInsight insight;
  final TemperatureReading? latest;
  final List<QualityReview> reviews;
  final List<ExcursionAction> actions;
  final Future<void> Function() onChanged;

  @override
  State<QualityReviewPanel> createState() => _QualityReviewPanelState();
}

class _QualityReviewPanelState extends State<QualityReviewPanel> {
  final TextEditingController _comment = TextEditingController();
  QualityReviewStatus _status = QualityReviewStatus.inReview;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  bool get _canEdit => widget.user.role == UserRole.qualityManager;

  QualityReview? get _latest =>
      widget.reviews.isEmpty ? null : widget.reviews.last;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppDatabase.instance.saveQualityReview(
        actorUserId: widget.user.id,
        shipmentId: widget.shipment.id,
        status: _status,
        comment: _comment.text,
      );
      _comment.clear();
      await widget.onChanged();
    } on QualityReviewException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '검토 기록을 저장하지 못했습니다.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final QualityReview? latest = _latest;
    final QualityReviewStatus current =
        latest?.status ?? QualityReviewStatus.notReviewed;
    final bool medical = widget.user.role == UserRole.medicalStaff;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            medical ? '품질 검토 결과' : '품질 검토',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (medical) ...[
            const SizedBox(height: 8),
            Text(
              buildShipmentNarrative(
                shipment: widget.shipment,
                insight: widget.insight,
                latestReview: latest,
                actions: widget.actions,
              ),
              key: const Key('medical-shipment-summary'),
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '품질 검토 상태: ${current.label}',
            key: const Key('quality-review-current'),
          ),
          if (medical) ...[
            Text(
              widget.insight.excursions.count == 0 ? '온도 이탈: 없음' : '온도 이탈: 있음',
            ),
            Text(
              widget.actions.isEmpty
                  ? '운송자 조치 기록: 없음'
                  : '운송자 대응 기록: ${widget.actions.length}건',
              key: const Key('response-action-history'),
            ),
          ],
          Text(
            current.medicalMessage,
            key: const Key('quality-review-message'),
          ),
          if (latest != null) ...[
            Text('최근 검토 의견: ${latest.comment.isEmpty ? '없음' : latest.comment}'),
            Text('검토자: ${latest.reviewerLoginId}'),
            Text('검토 시각: ${formatMeasurementTime(latest.createdAt)}'),
          ],
          if (_canEdit) ...[
            const SizedBox(height: 8),
            Text(
              '운송 건 ${widget.shipment.displayId} · ${widget.shipment.vaccine}',
            ),
            Text('운송 상태: ${widget.shipment.status.label}'),
            Text('운영 위험 수준: ${widget.insight.risk.level.label}'),
            DisclosureBlock(
              label: '판단 근거 보기',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 또는 마지막 온도: ${widget.latest == null ? '아직 기록되지 않음' : widget.latest!.temperatureLabel}',
                  ),
                  Text('설정 온도 범위: ${widget.shipment.temperatureRangeLabel}'),
                  Text('온도 이탈 횟수: ${widget.insight.excursions.count}회'),
                  Text(
                    '최대 상한 초과: ${widget.insight.excursions.maxAboveExcess?.toStringAsFixed(1) ?? '없음'}°C',
                  ),
                  Text(
                    '최대 하한 미달: ${widget.insight.excursions.maxBelowShortfall?.toStringAsFixed(1) ?? '없음'}°C',
                  ),
                  Text('관측된 이탈 지속시간: ${widget.insight.excursions.durationLabel}'),
                  Text('데이터 공백: ${widget.insight.hasGap ? '있음' : '없음'}'),
                  Text(
                    '원인 및 조치 기록: ${widget.insight.excursions.count == 0
                        ? '해당 없음'
                        : widget.insight.excursions.missingAction
                        ? '미작성'
                        : '작성 완료'}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<QualityReviewStatus>(
              key: const Key('quality-review-status'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '검토 상태'),
              items: <DropdownMenuItem<QualityReviewStatus>>[
                for (final QualityReviewStatus status
                    in QualityReviewStatus.editable)
                  DropdownMenuItem<QualityReviewStatus>(
                    value: status,
                    child: Text(status.label),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (QualityReviewStatus? value) {
                      if (value != null) {
                        setState(() => _status = value);
                      }
                    },
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('quality-review-comment'),
              controller: _comment,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '검토 의견',
                hintText: '확인한 기록과 의견을 입력합니다.',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const Key('quality-review-save'),
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              child: Text(_saving ? '저장 중' : '검토 저장'),
            ),
          ],
          if (medical) ...[
            const SizedBox(height: 8),
            const Text(
              '검토 완료는 백신의 접종 가능 여부를 의미하지 않습니다. 실제 사용 여부는 관련 품질관리 절차와 제품별 안정성 자료를 근거로 별도 판단해야 합니다.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
          Material(
            color: AppColors.card,
            child: ExpansionTile(
              key: const Key('quality-review-history'),
              tilePadding: EdgeInsets.zero,
              title: Text('검토 이력 ${widget.reviews.length}건'),
              children: [
                if (widget.reviews.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('품질관리자의 검토 기록이 없습니다.'),
                  )
                else
                  for (final QualityReview review in widget.reviews)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${formatMeasurementTime(review.createdAt)}\n'
                          '${review.reviewerLoginId}\n'
                          '${review.status.label}'
                          '${review.comment.isEmpty ? '' : '\n${review.comment}'}',
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
