import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// A drag-and-drop target plus a "Browse…" button. Restricts files to
/// [allowedExtensions] when non-empty.
class FileDropZone extends StatefulWidget {
  const FileDropZone({
    super.key,
    required this.label,
    required this.placeholder,
    this.allowedExtensions,
    this.value,
    this.onPicked,
    this.icon = Icons.upload_file,
    this.compact = false,
  });

  final String label;
  final String placeholder;

  /// e.g. `['js']`, `['ts', 'js']`, or null for any file.
  final List<String>? allowedExtensions;
  final String? value;
  final ValueChanged<String>? onPicked;
  final IconData icon;
  final bool compact;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _hovering = false;

  String _basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.last;
  }

  String get _display => widget.value != null && widget.value!.isNotEmpty
      ? _basename(widget.value!)
      : widget.placeholder;

  bool _accepts(String path) {
    if (widget.allowedExtensions == null) return true;
    final name = _basename(path).toLowerCase();
    return widget.allowedExtensions!.any((e) => name.endsWith('.$e'));
  }

  void _handleDrop(List<DropItem> items) {
    if (items.isEmpty) return;
    final path = items.first.path;
    if (path.isEmpty || !_accepts(path)) return;
    widget.onPicked?.call(path);
  }

  Future<void> _browse() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.allowedExtensions ?? const <String>[],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;
    if (!_accepts(path)) return;
    widget.onPicked?.call(path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _hovering ? scheme.primary : scheme.outline;
    final selected = widget.value != null && widget.value!.isNotEmpty;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: widget.compact ? 20 : 28, color: accent),
        if (!widget.compact) const SizedBox(height: 8),
        Text(
          _display,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          style: TextStyle(
            fontSize: widget.compact ? 12 : 13,
            color: selected ? scheme.onSurface : scheme.outline,
            fontFamily: 'monospace',
          ),
        ),
        if (widget.value != null && widget.value!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.value!,
              style: TextStyle(fontSize: 10, color: scheme.outline),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        if (!widget.compact) const SizedBox(height: 8),
        if (!widget.compact)
          OutlinedButton.icon(
            onPressed: _browse,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(widget.value != null && widget.value!.isNotEmpty
                ? 'Replace'
                : 'Browse…'),
          ),
      ],
    );

    final zone = DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) => _handleDrop(details.files),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        constraints:
            BoxConstraints(minHeight: widget.compact ? 44 : 96),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _hovering
              ? scheme.primary.withOpacity(0.08)
              : scheme.surfaceContainerHighest.withOpacity(0.3),
          border: Border.all(
            color: accent,
            width: _hovering ? 1.6 : 1,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      ),
    );

    if (widget.compact) {
      return Row(
        children: [
          Expanded(child: zone),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Browse',
            icon: const Icon(Icons.folder_open),
            onPressed: _browse,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        const SizedBox(height: 4),
        zone,
      ],
    );
  }
}