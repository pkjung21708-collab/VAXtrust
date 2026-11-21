import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/response_manual.dart';
import '../models/excursion_action.dart';
import '../models/temperature_excursion.dart';
import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';

/// 이탈 한 건의 원인과 조치입니다.
/// 현재 담당 운송자만 새 기록을 추가하고, 이전 기록은 그대로 둡니다.
class ExcursionActionScreen extends StatefulWidget {
  const ExcursionActionScreen({
    super.key,
    this.excursionId,
    this.shipmentId,
    this.initialSituationType,
    required this.canEdit,
  });

  final int? excursionId;
  final int? shipmentId;
  final String? initialSituationType;
  final bool canEdit;

  @override
  State<ExcursionActionScreen> createState() => _ExcursionActionScreenState();
}

class _ExcursionActionScreenState extends State<ExcursionActionScreen> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _action = TextEditingController();
  final TextEditingController _reportedTo = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _category = ExcursionAction.categories.first;
  String _certainty = ExcursionAction.suspected;
  String _situation = ManualScenario.aboveMax;
  bool _responsibleContacted = false;
  bool _holdGuidanceGiven = false;
  bool _holdActionCompleted = false;
  DateTime? _discoveredAt;
  DateTime? _responseStartedAt;
  DateTime? _reportedAt;
  List<ExcursionAction> _history = const <ExcursionAction>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final String? initial = widget.initialSituationType;
    if (initial != null && ExcursionAction.situationTypes.contains(initial)) {
      _situation = initial;
    }
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _action.dispose();
    _reportedTo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = await AppDatabase.instance.currentSessionUser();
      if (user == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '로그인 정보가 없습니다.';
        });
        return;
      }
      final List<ExcursionAction> history;
      if (widget.excursionId != null) {
        history = await AppDatabase.instance.actionsForExcursion(
          userId: user.id,
          excursionId: widget.excursionId!,
        );
      } else {
        history = await AppDatabase.instance.actionsForShipment(
          userId: user.id,
          shipmentId: widget.shipmentId!,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _history = history;
        _loading = false;
        _error = null;
      });
    } on ExcursionException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '원인 기록을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _pickTime(void Function(DateTime? value) assign) async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (day == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) {
      return;
    }
    assign(DateTime(day.year, day.month, day.day, time.hour, time.minute));
    setState(() {});
  }

  Future<void> _save() async {
    final user = await AppDatabase.instance.currentSessionUser();
    if (user == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.excursionId != null) {
        await AppDatabase.instance.saveExcursionAction(
          actorUserId: user.id,
          excursionId: widget.excursionId!,
          causeCategory: _category,
          causeCertainty: _certainty,
          description: _description.text,
          actionTaken: _action.text,
          discoveredAt: _discoveredAt,
          responseStartedAt: _responseStartedAt,
          reportedTo: _reportedTo.text,
          reportedAt: _reportedAt,
          note: _note.text,
          situationType: _situation,
          responsibleContacted: _responsibleContacted,
          holdGuidanceGiven: _holdGuidanceGiven,
          holdActionCompleted: _holdActionCompleted,
        );
      } else {
        await AppDatabase.instance.saveSituationReport(
          actorUserId: user.id,
          shipmentId: widget.shipmentId!,
          situationType: _situation,
          description: _description.text,
          actionTaken: _action.text,
          responsibleContacted: _responsibleContacted,
          holdGuidanceGiven: _holdGuidanceGiven,
          holdActionCompleted: _holdActionCompleted,
          note: _note.text,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ExcursionException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('원인 기록을 저장하지 못했습니다.')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const VaxLogo(compact: true, light: true)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '원인 및 조치 기록',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text('시연 시나리오 이름과 별개로, 운송자가 확인한 내용을 기록합니다.'),
          const SizedBox(height: 16),
          if (_loading)
            const Text('불러오는 중')
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger))
          else ...[
            Text(
              _history.isEmpty ? '원인 기록: 미작성' : '이전 기록 ${_history.length}건',
              key: const Key('excursion-action-history'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._history.map(_historyTile),
            if (widget.canEdit) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('excursion-cause-category'),
                initialValue: _category,
                decoration: const InputDecoration(labelText: '원인 분류'),
                items: [
                  for (final String category in ExcursionAction.categories)
                    DropdownMenuItem<String>(
                      value: category,
                      child: Text(ExcursionAction.labelForCategory(category)),
                    ),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('excursion-cause-certainty'),
                initialValue: _certainty,
                decoration: const InputDecoration(labelText: '확인된 원인 / 추정 원인'),
                items: const [
                  DropdownMenuItem<String>(
                    value: ExcursionAction.confirmed,
                    child: Text('확인된 원인'),
                  ),
                  DropdownMenuItem<String>(
                    value: ExcursionAction.suspected,
                    child: Text('추정 원인'),
                  ),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _certainty = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('excursion-description'),
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '상세 상황 설명'),
              ),
              const SizedBox(height: 8),
              _timeRow(
                '발견 시각',
                _discoveredAt,
                () => _pickTime((DateTime? value) => _discoveredAt = value),
              ),
              _timeRow(
                '대응 시작 시각',
                _responseStartedAt,
                () =>
                    _pickTime((DateTime? value) => _responseStartedAt = value),
              ),
              TextField(
                key: const Key('excursion-action-taken'),
                controller: _action,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '시행한 조치'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reportedTo,
                decoration: const InputDecoration(labelText: '보고 대상'),
              ),
              _timeRow(
                '보고 시각',
                _reportedAt,
                () => _pickTime((DateTime? value) => _reportedAt = value),
              ),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '추가 메모'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('action-situation-type'),
                initialValue: _situation,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '상황 유형'),
                items: [
                  for (final String type in ExcursionAction.situationTypes)
                    DropdownMenuItem<String>(
                      value: type,
                      child: Text(ExcursionAction.labelForSituation(type)),
                    ),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _situation = value);
                  }
                },
              ),
              CheckboxListTile(
                key: const Key('action-responsible-contacted'),
                contentPadding: EdgeInsets.zero,
                value: _responsibleContacted,
                title: const Text('책임자에게 연락함'),
                onChanged: (bool? value) {
                  setState(() => _responsibleContacted = value ?? false);
                },
              ),
              CheckboxListTile(
                key: const Key('action-hold-guidance'),
                contentPadding: EdgeInsets.zero,
                value: _holdGuidanceGiven,
                title: const Text('사용 보류를 안내함'),
                subtitle: const Text('안내는 실제 격리 완료가 아닙니다.'),
                onChanged: (bool? value) {
                  setState(() => _holdGuidanceGiven = value ?? false);
                },
              ),
              CheckboxListTile(
                key: const Key('action-hold-completed'),
                contentPadding: EdgeInsets.zero,
                value: _holdActionCompleted,
                title: const Text('실제 사용 보류 조치를 완료함'),
                subtitle: const Text('직접 수행한 경우에만 선택합니다.'),
                onChanged: (bool? value) {
                  setState(() => _holdActionCompleted = value ?? false);
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('save-excursion-action'),
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('기록 저장'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _timeRow(String label, DateTime? value, VoidCallback onPick) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text('$label: ${formatMeasurementTime(value)}')),
          TextButton(onPressed: onPick, child: const Text('선택')),
        ],
      ),
    );
  }

  Widget _historyTile(ExcursionAction action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        '${formatMeasurementTime(action.createdAt)} · ${action.authorLoginId}\n'
        '${action.situationLabel}\n'
        '${action.categoryLabel} · ${action.certaintyLabel}\n'
        '${action.description}\n시행한 조치: ${action.actionTaken}\n'
        '${action.contactLabel}\n${action.holdLabel}',
        key: Key('excursion-action-row-${action.id}'),
      ),
    );
  }
}
