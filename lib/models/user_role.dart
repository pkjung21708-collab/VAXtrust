import 'package:flutter/material.dart';

/// 앱에서 고를 수 있는 사용자 역할입니다.
/// enum은 "정해진 몇 가지 값만 허용"할 때 씁니다.
enum UserRole {
  transporter,
  qualityManager,
  medicalStaff;

  /// SQLite에 넣는 역할 이름입니다. 로그인 화면의 역할 문자열과 같습니다.
  static UserRole fromStorage(String value) {
    for (final UserRole role in UserRole.values) {
      if (role.name == value) {
        return role;
      }
    }
    throw FormatException('저장할 수 없는 사용자 역할입니다: $value');
  }
}

/// 역할마다 화면에 보여줄 이름, 설명, 아이콘을 묶어 둡니다.
class RoleInfo {
  const RoleInfo({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
  });

  final UserRole role;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
}

const List<RoleInfo> kRoleInfos = [
  RoleInfo(
    role: UserRole.transporter,
    title: '운송자',
    subtitle: 'Cold Chain Courier',
    description: '백신 배송 경로, 실시간 온도, 도착 예정 시간을 확인합니다.',
    icon: Icons.local_shipping_outlined,
  ),
  RoleInfo(
    role: UserRole.qualityManager,
    title: '품질관리자',
    subtitle: 'Quality Assurance',
    description: '로트 적합 여부, 온도 이탈, 감사 로그를 검토합니다.',
    icon: Icons.verified_outlined,
  ),
  RoleInfo(
    role: UserRole.medicalStaff,
    title: '의료진',
    subtitle: 'Clinical Staff',
    description: '입고 백신, 보관 상태, 투여 가능 여부를 확인합니다.',
    icon: Icons.medical_services_outlined,
  ),
];
