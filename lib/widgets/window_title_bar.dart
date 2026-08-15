import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Custom title bar (used with `TitleBarStyle.hidden` + `VirtualWindowFrame`).
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key, required this.title, this.leading});

  final String title;

  /// Optional action rendered at the far left (e.g. a back button).
  final Widget? leading;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar>
    with WindowListener {
  bool _maximized = false;
  _WindowButton? _hoveredTarget;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && _maximized != maximized) {
      setState(() => _maximized = maximized);
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  IconData get _windowButtonIcon =>
      _maximized ? Icons.filter_none : Icons.crop_square_rounded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 12),
          Icon(Icons.bug_report_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ),
          _windowButton(
            key: const Key('title-min'),
            icon: Icons.remove,
            tooltip: 'Minimize',
            onTap: () => windowManager.minimize(),
            onEnter: _setHovered,
            onExit: _clearHovered,
          ),
          _windowButton(
            key: const Key('title-max'),
            icon: _windowButtonIcon,
            tooltip: _maximized ? 'Restore' : 'Maximize',
            onTap: () {
              if (_maximized) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
            onEnter: _setHovered,
            onExit: _clearHovered,
          ),
          _windowButton(
            key: const Key('title-close'),
            icon: Icons.close,
            tooltip: 'Close',
            hoverColor: Theme.of(context).colorScheme.error,
            hoverIconColor: Theme.of(context).colorScheme.onError,
            onTap: () => windowManager.close(),
            onEnter: _setHovered,
            onExit: _clearHovered,
          ),
        ],
      ),
    );
  }

  // Drag-to-move region: the whole bar except the buttons.
  Widget _windowButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? hoverColor,
    Color? hoverIconColor,
    required ValueChanged<_WindowButton> onEnter,
    required VoidCallback onExit,
  }) {
    return MouseRegion(
      key: key,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter(_WindowButton(icon: icon)),
      onExit: (_) => onExit(),
      child: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 40,
              height: 32,
              alignment: Alignment.center,
              color: _hoveredTarget?.icon == icon && hoverColor != null
                  ? hoverColor
                  : (_hoveredTarget?.icon == icon
                      ? scheme.onSurface.withOpacity(0.08)
                      : Colors.transparent),
              child: Icon(
                icon,
                size: 16,
                color: _hoveredTarget?.icon == icon && hoverIconColor != null
                    ? hoverIconColor
                    : scheme.onSurface,
              ),
            ),
          ),
        );
      }),
    );
  }

  void _setHovered(_WindowButton button) =>
      setState(() => _hoveredTarget = button);

  void _clearHovered() => setState(() => _hoveredTarget = null);
}

/// Which button is currently hovered (for highlight coloring).
class _WindowButton {
  const _WindowButton({required this.icon});
  final IconData icon;
}

/// Wraps the title bar with the window_manager drag-to-move region.
class DraggableTitleBar extends StatelessWidget {
  const DraggableTitleBar({super.key, required this.title, this.leading});

  final String title;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: WindowTitleBar(title: title, leading: leading),
    );
  }
}