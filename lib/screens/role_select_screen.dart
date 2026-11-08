import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_theme.dart';
import '../widgets/role_card.dart';
import '../widgets/vax_logo.dart';
import 'medical_dashboard.dart';
import 'quality_dashboard.dart';
import 'transporter_dashboard.dart';

/// 앱을 켜면 가장 먼저 보이는 화면입니다.
/// 로고, 서비스 소개, 역할 선택 카드를 보여 줍니다.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  void _openDashboard(BuildContext context, UserRole role) {
    // Navigator.push는 새 화면을 위에 쌓는 이동 방식입니다.
    final Widget screen = switch (role) {
      UserRole.transporter => const TransporterDashboard(),
      UserRole.qualityManager => const QualityDashboard(),
      UserRole.medicalStaff => const MedicalDashboard(),
    };

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.navy, Color(0xFF0A4A52), AppColors.teal],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VaxLogo(light: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      '백신 콜드체인을\n끝까지 신뢰할 수 있게',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '운송·품질·투여까지 온도 이력을 한곳에서 추적하는 '
                      '의료 바이오 콜드체인 관리 서비스입니다.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 14.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.ice,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      const Text(
                        '역할을 선택하세요',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '선택한 역할의 대시보드로 바로 이동합니다. 로그인 서버는 아직 연결하지 않습니다.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...kRoleInfos.map(
                        (RoleInfo info) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RoleCard(
                            key: ValueKey<String>(info.role.name),
                            info: info,
                            onTap: () => _openDashboard(context, info.role),
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
