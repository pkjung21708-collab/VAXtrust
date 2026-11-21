import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/app_user.dart';
import '../models/shipment_record.dart';
import '../theme/app_theme.dart';
import '../widgets/vax_logo.dart';

/// 현재 담당 운송자가 다른 운송자에게 인계를 요청하는 화면입니다.
class HandoverRequestScreen extends StatefulWidget {
  const HandoverRequestScreen({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  State<HandoverRequestScreen> createState() => _HandoverRequestScreenState();
}

class _HandoverRequestScreenState extends State<HandoverRequestScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  List<AppUser> _candidates = const <AppUser>[];
  AppUser? _selected;
  DateTime? _scheduledAt;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCandidates());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    try {
      final AppUser? user = await AppDatabase.instance.currentSessionUser();
      if (!mounted) {
        return;
      }
      if (user == null) {
        setState(() {
          _loading = false;
          _error = '로그인 정보가 없습니다.';
        });
        return;
      }
      final List<AppUser> candidates = await AppDatabase.instance
          .searchTransporters(
            excludeUserId: user.id,
            query: _searchController.text,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _candidates = candidates;
        _loading = false;
        if (_selected != null &&
            candidates.every((AppUser item) => item.id != _selected!.id)) {
          _selected = null;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '운송자 목록을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _pickSchedule() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: '인계 예정 날짜',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (date == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now),
      helpText: '인계 예정 시각',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    final AppUser? selected = _selected;
    if (selected == null) {
      setState(() => _error = '인수할 운송자를 선택해 주세요.');
      return;
    }
    if (_locationController.text.trim().isEmpty) {
      setState(() => _error = '인계 장소를 입력해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final AppUser? user = await AppDatabase.instance.currentSessionUser();
      if (user == null) {
        throw const TransferException('로그인 정보가 없습니다.');
      }
      await AppDatabase.instance.requestHandover(
        actorUserId: user.id,
        shipmentId: widget.shipmentId,
        toLoginId: selected.loginId,
        location: _locationController.text,
        scheduledAt: _scheduledAt,
        note: _noteController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on TransferException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '인수인계 요청을 저장하지 못했습니다.';
      });
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
            '인수인계 요청',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${ShipmentRecord.displayIdFor(widget.shipmentId)}의 담당은 '
            '인수자가 수락하기 전까지 바뀌지 않습니다.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('handover-search'),
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '운송자 아이디 검색',
              hintText: '아이디 일부',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => unawaited(_loadCandidates()),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Text('운송자 목록을 불러오는 중')
          else if (_candidates.isEmpty)
            const Text('선택할 수 있는 다른 운송자 계정이 없습니다.')
          else
            ..._candidates.map(_candidateTile),
          const SizedBox(height: 16),
          TextField(
            key: const Key('handover-location'),
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: '인계 장소',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('handover-schedule'),
            onPressed: _pickSchedule,
            icon: const Icon(Icons.schedule),
            label: Text(
              _scheduledAt == null
                  ? '인계 예정 시각 (선택)'
                  : '예정 ${_scheduledAt!.year}-'
                        '${_scheduledAt!.month.toString().padLeft(2, '0')}-'
                        '${_scheduledAt!.day.toString().padLeft(2, '0')} '
                        '${_scheduledAt!.hour.toString().padLeft(2, '0')}:'
                        '${_scheduledAt!.minute.toString().padLeft(2, '0')}',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('handover-note'),
            controller: _noteController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '특이사항 및 메모',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('handover-request-error'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              key: const Key('submit-handover'),
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              child: Text(_saving ? '저장 중' : '인수인계 요청'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _candidateTile(AppUser candidate) {
    final bool selected = _selected?.id == candidate.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFE7F3F3) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('handover-candidate-${candidate.loginId}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selected = candidate),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.teal : const Color(0xFFE1EAED),
              ),
            ),
            child: Text(
              candidate.loginId,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
