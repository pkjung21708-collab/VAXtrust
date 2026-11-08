import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/vax_logo.dart';

class MedicalDashboard extends StatelessWidget {
  const MedicalDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final int readyCount =
        kMockInventory.where((MedicalInventory item) => item.ready).length;

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
            '의료진 대시보드',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text('입고 백신의 보관 온도와 투여 가능 여부를 확인합니다.'),
          const SizedBox(height: 16),
          Row(
            children: [
              MetricCard(
                label: '투여 가능 로트',
                value: '$readyCount건',
                icon: Icons.vaccines_outlined,
              ),
              const SizedBox(width: 10),
              const MetricCard(
                label: '보관 이상',
                value: '1건',
                icon: Icons.severe_cold_outlined,
                alert: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionTitle(title: '원내 재고', caption: '임시 데이터'),
          const SizedBox(height: 10),
          ...kMockInventory.map(
            (MedicalInventory item) => Container(
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
                        item.lot,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                      const Spacer(),
                      StatusChip(label: item.ready ? '적합' : '주의'),
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
                  const SizedBox(height: 6),
                  Text(
                    '${item.doses}도즈  ·  보관 ${item.storageTempC}°C  ·  '
                    '${item.ready ? '투여 가능' : '보관 온도 확인 필요'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
