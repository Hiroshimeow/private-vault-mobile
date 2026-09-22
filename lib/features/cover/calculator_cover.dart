import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/auth/unlock_gate/calculator_unlock_gate.dart';

class CalculatorCover extends StatefulWidget {
  const CalculatorCover({
    super.key,
    this.pinLength = 4,
    this.biometricMode = false,
    this.holdDuration = const Duration(seconds: 2),
    this.onUnlockTriggered,
    this.onUnlockReleased,
  });

  final int pinLength;
  final bool biometricMode;
  final Duration holdDuration;
  final ValueChanged<CalculatorUnlockAttempt>? onUnlockTriggered;
  final ValueChanged<CalculatorUnlockTrigger>? onUnlockReleased;

  @override
  State<CalculatorCover> createState() => _CalculatorCoverState();
}

class _CalculatorCoverState extends State<CalculatorCover>
    with WidgetsBindingObserver {
  String _display = '0';
  double? _left;
  String? _operator;
  bool _replace = true;
  late final CalculatorUnlockGateController _unlockGate;

  @override
  void initState() {
    super.initState();
    _unlockGate = _newUnlockGate();
    WidgetsBinding.instance.addObserver(this);
  }

  CalculatorUnlockGateController _newUnlockGate() =>
      CalculatorUnlockGateController(
        pinLength: widget.pinLength,
        mode: widget.biometricMode
            ? CalculatorUnlockMode.biometric
            : CalculatorUnlockMode.pin,
        holdDuration: widget.holdDuration,
        onTriggered: (attempt) => widget.onUnlockTriggered?.call(attempt),
        onReleased: (trigger) => widget.onUnlockReleased?.call(trigger),
      );

  @override
  void didUpdateWidget(covariant CalculatorCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unlockGate.update(
      pinLength: widget.pinLength,
      mode: widget.biometricMode
          ? CalculatorUnlockMode.biometric
          : CalculatorUnlockMode.pin,
      holdDuration: widget.holdDuration,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      return;
    }
    _unlockGate.cancelHold(notifyRelease: true);
    _unlockGate.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unlockGate.dispose();
    super.dispose();
  }

  void _digit(String digit) {
    setState(() {
      if (_replace || _display == '0') {
        _display = digit;
        _replace = false;
      } else if (_display.length < 14) {
        _display += digit;
      }
    });
    _unlockGate.recordDigit(digit);
  }

  void _resetSecretDigits() => _unlockGate.clear();

  void _operation(String operator) {
    _resetSecretDigits();
    setState(() {
      _applyPending();
      _left = double.tryParse(_display);
      _operator = operator;
      _replace = true;
    });
  }

  void _equals() {
    _resetSecretDigits();
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
    _resetSecretDigits();
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

  _CalculatorKeyRole _roleFor(String label) {
    if (label == 'C') return _CalculatorKeyRole.destructive;
    if (label == '=') return _CalculatorKeyRole.equals;
    if (label.length == 1 && '0123456789'.contains(label)) {
      return _CalculatorKeyRole.number;
    }
    return _CalculatorKeyRole.operator;
  }

  String _semanticLabel(String label) {
    return switch (label) {
      '÷' => 'Divide',
      '×' => 'Multiply',
      '-' => 'Subtract',
      '+' => 'Add',
      '=' => 'Equals',
      'C' => 'Clear',
      _ => label,
    };
  }

  ButtonStyle _buttonStyle(BuildContext context, _CalculatorKeyRole role) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (role) {
      _CalculatorKeyRole.number => (
        colors.surfaceContainerHighest,
        colors.onSurface,
      ),
      _CalculatorKeyRole.operator => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      _CalculatorKeyRole.destructive => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _CalculatorKeyRole.equals => (colors.primary, colors.onPrimary),
    };

    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      padding: EdgeInsets.zero,
      textStyle: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    );
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
      appBar: AppBar(title: const Text('Calculator', key: Key('cover-title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              const displayMinHeight = 44.0;
              const displayGap = 12.0;
              final keyWidth = (constraints.maxWidth - (gap * 3)) / 4;
              final widthDrivenHeight = keyWidth.clamp(48.0, 76.0);
              final heightDrivenHeight =
                  ((constraints.maxHeight -
                              displayMinHeight -
                              displayGap -
                              (gap * 3)) /
                          4)
                      .clamp(48.0, 76.0);
              final keyHeight = widthDrivenHeight < heightDrivenHeight
                  ? widthDrivenHeight
                  : heightDrivenHeight;
              final keypadHeight = (keyHeight * 4) + (gap * 3);

              return Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Semantics(
                        label: 'Calculator display',
                        value: _display,
                        child: SingleChildScrollView(
                          key: const Key('calculator-display-viewport'),
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Text(
                            _display,
                            key: const Key('calculator-display'),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: displayGap),
                  SizedBox(
                    height: keypadHeight,
                    child: Column(
                      children: [
                        for (var row = 0; row < 4; row++) ...[
                          SizedBox(
                            height: keyHeight,
                            child: Row(
                              children: [
                                for (var column = 0; column < 4; column++) ...[
                                  Expanded(
                                    child: Semantics(
                                      label: _semanticLabel(
                                        labels[(row * 4) + column],
                                      ),
                                      button: true,
                                      excludeSemantics: true,
                                      child: Listener(
                                        onPointerDown: (_) =>
                                            _unlockGate.keyDown(
                                              labels[(row * 4) + column],
                                            ),
                                        onPointerUp: (_) => _unlockGate.keyUp(
                                          labels[(row * 4) + column],
                                        ),
                                        onPointerCancel: (_) => _unlockGate
                                            .cancelHold(notifyRelease: true),
                                        child: FilledButton(
                                          key: Key(
                                            <String>[
                                              'calculator-key-',
                                              labels[(row * 4) + column],
                                            ].join(),
                                          ),
                                          style: _buttonStyle(
                                            context,
                                            _roleFor(
                                              labels[(row * 4) + column],
                                            ),
                                          ),
                                          onPressed: () => _press(
                                            labels[(row * 4) + column],
                                          ),
                                          child: Text(
                                            labels[(row * 4) + column],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (column != 3) const SizedBox(width: gap),
                                ],
                              ],
                            ),
                          ),
                          if (row != 3) const SizedBox(height: gap),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _CalculatorKeyRole { number, operator, destructive, equals }
