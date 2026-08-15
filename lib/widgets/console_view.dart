import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../core/theme.dart';

/// Scrollable, monospace log view with optional timestamps and a jump-to-bottom
/// affordance.
class ConsoleView extends StatefulWidget {
  const ConsoleView({
    super.key,
    required this.log,
    this.showTimestamps = false,
    this.controller,
  });

  final List<SessionLogLine> log;
  final bool showTimestamps;
  final ScrollController? controller;

  @override
  State<ConsoleView> createState() => ConsoleViewState();
}

class ConsoleViewState extends State<ConsoleView> {
  late final ScrollController _controller;
  bool _atBottom = true;
  final bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void didUpdateWidget(ConsoleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.log.length != oldWidget.log.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_stickToBottom) _jumpToBottom();
      });
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final atEnd = _controller.position.extentAfter < 40;
    if (_atBottom != atEnd) setState(() => _atBottom = atEnd);
  }

  void _jumpToBottom() {
    if (_controller.hasClients) {
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: widget.log.isEmpty
                ? Center(
                    child: Text(
                      'Terminal output will appear here.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.all(10),
                    itemCount: widget.log.length,
                    itemBuilder: (context, i) {
                      final entry = widget.log[i];
                      return _LogLine(
                        entry: entry,
                        showTimestamp: widget.showTimestamps,
                      );
                    },
                  ),
          ),
        ),
        SizedBox(
          height: 32,
          child: Row(
            children: [
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Jump to bottom',
                iconSize: 16,
                icon: const Icon(Icons.arrow_downward),
                onPressed: () {
                  setState(() => _atBottom = true);
                  _jumpToBottom();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry, required this.showTimestamp});

  final SessionLogLine entry;
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
        children: [
          if (showTimestamp && entry.timestamp != null)
            TextSpan(
              text: '[${entry.timestamp!.toLocal().toIso8601String()}] ',
              style: const TextStyle(color: LogColors.info, fontSize: 11),
            ),
          TextSpan(text: entry.text),
        ],
      ),
      style: TextStyle(color: _color(entry.level)),
    );
  }

  Color _color(LogLevel level) {
    switch (level) {
      case LogLevel.system:
        return LogColors.system;
      case LogLevel.output:
        return LogColors.output;
      case LogLevel.error:
        return LogColors.error;
      case LogLevel.info:
        return LogColors.info;
    }
  }
}