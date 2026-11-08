import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/vax_logo.dart';

class QualityDashboard extends StatelessWidget {
  const QualityDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const VaxLogo(compact: true, light: true),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          DemoBanner(),
          SizedBox(height: 16),
          Text(
            '품질관리자 대시보드',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text('로트별 적합도와 온도 이탈을 검토합니다.'),
          SizedBox(height: 16),
          Row(
            children: [
              MetricCard(
                label: '평균 적합도',
                value: '98%',
                icon: Icons.fact_check_outlined,
              ),
              SizedBox(width: 10),
              MetricCard(
                label: '검토 필요',
                value: '1건',
                icon: Icons.warning_amber_outlined,
                alert: true,
              ),
            ],
          ),
          SizedBox(height: 20),
          SectionTitle(title: '로트 감사', caption: '임시 데이터'),
          SizedBox(height: 10),
          _BatchList(),
        ],
      ),
    );
  }
}

class _BatchList extends StatelessWidget {
  const _BatchList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: kMockBatches
          .map(
            (QualityBatch batch) => Container(
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
                        batch.lot,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                      const Spacer(),
                      StatusChip(label: batch.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    batch.vaccine,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '적합도 ${batch.compliance}%  ·  온도 이탈 ${batch.excursions}건',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
