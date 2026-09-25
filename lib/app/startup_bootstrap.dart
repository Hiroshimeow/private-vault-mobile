import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';

class StartupStageRunner {
  const StartupStageRunner({this.timeout = const Duration(seconds: 4)});

  final Duration timeout;

  Future<T> run<T>(String stage, Future<T> Function() action) async {
    Timeline.instantSync('startup_stage_begin', arguments: {'stage': stage});
    try {
      return await action().timeout(timeout);
    } finally {
      Timeline.instantSync('startup_stage_end', arguments: {'stage': stage});
    }
  }
}

class StartupBootstrap extends StatefulWidget {
  const StartupBootstrap({
    super.key,
    required this.initialize,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<Widget> Function() initialize;
  final Duration timeout;

  @override
  State<StartupBootstrap> createState() => _StartupBootstrapState();
}

class _StartupBootstrapState extends State<StartupBootstrap> {
  Widget? _ready;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    final attempt = ++_attempt;
    if (mounted) setState(() => _failed = false);
    try {
      final ready = await widget.initialize().timeout(widget.timeout);
      if (!mounted || attempt != _attempt) return;
      setState(() => _ready = ready);
    } on Object {
      if (!mounted || attempt != _attempt) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready != null) return ready;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        key: const Key('startup-locked-shell'),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calculate_outlined, size: 40),
                  const SizedBox(height: 16),
                  const Text('Calculator'),
                  const SizedBox(height: 12),
                  if (_failed) ...[
                    const Text('Startup unavailable'),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('startup-retry'),
                      onPressed: _initialize,
                      child: const Text('Retry'),
                    ),
                  ] else
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
