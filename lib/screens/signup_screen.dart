import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import '../widgets/role_card.dart';
import '../widgets/vax_logo.dart';
import 'role_home.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  UserRole? _role;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  bool _leaving = false;
  String? _errorMessage;

  bool get _isDirty {
    return _idController.text.isNotEmpty ||
        _passwordController.text.isNotEmpty ||
        _confirmController.text.isNotEmpty ||
        _role != null;
  }

  @override
  void initState() {
    super.initState();
    _idController.addListener(_handleDraftChanged);
    _passwordController.addListener(_handleDraftChanged);
    _confirmController.addListener(_handleDraftChanged);
  }

  void _handleDraftChanged() {
    setState(() {});
  }

  Future<void> _confirmDiscard() async {
    if (_leaving || !mounted) {
      return;
    }
    _leaving = true;
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('작성 중인 가입 정보'),
          content: const Text('입력한 내용이 사라집니다. 로그인 화면으로 돌아갈까요?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('계속 작성'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('로그인 화면으로'),
            ),
          ],
        );
      },
    );
    _leaving = false;
    if (leave == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _signup() async {
    if (_submitting) {
      return;
    }
    FocusScope.of(context).unfocus();

    final String id = _idController.text.trim();
    final String password = _passwordController.text;
    final String confirm = _confirmController.text;

    String? error;
    if (id.isEmpty) {
      error = '아이디를 입력해 주세요.';
    } else if (password.isEmpty) {
      error = '비밀번호를 입력해 주세요.';
    } else if (password != confirm) {
      error = '비밀번호가 서로 다릅니다.';
    } else if (_role == null) {
      error = '역할을 선택해 주세요.';
    }

    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final AppUser user = await AppDatabase.instance.createUser(
        loginId: id,
        password: password,
        role: _role!,
      );
      await AppDatabase.instance.saveSession(user.id);
      if (!mounted) {
        return;
      }
      openSignedInHome(context, user.role);
    } on DuplicateLoginIdException {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '이미 사용 중인 아이디입니다.';
      });
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '로컬 저장소를 열 수 없습니다.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '회원가입 처리 중 오류가 발생했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _idController.removeListener(_handleDraftChanged);
    _passwordController.removeListener(_handleDraftChanged);
    _confirmController.removeListener(_handleDraftChanged);
    _idController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        unawaited(_confirmDiscard());
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF3F8FA), Color(0xFFE7F3F3)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: '뒤로가기',
                          onPressed: () {
                            unawaited(Navigator.of(context).maybePop());
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                      const Center(
                        child: VaxLogo(compact: false, light: false),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '회원가입',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '역할별 계정을 이 기기에 저장합니다. 서버로 보내지 않습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _label('아이디'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _idController,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: _decoration(
                          hint: '아이디를 입력하세요',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('비밀번호'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          hint: '비밀번호를 입력하세요',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('비밀번호 확인'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _signup(),
                        decoration: _decoration(
                          hint: '비밀번호를 다시 입력하세요',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirm = !_obscureConfirm;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _label('역할'),
                      const SizedBox(height: 8),
                      const Text(
                        '가입한 역할은 이 계정에 고정됩니다. 다른 역할은 따로 가입합니다.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final RoleInfo info in kRoleInfos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RoleCard(
                            key: ValueKey<String>('signup-${info.role.name}'),
                            info: info,
                            selected: _role == info.role,
                            onTap: () {
                              if (_submitting) {
                                return;
                              }
                              setState(() {
                                _role = info.role;
                                _errorMessage = null;
                              });
                            },
                          ),
                        ),
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            disabledBackgroundColor: AppColors.teal,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '가입하기',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
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
        ),
      ),
    );
  }
}
