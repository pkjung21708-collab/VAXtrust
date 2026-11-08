import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';
import 'transporter_dashboard.dart';

class ShipmentSetupScreen extends StatefulWidget {
  const ShipmentSetupScreen({super.key});

  @override
  State<ShipmentSetupScreen> createState() => _ShipmentSetupScreenState();
}

class _ShipmentSetupScreenState extends State<ShipmentSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _manufacturerController = TextEditingController();
  final _lotController = TextEditingController();
  final _quantityController = TextEditingController(text: '100');
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();

  String _selectedVaccine = '인플루엔자 4가';
  String _targetRange = '2 ~ 8°C';
  DateTime? _expiryDate;

  final Map<String, String> _vaccineRanges = {
    '인플루엔자 4가': '2 ~ 8°C',
    'MMR': '2 ~ 8°C',
    'B형간염': '2 ~ 8°C',
    'HPV 9가': '2 ~ 8°C',
    'mRNA COVID-19 (초저온 보관 예시)': '-80 ~ -60°C',
  };

  @override
  void dispose() {
    _manufacturerController.dispose();
    _lotController.dispose();
    _quantityController.dispose();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '필수 입력 항목입니다.';
    }
    return null;
  }

  Future<void> _selectExpiryDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 15),
      helpText: '백신 유효기간 선택',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (picked != null && mounted) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  void _startTransport() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('백신 유효기간을 선택해 주세요.')),
      );
      return;
    }

    final quantity = int.tryParse(_quantityController.text.trim());

    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수량은 1 이상의 정수로 입력해 주세요.')),
      );
      return;
    }

    final shipmentInfo = <String, String>{
      'vaccine': _selectedVaccine,
      'manufacturer': _manufacturerController.text.trim(),
      'lot': _lotController.text.trim(),
      'expiryDate':
          '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}',
      'quantity': quantity.toString(),
      'origin': _originController.text.trim(),
      'destination': _destinationController.text.trim(),
      'targetRange': _targetRange,
    };

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => TransporterDashboard(
          shipmentInfo: shipmentInfo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '로그인 화면으로 돌아가기',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).maybePop();
            },
          ),
          title: const VaxLogo(compact: true, light: true),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF4F8FA),
                Color(0xFFEAF4F3),
              ],
            ),
          ),
          child: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '새 배송 등록',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '운송을 시작하기 전에 백신과 배송 정보를 입력해 주세요.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('백신 정보'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedVaccine,
                    decoration: _decoration('백신 종류'),
                    items: _vaccineRanges.keys
                        .map(
                          (vaccine) => DropdownMenuItem(
                            value: vaccine,
                            child: Text(
                              vaccine,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedVaccine = value;
                        _targetRange = _vaccineRanges[value]!;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _manufacturerController,
                    label: '제조사',
                    hint: '예: Korea Vaccine',
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _lotController,
                    label: 'LOT 번호',
                    hint: '예: LOT-KR-8812',
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _selectExpiryDate,
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: _decoration('유효기간'),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            color: AppColors.teal,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _expiryDate == null
                                ? '날짜 선택'
                                : '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: _expiryDate == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _quantityController,
                    label: '수량 (dose)',
                    hint: '예: 100',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('배송 정보'),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _originController,
                    label: '출발지',
                    hint: '예: Incheon Vaccine Center',
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _destinationController,
                    label: '도착지',
                    hint: '예: Seoul National University Hospital',
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('보관 조건'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFDCE8EA),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.thermostat_outlined,
                          color: AppColors.teal,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '목표 보관 온도',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          _targetRange,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '현재 온도 범위는 시연용 예시입니다. 실제 운송 전에는 제품별 허가사항과 제조사 보관 지침을 확인해야 합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _startTransport,
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text(
                        '운송 시작',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE8EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE8EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.teal,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      autocorrect: false,
      enableSuggestions: true,
      textInputAction: TextInputAction.next,
      validator: _requiredValidator,
      decoration: _decoration(label).copyWith(
        hintText: hint,
      ),
    );
  }
}