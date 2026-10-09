import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canvas_state.dart';
import '../models/shape.dart';


const List<String> kFontFamilies = ['Sans', 'Serif', 'Monospace', 'Handwriting'];
const List<double> kFontSizes = [12, 14, 16, 20, 24, 32, 40, 48, 64];
const List<Color> kDefaultTextColors = [
  Color(0xFF1A1A2E),
  Color(0xFFFFFFFF),
  Color(0xFF9CA3AF),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

/// Floating bar shown at the top when one or more text objects are selected.
class TextStyleBar extends StatelessWidget {
  const TextStyleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CanvasState>();
    final selectedText = state.shapes.where(
      (s) => s.type == ShapeType.text && state.selectedShapeIds.contains(s.id),
    );
    if (selectedText.isEmpty) return const SizedBox.shrink();
    final style = selectedText.first.style;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FontDropdown(
                value: kFontFamilies.contains(style.fontFamily) ? style.fontFamily : 'Sans',
                onChanged: (v) => state.updateSelectedTextStyle((s) => s.copyWith(fontFamily: v)),
              ),
              const _Divider(),
              _SizeDropdown(
                value: style.fontSize,
                onChanged: (v) => state.updateSelectedTextStyle((s) => s.copyWith(fontSize: v)),
              ),
              const _Divider(),
              _ColorButton(
                color: style.textColor,
                onPicked: (c) => state.updateSelectedTextStyle((s) => s.copyWith(textColor: c)),
              ),
              const _Divider(),
              _ToggleBtn(
                label: 'B',
                bold: true,
                active: style.bold,
                onTap: () => state.updateSelectedTextStyle((s) => s.copyWith(bold: !s.bold)),
              ),
              _ToggleBtn(
                label: 'I',
                italic: true,
                active: style.italic,
                onTap: () => state.updateSelectedTextStyle((s) => s.copyWith(italic: !s.italic)),
              ),
              _ToggleBtn(
                label: 'U',
                underline: true,
                active: style.underline,
                onTap: () => state.updateSelectedTextStyle((s) => s.copyWith(underline: !s.underline)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _FontDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      items: [
        for (final f in kFontFamilies) DropdownMenuItem(value: f, child: Text(f)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _SizeDropdown extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _SizeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<double>(
      value: kFontSizes.contains(value) ? value : 24,
      underline: const SizedBox.shrink(),
      items: [
        for (final s in kFontSizes)
          DropdownMenuItem(value: s, child: Text(s.toStringAsFixed(0))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Opens a small popover with a colour grid of default solid colours plus a
/// custom picker using RGB sliders.
class _ColorButton extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onPicked;
  const _ColorButton({required this.color, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDialog<Color>(
          context: context,
          builder: (_) => _ColorPickerDialog(initial: color),
        );
        if (picked != null) onPicked(picked);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E4EA)),
          ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _r, _g, _b;

  @override
  void initState() {
    super.initState();
    _r = (widget.initial.r * 255.0).round().clamp(0, 255).toDouble();
    _g = (widget.initial.g * 255.0).round().clamp(0, 255).toDouble();
    _b = (widget.initial.b * 255.0).round().clamp(0, 255).toDouble();
  }

  Color get _current => Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kDefaultTextColors)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, c),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E4EA)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 36, decoration: BoxDecoration(color: _current, borderRadius: BorderRadius.circular(6))),
            _slider('R', _r, Colors.red, (v) => setState(() => _r = v)),
            _slider('G', _g, Colors.green, (v) => setState(() => _g = v)),
            _slider('B', _b, Colors.blue, (v) => setState(() => _b = v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _current), child: const Text('Apply')),
      ],
    );
  }

  Widget _slider(String label, double value, Color c, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: c,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final bool bold;
  final bool italic;
  final bool underline;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.label,
    required this.onTap,
    required this.active,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8EAF6) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: underline ? TextDecoration.underline : TextDecoration.none,
            fontSize: 15,
            color: const Color(0xFF1A1A2E),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFE2E4EA),
    );
  }
}
