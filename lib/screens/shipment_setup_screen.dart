import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../models/shipment_record.dart';
import '../models/vaccine_product.dart';
import '../navigation/logout.dart';
import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';
import 'shipment_detail_screen.dart';

class ShipmentSetupScreen extends StatefulWidget {
  const ShipmentSetupScreen({super.key, this.returnToList = false});

  /// 운송 건 목록 위에 열린 경우, 뒤로가기는 로그인 대신 목록으로 돌아갑니다.
  final bool returnToList;

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
  final _minController = TextEditingController(text: '2');
  final _maxController = TextEditingController(text: '8');

  static const String _defaultProductName = '스카이셀플루4가프리필드시린지';

  List<VaccineProduct> _products = const <VaccineProduct>[];
  List<VaccineStorageProfile> _profiles = const <VaccineStorageProfile>[];
  int? _selectedProductId;
  int? _selectedProfileId;
  bool _catalogLoading = true;
  bool _temperatureTouched = false;
  DateTime? _expiryDate;
  bool _leaving = false;
  bool _allowPop = false;
  bool _saving = false;
  String? _saveError;

  VaccineProduct? get _selectedProduct {
    for (final VaccineProduct product in _products) {
      if (product.id == _selectedProductId) {
        return product;
      }
    }
    return null;
  }

  VaccineStorageProfile? get _selectedProfile {
    for (final VaccineStorageProfile profile in _profiles) {
      if (profile.id == _selectedProfileId) {
        return profile;
      }
    }
    return null;
  }

  bool get _rangeDiffers {
    final VaccineStorageProfile? profile = _selectedProfile;
    final double? min = double.tryParse(_minController.text.trim());
    final double? max = double.tryParse(_maxController.text.trim());
    if (profile == null || min == null || max == null) {
      return false;
    }
    return temperatureRangesDiffer(
      recommendedMin: profile.minTemperature,
      recommendedMax: profile.maxTemperature,
      actualMin: min,
      actualMax: max,
    );
  }

  bool get _shipmentDraftIsDirty {
    final String typedManufacturer = _manufacturerController.text.trim();
    final String catalogManufacturer = _selectedProduct?.manufacturer ?? '';
    return _temperatureTouched ||
        _lotController.text.trim().isNotEmpty ||
        _originController.text.trim().isNotEmpty ||
        _destinationController.text.trim().isNotEmpty ||
        _quantityController.text.trim() != '100' ||
        (typedManufacturer.isNotEmpty &&
            typedManufacturer != catalogManufacturer) ||
        (_selectedProduct != null &&
            _selectedProduct!.productName != _defaultProductName) ||
        _expiryDate != null;
  }

  @override
  void initState() {
    super.initState();
    final List<VaccineProduct> cached =
        AppDatabase.instance.loadedVaccineProducts;
    if (cached.isNotEmpty) {
      _installCatalog(cached);
    } else {
      unawaited(_loadCatalog());
    }
  }

  void _installCatalog(List<VaccineProduct> products) {
    final List<VaccineProduct> selectable = products
        .where((VaccineProduct product) => product.isActive)
        .toList();
    if (selectable.isEmpty) {
      _catalogLoading = false;
      _saveError = '등록된 백신이 없습니다.';
      return;
    }
    VaccineProduct selected = selectable.first;
    for (final VaccineProduct product in selectable) {
      if (product.productName == _defaultProductName) {
        selected = product;
        break;
      }
    }
    final List<VaccineStorageProfile> profiles = AppDatabase.instance
        .loadedProfilesFor(selected.id);
    _products = selectable;
    _profiles = profiles;
    _selectedProductId = selected.id;
    _selectedProfileId = profiles.isEmpty ? null : profiles.first.id;
    _catalogLoading = false;
    _applyProfile(
      profiles.isEmpty ? null : profiles.first,
      product: selected,
      resetTemperature: !_temperatureTouched,
    );
  }

