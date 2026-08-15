import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Interactive HSV color wheel (hue + saturation) with a value (brightness)
/// slider. Reports the chosen color through [onChanged].
class ColorWheel extends StatefulWidget {
  const ColorWheel({
    super.key,
    required this.initial,
    required this.onChanged,
    this.size = 200,
  });

  final Color initial;
  final ValueChanged<Color> onChanged;
  final double size;

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  void _set(HSVColor next) {
    setState(() => _hsv = next);
    widget.onChanged(next.toColor());
  }

  /// Maps a local tap position to hue (from angle) + saturation (from radius).
  void _handle(Offset local, double diameter) {
    final center = Offset(diameter / 2, diameter / 2);
    final radius = diameter / 2;
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy) / radius;

    var hue = (math.atan2(dy, dx) * 180 / math.pi) % 360;
    if (hue < 0) hue += 360;
    final saturation = distance.clamp(0.0, 1.0);
    _set(_hsv.withHue(hue).withSaturation(saturation));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final diameter = constraints.maxWidth;
              return GestureDetector(
                onPanDown: (d) => _handle(d.localPosition, diameter),
                onPanUpdate: (d) => _handle(d.localPosition, diameter),
                child: CustomPaint(
                  painter: _WheelPainter(hsv: _hsv),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _ValueSlider(hsv: _hsv, onChanged: (v) => _set(_hsv.withValue(v))),
      ],
    );
  }
}

/// Brightness slider tinted with the current hue/saturation.
class _ValueSlider extends StatelessWidget {
  const _ValueSlider({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 0);
    return Row(
      children: [
        Icon(Icons.brightness_low, size: 16, color: scheme.onSurfaceVariant),
        Expanded(
          child: Slider(
            value: hsv.value,
            onChanged: onChanged,
            activeColor: hsv.toColor(),
            inactiveColor: dark.toColor(),
          ),
        ),
        Icon(Icons.brightness_high, size: 16, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

/// Draws the hue wheel (sweep gradient) faded to white at the center for the
/// saturation dimension, plus a marker at the current hue/sat position.
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final hueColors = <Color>[
      for (var i = 0; i <= 12; i++)
        HSVColor.fromAHSV(1, i * 30.0, 1, 1).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = SweepGradient(colors: hueColors).createShader(rect),
    );
    // White core -> transparent edge gives the saturation fade.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.12, 1.0],
        ).createShader(rect),
    );

    // Marker at the current hue/saturation.
    final angle = hsv.hue * math.pi / 180;
    final distance = hsv.saturation * radius;
    final position =
        center + Offset(math.cos(angle), math.sin(angle)) * distance;
    canvas.drawCircle(position, 8, Paint()..color = Colors.black26);
    canvas.drawCircle(
      position,
      6,
      Paint()..color = hsv.toColor(),
    );
    canvas.drawCircle(
      position,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.hsv != hsv;
}

/// Hex string like `#0081FB`.
String colorHex(Color color) {
  final value = color.value & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Parses `#RGB` / `#RRGGBB` (case-insensitive, `#` optional). Returns null
/// when the input is not a valid 6-digit (or 3-digit) hex color.
Color? parseHexColor(String input) {
  var text = input.trim();
  if (text.startsWith('#')) text = text.substring(1);
  if (text.startsWith('0x')) text = text.substring(2);
  if (text.length == 3) {
    text = text
        .split('')
        .map((c) => '$c$c')
        .join();
  }
  if (text.length != 6) return null;
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// Modal dialog for picking any accent color.
class AccentColorPickerDialog extends StatefulWidget {
  const AccentColorPickerDialog({super.key, required this.initial});

  final Color initial;

  @override
  State<AccentColorPickerDialog> createState() =>
      _AccentColorPickerDialogState();

  /// Shows the dialog and resolves with the picked color (or null if
  /// cancelled).
  static Future<Color?> show(BuildContext context, Color initial) {
    return showDialog<Color>(
      context: context,
      builder: (_) => AccentColorPickerDialog(initial: initial),
    );
  }
}

class _AccentColorPickerDialogState extends State<AccentColorPickerDialog> {
  late Color _color = widget.initial;
  late final TextEditingController _hex = TextEditingController(
      text: colorHex(widget.initial));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(Color c) {
    setState(() {
      _color = c;
      _hex.text = colorHex(c);
    });
  }

  void _setHex(String text) {
    final parsed = parseHexColor(text);
    if (parsed != null) _setColor(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _color.red / 255;
    final g = _color.green / 255;
    final b = _color.blue / 255;
    return AlertDialog(
      title: const Text('Pick accent color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _color,
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _hex,
                  onChanged: _setHex,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Hex',
                    hintText: '#000000',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 34),
              const SizedBox(width: 10),
              Expanded(
                child: _RgbSlider(
                  label: 'R',
                  value: r,
                  color: Colors.red,
                  onChanged: (v) => _setColor(
                      Color.fromARGB(255, (v * 255).round(), _color.green, _color.blue)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 34),
              const SizedBox(width: 10),
              Expanded(
                child: _RgbSlider(
                  label: 'G',
                  value: g,
                  color: Colors.green,
                  onChanged: (v) => _setColor(
                      Color.fromARGB(255, _color.red, (v * 255).round(), _color.blue)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 34),
              const SizedBox(width: 10),
              Expanded(
                child: _RgbSlider(
                  label: 'B',
                  value: b,
                  color: Colors.blue,
                  onChanged: (v) => _setColor(
                      Color.fromARGB(255, _color.red, _color.green, (v * 255).round())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ColorWheel(
              initial: _color, onChanged: (c) => _setColor(c)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}

/// Single-channel RGB slider with a channel letter label.
class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace')),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
            activeColor: color.withOpacity(0.85),
          ),
        ),
        SizedBox(
          width: 26,
          child: Text('${(value * 255).round()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}
