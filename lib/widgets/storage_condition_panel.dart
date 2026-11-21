import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/shipment_record.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';

/// 등록 당시 보관 조건입니다. 목록이 나중에 바뀌어도 이 화면은 스냅샷을 봅니다.
class StorageConditionPanel extends StatelessWidget {
  const StorageConditionPanel({
    super.key,
    required this.user,
    required this.shipment,
    this.initiallyExpanded = false,
  });

  final AppUser user;
  final ShipmentRecord shipment;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final bool legacy = shipment.isLegacyManualRegistration;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: ExpansionTile(
        key: const Key('storage-condition-panel'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE1EAED)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE1EAED)),
        ),
        title: const Text(
          '보관 조건',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        subtitle: Text(
          legacy
              ? '기존 수동 등록 운송 건'
              : '${shipment.selectedStorageStage ?? '보관 단계 없음'} · ${shipment.temperatureRangeLabel}',
          key: const Key('storage-condition-summary'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        children: [
          if (legacy) ...[
            const Text(
              '기존 수동 등록 운송 건입니다. 백신 목록과 자동으로 연결하지 않았고, 등록 당시 온도 범위를 유지합니다.',
              key: Key('storage-legacy'),
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            _line(
              '적용 온도 범위',
              shipment.temperatureRangeLabel,
              key: const Key('storage-applied-range'),
            ),
          ] else ...[
            _line('백신명', shipment.selectedProductName ?? shipment.vaccine),
            _line(
              '제조사',
              shipment.selectedManufacturer ?? '제조사 미확인',
              key: const Key('storage-manufacturer'),
            ),
            _line(
              '보관 단계',
              shipment.selectedStorageStage ?? '없음',
              key: const Key('storage-stage'),
            ),
            if (user.role == UserRole.qualityManager) ...[
              _line(
                '참고 보관 온도',
                shipment.recommendedRangeLabel ?? '없음',
                key: const Key('storage-recommended-range'),
              ),
              _line(
                '실제 적용 온도',
                shipment.temperatureRangeLabel,
                key: const Key('storage-applied-range'),
              ),
              _line(
                '범위 차이',
                shipment.appliedRangeDiffersFromRecommendation
                    ? '참고 범위와 실제 적용 범위가 다릅니다.'
                    : '참고 범위와 실제 적용 범위가 같습니다.',
                key: const Key('storage-range-difference'),
              ),
              _line(
                '보관 조건 출처',
                shipment.storageProfileReference ?? '출처 없음',
                key: const Key('storage-source'),
              ),
            ] else ...[
              _line(
                '적용 온도 범위',
                shipment.temperatureRangeLabel,
                key: const Key('storage-applied-range'),
              ),
              _line(
                '취급 주의사항',
                shipment.handlingNotesSnapshot ?? '등록된 주의사항이 없습니다.',
                key: const Key('storage-handling'),
              ),
              if (shipment.timeLimitNotesSnapshot != null)
                _line(
                  '시간 관련 참고',
                  shipment.timeLimitNotesSnapshot!,
                  key: const Key('storage-time-limit'),
                ),
            ],
            if (user.role == UserRole.medicalStaff)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '품질관리자 검토 결과는 아래 품질 검토 영역에서 확인할 수 있습니다. 검토 결과는 접종 가능 여부를 정하지 않습니다.',
                  key: Key('storage-review-pointer'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _line(String label, String value, {Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            key: key,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
