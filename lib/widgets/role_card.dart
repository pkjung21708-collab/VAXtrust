import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_theme.dart';

/// 첫 화면에서 역할을 고르는 카드입니다.
class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.info,
    required this.onTap,
  });

  final RoleInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: info.title,
      child: Material(
        color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1EAED)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.ice,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(info.icon, color: AppColors.teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      info.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.4,
                        color: AppColors.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
