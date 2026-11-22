import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/demo_temperature_session.dart';
import '../models/app_user.dart';
import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';
import 'role_home.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _login() async {
    if (_submitting) {
      return;
    }
    FocusScope.of(context).unfocus();

    final String id = _idController.text.trim();
    final String password = _passwordController.text;
    if (id.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = '아이디와 비밀번호를 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final AppUser? user = await AppDatabase.instance.authenticate(
        loginId: id,
        password: password,
      );
      if (!mounted) {
        return;
      }
      if (user == null) {
        setState(() {
          _errorMessage = '아이디 또는 비밀번호를 확인해 주세요.';
        });
        return;
      }
      await AppDatabase.instance.saveSession(user.id);
      if (!mounted) {
        return;
      }
      openSignedInHome(context, user.role);
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
        _errorMessage = '로그인 처리 중 오류가 발생했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _loginAsDemo(String loginId) {
    _idController.text = loginId;
    _passwordController.text = 'demo1234';
    return _login();
  }

  Future<void> _resetWebDemo() async {
    if (!kIsWeb || _submitting) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('이 브라우저의 시연 데이터를 지울까요?'),
          content: const Text(
            '이 브라우저에 저장된 계정, 운송, 온도, 인수인계, 품질 검토 기록이 삭제되고 '
            '시연 계정 세 개가 다시 만들어집니다. '
            '다른 브라우저와 아이폰 앱의 데이터는 바뀌지 않습니다.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              key: const Key('confirm-web-reset'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('초기화'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      DemoTemperatureSession.instance.pauseGeneration();
      await AppDatabase.instance.deleteWebDemoDatabase();
      await AppDatabase.instance.open();
      await AppDatabase.instance.clearSession();
      await AppDatabase.instance.ensureDemoAccounts();
      DemoTemperatureSession.instance.attach();
      await DemoTemperatureSession.instance.restore();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 브라우저의 시연 데이터를 초기화했습니다.')),
      );
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '이 브라우저의 저장소를 초기화할 수 없습니다.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '시연 데이터를 초기화하는 중 오류가 발생했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _openSignup() {
    if (_submitting) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SignupScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: VaxLogo(compact: false, light: false)),
                    const SizedBox(height: 32),
                    const Text(
                      '로그인',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'VAXtrust 콜드체인 관리 시스템',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      '아이디',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _idController,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: '아이디를 입력하세요',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '비밀번호',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        hintText: '비밀번호를 입력하세요',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
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
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _login,
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
                                '로그인',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _submitting ? null : _openSignup,
                      child: const Text(
                        '회원가입',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDCE8EA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '시연용 계정',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('운송자: courier / demo1234'),
                          const SizedBox(height: 4),
                          const Text('품질관리자: quality / demo1234'),
                          const SizedBox(height: 4),
                          const Text('의료진: medical / demo1234'),
                          const SizedBox(height: 8),
                          Text(
                            kIsWeb
                                ? '이 브라우저에만 저장됩니다. 다른 브라우저, 시크릿 창, 아이폰 앱과는 데이터가 공유되지 않습니다.'
                                : '※ 경진대회 시연용 계정입니다. 이 기기에 저장됩니다.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (kIsWeb) ...<Widget>[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              key: const Key('demo-login-courier'),
                              onPressed: _submitting
                                  ? null
                                  : () => _loginAsDemo('courier'),
                              child: const Text('운송자로 입장'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              key: const Key('demo-login-quality'),
                              onPressed: _submitting
                                  ? null
                                  : () => _loginAsDemo('quality'),
                              child: const Text('품질관리자로 입장'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              key: const Key('demo-login-medical'),
                              onPressed: _submitting
                                  ? null
                                  : () => _loginAsDemo('medical'),
                              child: const Text('의료진으로 입장'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              key: const Key('web-demo-reset'),
                              onPressed: _submitting ? null : _resetWebDemo,
                              child: const Text('이 브라우저의 시연 데이터 초기화'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
