import 'package:flutter/material.dart';

const accentPresets = <(String, int)>[
  ('Meta Blue', 0xFF0081FB),
  ('Terminal Green', 0xFF7CFA6F),
  ('Fire Red', 0xFFEF5350),
  ('Orange', 0xFFFFB300),
  ('Amber', 0xFFFFC23E),
  ('Purple', 0xFFAB47BC),
  ('Pink', 0xFFE91E63),
  ('Teal', 0xFF26A69A),
  ('Indigo', 0xFF5C6BC0),
];

class AccentSwatch extends StatelessWidget {
  const AccentSwatch({
    super.key,
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: Material(
        shape: const CircleBorder(),
        color: color,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 2.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
