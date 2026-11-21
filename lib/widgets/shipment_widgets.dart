import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../data/shipment_analytics.dart';
import '../models/demo_scenario.dart';
import '../models/quality_review.dart';
import '../models/shipment_record.dart';
import '../models/temperature_excursion.dart';
import '../models/temperature_reading.dart';
import '../theme/app_theme.dart';
import 'dashboard_widgets.dart';

/// 목록 카드에서 역할마다 보여줄 항목을 고릅니다.
enum ShipmentCardKind { transporter, quality, medical }

Future<void> copyParticipationCode(BuildContext context, String code) async {
  await Clipboard.setData(ClipboardData(text: code));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('참여 코드를 복사했습니다.')));
}

class ShipmentInfoRow extends StatelessWidget {
  const ShipmentInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StoredShipmentCard extends StatelessWidget {
  const StoredShipmentCard({
    super.key,
    required this.shipment,
    required this.kind,
    required this.onTap,
    this.latest,
    this.excursion,
    this.insight,
    this.review,
  });

  final ShipmentRecord shipment;
  final ShipmentCardKind kind;
  final VoidCallback onTap;
  final TemperatureReading? latest;
  final ExcursionSummary? excursion;
  final ShipmentInsight? insight;
  final QualityReview? review;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
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
                      shipment.displayId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.teal,
                      ),
                    ),
                  ),
                  StatusChip(label: shipment.status.label),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                shipment.vaccine,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text('${shipment.origin} → ${shipment.destination}'),
              const SizedBox(height: 4),
              Text(
                shipment.lot,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '최신 온도 ${latest == null ? '측정 전' : latest!.temperatureLabel}'
                ' · 설정 ${shipment.temperatureRangeLabel}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                latest == null
                    ? '아직 기록되지 않음'
                    : '${latest!.sourceLabel} · 마지막 측정 ${formatMeasurementTime(latest!.measuredAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (insight != null) ...[
                Text(
                  '운영 위험 수준: ${insight!.risk.level.label}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (insight!.risk.reasons.isNotEmpty)
                  DisclosureBlock(
                    label: '판단 근거 보기',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final String reason in insight!.risk.reasons)
                          Text(
                            '판단 근거: $reason',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (insight!.hasGap)
                  const Text(
                    '데이터 공백: 확인 필요',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                Text(
                  '품질 검토 상태: ${review?.status.label ?? QualityReviewStatus.notReviewed.label}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (kind == ShipmentCardKind.medical) _medicalExcursionLines(),
              if (kind == ShipmentCardKind.quality) _qualityExcursionLines(),
              if (kind == ShipmentCardKind.transporter) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '참여 코드 ${shipment.participationCode}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: '참여 코드 복사',
                      child: TextButton.icon(
                        key: ValueKey<String>('copy-code-${shipment.id}'),
                        onPressed: () => copyParticipationCode(
                          context,
                          shipment.participationCode,
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('복사'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.teal,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _currentTemperatureState() {
    final TemperatureReading? reading = latest;
    final double? min = shipment.tempMin;
    final double? max = shipment.tempMax;
    if (reading == null || min == null || max == null) {
      return '측정 전';
    }
    if (reading.celsius > max) {
      return '상한 이탈';
    }
    if (reading.celsius < min) {
      return '하한 이탈';
    }
    if ((excursion?.count ?? 0) > 0) {
      return '정상 범위 복귀';
    }
    return '설정 범위 내';
  }

  Widget _medicalExcursionLines() {
    final int count = excursion?.count ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '온도 이탈 기록: $count건',
          style: TextStyle(
            fontSize: 12,
            color: count == 0 ? AppColors.textSecondary : AppColors.danger,
            fontWeight: count == 0 ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
        Text(
          '현재 온도: ${_currentTemperatureState()}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          '온도 이탈 이력: ${count == 0 ? '없음' : '있음'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Text(
          '시연용 가상 데이터입니다. 실제 센서 측정이 아닙니다. 투여 여부는 정하지 않습니다',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _qualityExcursionLines() {
    final int count = excursion?.count ?? 0;
    final bool open = excursion?.open ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          open
              ? '온도 이탈 여부: 이탈 중'
              : count == 0
              ? '온도 이탈 여부: 없음'
              : '온도 이탈 여부: 기록 있음',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          '누적 온도 이탈: $count건 · ${open ? '현재 이탈 중' : '현재 이탈 없음'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          '온도 이탈 이력: ${count == 0 ? '없음' : '있음'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class ParticipationCodeJoinCard extends StatefulWidget {
  const ParticipationCodeJoinCard({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<ParticipationCodeJoinCard> createState() =>
      _ParticipationCodeJoinCardState();
}

class _JoinNotice {
  const _JoinNotice({required this.message, required this.isError});

  final String message;
  final bool isError;
}

class _ParticipationCodeJoinCardState extends State<ParticipationCodeJoinCard> {
  final TextEditingController _controller = TextEditingController();

  bool _submitting = false;
  _JoinNotice? _notice;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    FocusScope.of(context).unfocus();
    final String code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _notice = const _JoinNotice(message: '참여 코드를 입력해 주세요.', isError: true);
      });
      return;
    }

    setState(() {
      _submitting = true;
      _notice = null;
    });

    try {
      final user = await AppDatabase.instance.currentSessionUser();
      if (!mounted) {
        return;
      }
      if (user == null) {
        setState(() {
          _notice = const _JoinNotice(
            message: '로그인 정보가 없습니다. 다시 로그인해 주세요.',
            isError: true,
          );
        });
        return;
      }

      final ShipmentJoinResult? result = await AppDatabase.instance
          .joinByParticipationCode(userId: user.id, code: code);
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() {
          _notice = const _JoinNotice(
            message: '존재하지 않는 참여 코드입니다.',
            isError: true,
          );
        });
        return;
      }

      if (!result.alreadyJoined) {
        _controller.clear();
      }
      setState(() {
        _notice = _JoinNotice(
          message: result.alreadyJoined ? '이미 연결된 운송 건입니다.' : '운송 건이 연결되었습니다.',
          isError: false,
        );
      });
      widget.onChanged();
    } on ArgumentError catch (error) {
      final Object? message = error.message;
      _showNotice(
        message is String && message.trim().isNotEmpty
            ? message
            : '참여 코드를 연결하지 못했습니다.',
        isError: true,
      );
    } on StateError {
      _showNotice('로컬 저장소를 열 수 없습니다.', isError: true);
    } catch (_) {
      _showNotice('운송 건을 연결하지 못했습니다. 다시 시도해 주세요.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showNotice(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _notice = _JoinNotice(message: message, isError: isError);
    });
  }

  @override
  Widget build(BuildContext context) {
    final _JoinNotice? notice = _notice;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '참여 코드로 연결',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '운송자가 발급한 참여 코드로 같은 운송 건을 봅니다. 참여 코드는 역할을 바꾸지 않습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('participation-code-field'),
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '참여 코드',
              hintText: '예: VX-AB12CD',
              filled: true,
              fillColor: const Color(0xFFF7FBFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFDCE8EA)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFDCE8EA)),
              ),
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(
              notice.message,
              key: const Key('join-message'),
              style: TextStyle(
                fontSize: 13,
                color: notice.isError ? AppColors.danger : AppColors.teal,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              key: const Key('join-shipment'),
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                disabledBackgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '운송 건 연결',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
