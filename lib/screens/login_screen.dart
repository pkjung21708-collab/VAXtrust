import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';
import 'medical_dashboard.dart';
import 'quality_dashboard.dart';
import 'shipment_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController =
      TextEditingController();

  bool _obscurePassword = true;
  String? _errorMessage;

  final Map<String, Map<String, String>> _demoAccounts = {
    'courier': {
      'password': 'demo1234',
      'role': 'transporter',
    },
    'quality': {
      'password': 'demo1234',
      'role': 'qualityManager',
    },
    'medical': {
      'password': 'demo1234',
      'role': 'medicalStaff',
    },
  };

    void _login() {
    final String id = _idController.text.trim();
    final String password = _passwordController.text;

    final Map<String, String>? account = _demoAccounts[id];

    if (account == null || account['password'] != password) {
      setState(() {
        _errorMessage = '아이디 또는 비밀번호를 확인해 주세요.';
      });
      return;
    }

    final String role = account['role']!;

    late final Widget destination;

    switch (role) {
      case 'transporter':
        destination = const ShipmentSetupScreen();
        break;
      case 'qualityManager':
        destination = const QualityDashboard();
        break;
      case 'medicalStaff':
        destination = const MedicalDashboard();
        break;
      default:
        setState(() {
          _errorMessage = '등록되지 않은 사용자 유형입니다.';
        });
        return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => destination,
      ),
      (route) => false
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
            colors: [
              Color(0xFFF3F8FA),
              Color(0xFFE7F3F3),
            ],
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
                    const Center(
                      child: VaxLogo(
                        compact: false,
                        light: false,
                      ),
                    ),
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
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '로그인',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFDCE8EA),
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '시연용 계정',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text('운송자: courier / demo1234'),
                          SizedBox(height: 4),
                          Text('품질관리자: quality / demo1234'),
                          SizedBox(height: 4),
                          Text('의료진: medical / demo1234'),
                          SizedBox(height: 8),
                          Text(
                            '※ 경진대회 시연용 계정입니다.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
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