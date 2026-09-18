import 'package:flutter/material.dart';

class CalculatorCover extends StatefulWidget {
  const CalculatorCover({super.key, required this.onUnlockRequested});

  final VoidCallback onUnlockRequested;

  @override
  State<CalculatorCover> createState() => _CalculatorCoverState();
}

class _CalculatorCoverState extends State<CalculatorCover> {
  String _display = '0';
  double? _left;
  String? _operator;
  bool _replace = true;

  void _digit(String digit) {
    setState(() {
      if (_replace || _display == '0') {
        _display = digit;
        _replace = false;
      } else if (_display.length < 14) {
        _display += digit;
      }
    });
  }

  void _operation(String operator) {
    setState(() {
      _applyPending();
      _left = double.tryParse(_display);
      _operator = operator;
      _replace = true;
    });
  }

  void _equals() {
    setState(() {
      _applyPending();
      _operator = null;
      _left = null;
      _replace = true;
    });
  }

  void _applyPending() {
    if (_left == null || _operator == null) return;
    final right = double.tryParse(_display);
    if (right == null) return;

    final result = switch (_operator) {
      '+' => _left! + right,
      '-' => _left! - right,
      '×' => _left! * right,
      '÷' => right == 0 ? double.nan : _left! / right,
      _ => right,
    };
    _display = _format(result);
  }

  String _format(double value) {
    if (value.isNaN || value.isInfinite) return 'Error';
    if (value == value.roundToDouble()) return value.toInt().toString();
    final text = value.toStringAsFixed(8);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _clear() {
    setState(() {
      _display = '0';
      _left = null;
      _operator = null;
      _replace = true;
    });
  }

  void _press(String label) {
    if (RegExp(r'^\d$').hasMatch(label)) {
      _digit(label);
    } else if (label == 'C') {
      _clear();
    } else if (label == '=') {
      _equals();
    } else {
      _operation(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = <String>[
      '7',
      '8',
      '9',
      '÷',
      '4',
      '5',
      '6',
      '×',
      '1',
      '2',
      '3',
      '-',
      'C',
      '0',
      '=',
      '+',
    ];

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          key: const Key('cover-title'),
          onLongPress: widget.onUnlockRequested,
          child: const Text('Calculator'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Semantics(
                    label: 'Calculator display',
                    child: Text(
                      _display,
                      key: const Key('calculator-display'),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    for (var row = 0; row < 4; row++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: row == 3 ? 0 : 10),
                          child: Row(
                            children: [
                              for (var column = 0; column < 4; column++)
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: column == 3 ? 0 : 10,
                                    ),
                                    child: FilledButton(
                                      onPressed: () =>
                                          _press(labels[(row * 4) + column]),
                                      child: Text(labels[(row * 4) + column]),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