  Future<void> _loadCatalog() async {
    try {
      final List<VaccineProduct> products = await AppDatabase.instance
          .vaccineProducts();
      if (!mounted) {
        return;
      }
      if (products.isEmpty) {
        setState(() {
          _catalogLoading = false;
          _saveError = '등록된 백신이 없습니다.';
        });
        return;
      }
      final List<VaccineProduct> selectable = products
          .where((VaccineProduct product) => product.isActive)
          .toList();
      if (selectable.isEmpty) {
        setState(() {
          _catalogLoading = false;
          _saveError = '등록된 백신이 없습니다.';
        });
        return;
      }
      VaccineProduct selected = selectable.first;
      for (final VaccineProduct product in selectable) {
        if (product.productName == _defaultProductName) {
          selected = product;
          break;
        }
      }
      final List<VaccineStorageProfile> profiles = await AppDatabase.instance
          .storageProfilesFor(selected.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _products = selectable;
        _profiles = profiles;
        _selectedProductId = selected.id;
        _selectedProfileId = profiles.isEmpty ? null : profiles.first.id;
        _catalogLoading = false;
        _applyProfile(
          profiles.isEmpty ? null : profiles.first,
          product: selected,
          resetTemperature: !_temperatureTouched,
        );
      });
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogLoading = false;
        _saveError = '로컬 저장소를 열 수 없습니다.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogLoading = false;
        _saveError = '백신 목록을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _selectProduct(int productId) async {
    final List<VaccineStorageProfile> cached = AppDatabase.instance
        .loadedProfilesFor(productId);
    final List<VaccineStorageProfile> profiles = cached.isNotEmpty
        ? cached
        : await AppDatabase.instance.storageProfilesFor(productId);
    if (!mounted) {
      return;
    }
    VaccineProduct? product;
    for (final VaccineProduct item in _products) {
      if (item.id == productId) {
        product = item;
        break;
      }
    }
    setState(() {
      _selectedProductId = productId;
      _profiles = profiles;
      _selectedProfileId = profiles.isEmpty ? null : profiles.first.id;
      _temperatureTouched = false;
      _applyProfile(
        profiles.isEmpty ? null : profiles.first,
        product: product,
        resetTemperature: true,
        forceManufacturer: true,
      );
    });
  }

  void _applyProfile(
    VaccineStorageProfile? profile, {
    required VaccineProduct? product,
    required bool resetTemperature,
    bool forceManufacturer = false,
  }) {
    if (resetTemperature && profile != null) {
      _minController.text = TemperatureBounds.formatNumber(
        profile.minTemperature,
      );
      _maxController.text = TemperatureBounds.formatNumber(
        profile.maxTemperature,
      );
    }
    if (forceManufacturer || _manufacturerController.text.trim().isEmpty) {
      _manufacturerController.text = product?.manufacturer ?? '';
    }
  }

  Future<void> _requestLeave() async {
    if (_leaving || !mounted) {
      return;
    }
    if (widget.returnToList) {
      await _leaveToList();
      return;
    }
    await _leaveToLogin();
  }

