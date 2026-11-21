import 'package:flutter/material.dart';

import '../models/user_role.dart';
import 'medical_dashboard.dart';
import 'quality_dashboard.dart';
import 'transporter_dashboard.dart';

/// 로그인한 계정의 역할에 맞는 첫 화면으로 이동합니다.
/// 이전 로그인 화면은 스택에서 제거합니다.
void openSignedInHome(BuildContext context, UserRole role) {
  final Widget destination = switch (role) {
    UserRole.transporter => const TransporterDashboard(),
    UserRole.qualityManager => const QualityDashboard(),
    UserRole.medicalStaff => const MedicalDashboard(),
  };

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (BuildContext context) => destination),
    (Route<dynamic> route) => false,
  );
}
