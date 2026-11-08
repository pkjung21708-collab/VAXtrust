import 'user_role.dart';

/// 로컬 데이터베이스에 저장된 계정입니다.
/// 비밀번호 해시와 소금은 이 객체에 담지 않습니다.
class AppUser {
  const AppUser({
    required this.id,
    required this.loginId,
    required this.role,
    required this.createdAt,
  });

  final int id;
  final String loginId;
  final UserRole role;
  final DateTime createdAt;
}