  Future<void> _leaveToList() async {
    if (_leaving || !mounted) {
      return;
    }
    _leaving = true;
    var leave = true;
    if (_shipmentDraftIsDirty) {
      leave =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('작성 중인 운송 정보'),
                content: const Text('입력한 운송 정보가 사라집니다. 운송 건 목록으로 돌아갈까요?'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('계속 작성'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('목록으로'),
                  ),
                ],
              );
            },
          ) ??
          false;
    }
    if (!mounted) {
      return;
    }
    if (!leave) {
      _leaving = false;
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _leaveToLogin() async {
    if (_leaving || !mounted) {
      return;
    }
    _leaving = true;
    var leave = true;
    if (_shipmentDraftIsDirty) {
      leave =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('작성 중인 운송 정보'),
                content: const Text('입력한 운송 정보가 사라집니다. 로그인 화면으로 돌아갈까요?'),
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
          ) ??
          false;
    }
    if (!leave) {
      _leaving = false;
      return;
    }
    await endSessionAndShowLogin();
  }

  @override
  void dispose() {
    _manufacturerController.dispose();
    _lotController.dispose();
    _quantityController.dispose();
    _originController.dispose();
    _destinationController.dispose();
    _minController.dispose();
    _maxController.dispose();
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

  String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _setSaveError(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _saveError = message);
    _showSnack(message);
  }

  Future<void> _registerShipment() async {
    if (_saving || !mounted) {
      return;
    }
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_expiryDate == null) {
      _showSnack('백신 유효기간을 선택해 주세요.');
      return;
    }

    final int? quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      _showSnack('수량은 1 이상의 정수로 입력해 주세요.');
      return;
    }

    final VaccineProduct? product = _selectedProduct;
    final VaccineStorageProfile? profile = _selectedProfile;
    if (product == null || profile == null) {
      _showSnack('백신과 보관 단계를 선택해 주세요.');
      return;
    }
    final double? tempMin = double.tryParse(_minController.text.trim());
    final double? tempMax = double.tryParse(_maxController.text.trim());
    if (tempMin == null || tempMax == null || tempMin > tempMax) {
      _showSnack('적용 온도의 하한과 상한을 확인해 주세요.');
      return;
    }
    final TemperatureBounds bounds = TemperatureBounds(
      min: tempMin,
      max: tempMax,
    );

    setState(() {
      _saving = true;
      _saveError = null;
    });

    var navigated = false;
    try {
      final user = await AppDatabase.instance.currentSessionUser();
      if (!mounted) {
        return;
      }
      if (user == null) {
        _setSaveError('로그인 정보가 없습니다. 다시 로그인해 주세요.');
        return;
      }

      final record = await AppDatabase.instance.createShipment(
        ownerUserId: user.id,
        releaseRequired: true,
        draft: NewShipment(
          vaccine: product.productName,
          manufacturer: _manufacturerController.text.trim(),
          lot: _lotController.text.trim(),
          expiryDate: _formatDate(_expiryDate!),
          quantity: quantity,
          origin: _originController.text.trim(),
          destination: _destinationController.text.trim(),
          targetRange: bounds.label,
          tempMin: bounds.min,
          tempMax: bounds.max,
          vaccineProductId: product.id,
          storageProfileId: profile.id,
        ),
      );
      if (!mounted) {
        return;
      }
      navigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              ShipmentDetailScreen(shipmentId: record.id),
        ),
      );
    } on DuplicateShipmentException catch (error) {
      _setSaveError(error.message);
    } on ArgumentError catch (error) {
      final Object? message = error.message;
      _setSaveError(
        message is String && message.trim().isNotEmpty
            ? message
            : '입력값을 확인해 주세요.',
      );
    } on StateError {
      _setSaveError('로컬 저장소를 열 수 없습니다.');
    } catch (_) {
      _setSaveError('운송 건을 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted && !navigated) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        unawaited(_requestLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: widget.returnToList ? '운송 목록으로' : '로그인 화면으로 돌아가기',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              unawaited(Navigator.of(context).maybePop());
            },
          ),
          title: const VaxLogo(compact: true, light: true),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF4F8FA), Color(0xFFEAF4F3)],
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
                    '백신과 배송 정보를 저장합니다. 운송 시작은 등록 후 따로 진행합니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('백신 정보'),
                  const SizedBox(height: 12),
                  if (_catalogLoading)
                    const Text('백신 목록을 불러오는 중')
                  else ...[
                    DropdownButtonFormField<int>(
                      key: const Key('vaccine-product'),
                      initialValue: _selectedProductId,
                      isExpanded: true,
                      decoration: _decoration('백신'),
                      items: _products
                          .map(
                            (VaccineProduct product) => DropdownMenuItem<int>(
                              value: product.id,
                              child: Text(
                                product.choiceLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (int? value) {
                        if (value == null) {
                          return;
                        }
                        unawaited(_selectProduct(value));
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  _textField(
                    controller: _manufacturerController,
                    label: '제조사',
                    hint: '목록에 없으면 직접 입력',
                    fieldKey: const Key('field-manufacturer'),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _lotController,
                    label: 'LOT 번호',
                    hint: '예: LOT-KR-8812',
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.characters,
                    fieldKey: const Key('field-lot'),
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
                                : _formatDate(_expiryDate!),
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
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('배송 정보'),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _originController,
                    label: '출발지',
                    hint: '예: Incheon Vaccine Center',
                    fieldKey: const Key('field-origin'),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _destinationController,
                    label: '도착지',
                    hint: '예: Seoul National University Hospital',
                    fieldKey: const Key('field-destination'),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('보관 조건'),
                  const SizedBox(height: 12),
                  if (!_catalogLoading && _profiles.isNotEmpty)
                    DropdownButtonFormField<int>(
                      key: const Key('storage-profile'),
                      initialValue: _selectedProfileId,
                      isExpanded: true,
                      decoration: _decoration('보관 단계'),
                      items: _profiles
                          .map(
                            (VaccineStorageProfile profile) =>
                                DropdownMenuItem<int>(
                                  value: profile.id,
                                  child: Text(
                                    profile.choiceLabel,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          )
                          .toList(),
                      onChanged: (int? value) {
                        if (value == null) {
                          return;
                        }
                        VaccineStorageProfile? profile;
                        for (final VaccineStorageProfile item in _profiles) {
                          if (item.id == value) {
                            profile = item;
                            break;
                          }
                        }
                        setState(() {
                          _selectedProfileId = value;
                          _temperatureTouched = false;
                          _applyProfile(
                            profile,
                            product: _selectedProduct,
                            resetTemperature: true,
                          );
                        });
                      },
                    ),
                  const SizedBox(height: 14),
                  Text(
                    _selectedProfile == null
                        ? '보관 단계를 선택하면 참고 온도가 입력됩니다.'
                        : '참고 보관 온도 ${_selectedProfile!.rangeLabel}',
                    key: const Key('recommended-temperature'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '자동으로 입력된 범위는 확정값이 아니라 참고값입니다. 적용 조건을 확인한 뒤 등록해 주세요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _minController,
                    label: '적용 최저 온도 (°C)',
                    hint: '예: 2',
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    textCapitalization: TextCapitalization.none,
                    fieldKey: const Key('actual-temp-min'),
                    onChanged: (_) {
                      setState(() => _temperatureTouched = true);
                    },
                  ),
                  const SizedBox(height: 14),
                  _textField(
                    controller: _maxController,
                    label: '적용 최고 온도 (°C)',
                    hint: '예: 8',
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    textCapitalization: TextCapitalization.none,
                    fieldKey: const Key('actual-temp-max'),
                    onChanged: (_) {
                      setState(() => _temperatureTouched = true);
                    },
                  ),
                  if (_rangeDiffers) ...[
                    const SizedBox(height: 8),
                    const Text(
                      temperatureRangeMismatchWarning,
                      key: Key('temperature-range-warning'),
                      style: TextStyle(fontSize: 13, color: AppColors.warning),
                    ),
                  ],
                  if (_selectedProfile?.handlingNotes != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _selectedProfile!.handlingNotes!,
                      key: const Key('handling-notes'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                  if (_selectedProfile?.timeLimitNotes != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _selectedProfile!.timeLimitNotes!,
                      key: const Key('time-limit-notes'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (_selectedProfile?.verificationStatus ==
                      StorageVerificationStatus.verificationRequired) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '이 보관 조건은 추가 확인이 필요합니다. 공식 자료 대조 완료로 표시하지 않습니다.',
                      key: Key('verification-required-note'),
                      style: TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    '등록 후 출고 확인을 하고, 그 다음 운송을 시작합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_saveError != null) ...[
                    Text(
                      _saveError!,
                      key: const Key('shipment-save-error'),
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      key: const Key('register-shipment'),
                      onPressed: _saving ? null : _registerShipment,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(
                        _saving ? '저장 중' : '운송 건 등록',
                        style: const TextStyle(
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
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
    Key? fieldKey,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      autocorrect: false,
      enableSuggestions: true,
      textInputAction: TextInputAction.next,
      validator: _requiredValidator,
      onChanged: onChanged,
      decoration: _decoration(label).copyWith(hintText: hint),
    );
  }
}
