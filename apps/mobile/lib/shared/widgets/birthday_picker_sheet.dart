import 'package:bingo/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<DateTime?> showBirthdayPicker(BuildContext context,
    {DateTime? initialDate}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (_) => BirthdayPickerSheet(initialDate: initialDate));
}

class BirthdayPickerSheet extends StatefulWidget {
  const BirthdayPickerSheet({this.initialDate, super.key});
  final DateTime? initialDate;

  @override
  State<BirthdayPickerSheet> createState() => _BirthdayPickerSheetState();
}

class _BirthdayPickerSheetState extends State<BirthdayPickerSheet> {
  final _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _selected;
  late final List<FixedExtentScrollController> _controllers;

  int get _lastMonth => _selected.year == _today.year ? _today.month : 12;
  int get _lastDay =>
      _selected.year == _today.year && _selected.month == _today.month
          ? _today.day
          : DateTime(_selected.year, _selected.month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    final initial = DateUtils.dateOnly(widget.initialDate ?? DateTime(2000));
    _selected = initial.isAfter(_today)
        ? _today
        : initial.isBefore(DateTime(1900))
            ? DateTime(1900)
            : initial;
    _controllers = [
      FixedExtentScrollController(initialItem: _selected.year - 1900),
      FixedExtentScrollController(initialItem: _selected.month - 1),
      FixedExtentScrollController(initialItem: _selected.day - 1),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _change(int column, int index) {
    final year = column == 0 ? 1900 + index : _selected.year;
    final monthLimit = year == _today.year ? _today.month : 12;
    final month =
        (column == 1 ? index + 1 : _selected.month).clamp(1, monthLimit);
    final dayLimit = year == _today.year && month == _today.month
        ? _today.day
        : DateTime(year, month + 1, 0).day;
    final day = (column == 2 ? index + 1 : _selected.day).clamp(1, dayLimit);
    setState(() => _selected = DateTime(year, month, day));
    final indices = [year - 1900, month - 1, day - 1];
    for (var position = 0; position < _controllers.length; position++) {
      if (position != column &&
          _controllers[position].hasClients &&
          _controllers[position].selectedItem != indices[position]) {
        _controllers[position].jumpToItem(indices[position]);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('选择生日',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 22),
            SizedBox(
                height: 156,
                child: Row(children: [
                  for (var column = 0; column < 3; column++) ...[
                    if (column > 0) const SizedBox(width: 9),
                    Expanded(
                        child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                                color: BingoPalette.ice,
                                borderRadius: BorderRadius.circular(14)),
                            child: CupertinoPicker.builder(
                                scrollController: _controllers[column],
                                itemExtent: 44,
                                diameterRatio: 100,
                                squeeze: 1,
                                selectionOverlay: const DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: Color(0x1A67CDAE))),
                                childCount: [
                                  _today.year - 1900 + 1,
                                  _lastMonth,
                                  _lastDay
                                ][column],
                                onSelectedItemChanged: (index) =>
                                    _change(column, index),
                                itemBuilder: (_, index) {
                                  final selected = [
                                        _selected.year - 1900,
                                        _selected.month - 1,
                                        _selected.day - 1
                                      ][column] ==
                                      index;
                                  return Center(
                                      child: Text(
                                          column == 0
                                              ? '${1900 + index}'
                                              : '${index + 1} ${column == 1 ? '月' : '日'}',
                                          style: TextStyle(
                                              fontSize: selected ? 17 : 15,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: selected
                                                  ? BingoPalette.blue
                                                  : const Color(0xFF7D918A))));
                                }))),
                  ]
                ])),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'))),
              const SizedBox(width: 12),
              Expanded(
                  child: FilledButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: const Text('确定'))),
            ]),
          ])));
}
