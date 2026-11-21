import 'package:flutter/material.dart';

import '../data/response_manual.dart';
import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';

/// 대응 절차를 보여 줍니다. 이 화면을 열어도 조치 기록은 생기지 않습니다.
class ResponseManualScreen extends StatelessWidget {
  const ResponseManualScreen({
    super.key,
    required this.manual,
    required this.appliedRangeLabel,
    this.canRecord = false,
    this.onRecord,
  });

  final ResponseManualEntry manual;
  final String appliedRangeLabel;
  final bool canRecord;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const VaxLogo(compact: true, light: true)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            manual.title,
            key: const Key('response-manual-title'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            manual.shortDescription,
            key: const Key('response-manual-summary'),
          ),
          const SizedBox(height: 4),
          Text('적용 온도 범위: $appliedRangeLabel'),
          const SizedBox(height: 8),
          const Text(
            '시연용 가상 데이터와 제공 자료 기반 안내입니다.',
            key: Key('response-manual-demo-note'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('핵심 행동', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (var index = 0; index < manual.immediateActions.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${index + 1}. ${manual.immediateActions[index]}',
                key: Key('response-manual-step-${index + 1}'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Material(
            color: AppColors.card,
            child: ExpansionTile(
              key: const Key('response-manual-details'),
              tilePadding: EdgeInsets.zero,
              title: const Text('상세 대응 절차'),
              children: [
                for (final String line in manual.detailedActions)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(line),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(manual.reportingGuidance),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(manual.documentationGuidance),
                ),
                for (final String line in manual.handlingPrecautions)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(line),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    manual.sourceReference,
                    key: const Key('response-manual-source'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            ResponseManualCatalog.viewDoesNotCompleteAction,
            key: Key('manual-not-completed'),
          ),
          const SizedBox(height: 8),
          const Text(
            ResponseManualCatalog.disclaimer,
            key: Key('response-manual-disclaimer'),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (canRecord && onRecord != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('manual-record-action'),
              onPressed: onRecord,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('조치 기록'),
            ),
          ],
        ],
      ),
    );
  }
}
