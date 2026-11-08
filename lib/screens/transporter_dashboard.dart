import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/vax_logo.dart';

class TransporterDashboard extends StatelessWidget {
  const TransporterDashboard({
    super.key,
    this.shipmentInfo,
  });

  final Map<String, String>? shipmentInfo;

  @override
  Widget build(BuildContext context) {
    final bool hasUserShipment = shipmentInfo != null;

    final Shipment active = kMockShipments.first;

    final String vaccine = shipmentInfo?['vaccine'] ?? active.vaccine;
    final String lot = shipmentInfo?['lot'] ?? 'LOT 미입력';
    final String manufacturer =
        shipmentInfo?['manufacturer'] ?? '제조사 미입력';
    final String expiryDate =
        shipmentInfo?['expiryDate'] ?? '미입력';
    final String quantity =
        shipmentInfo?['quantity'] ?? '미입력';
    final String origin =
        shipmentInfo?['origin'] ?? '인천창고';
    final String destination =
        shipmentInfo?['destination'] ?? '서울대병원';
    final String targetRange =
        shipmentInfo?['targetRange'] ?? active.targetRange;


    return Scaffold(
      appBar: AppBar(
        title: const VaxLogo(compact: true, light: true),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
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
          const Text('담당 배송 정보와 온도 상태를 확인합니다.'),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: '현재 온도',
                  value: hasUserShipment ? '측정 대기' : '${active.currentTempC}°C',
                  icon: Icons.thermostat,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricCard(
                  label: '진행 배송',
                  value: hasUserShipment ? '1건' : '3건',
                  icon: Icons.route_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          SectionTitle(
            title: hasUserShipment ? '내 배송 정보' : '배송 목록',
            caption: hasUserShipment ? '입력한 정보' : '임시 데이터',
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 10),
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
                    const Icon(
                      Icons.local_shipping_outlined,
                      color: AppColors.teal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasUserShipment ? '내 배송' : active.id,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                    const StatusChip(label: '운송 준비'),
                  ],
                ),

                const Divider(height: 24),

                _InfoRow(label: '백신 종류', value: vaccine),
                _InfoRow(label: '제조사', value: manufacturer),
                _InfoRow(label: 'LOT 번호', value: lot),
                _InfoRow(label: '유효기간', value: expiryDate),
                _InfoRow(label: '수량', value: '$quantity 회분'),
                _InfoRow(label: '출발지', value: origin),
                _InfoRow(label: '도착지', value: destination),
                _InfoRow(label: '목표 보관 온도', value: targetRange),

                const Divider(height: 24),

                const Text(
                  '온도 측정 안내',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasUserShipment
                      ? '현재는 센서가 연결되지 않은 데모입니다. 실제 온도는 아직 측정되지 않았습니다.'
                      : '아래 온도는 임시 데이터이며 실제 센서 측정값이 아닙니다.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          if (!hasUserShipment) ...[
            const SizedBox(height: 10),
            const SectionTitle(
              title: '기존 배송 예시',
              caption: '임시 데이터',
            ),
            const SizedBox(height: 10),
            ...kMockShipments.map(
              (Shipment item) => Container(
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
                        Text(
                          item.id,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.teal,
                          ),
                        ),
                        const Spacer(),
                        StatusChip(label: item.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.vaccine,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(item.route),
                    const SizedBox(height: 8),
                    Text(
                      '온도 ${item.currentTempC}°C · 목표 ${item.targetRange} · ETA ${item.eta}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
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