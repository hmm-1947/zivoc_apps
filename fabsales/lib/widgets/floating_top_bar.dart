import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canvas_state.dart';
import 'infinite_canvas.dart';

class FloatingTopBar extends StatelessWidget {
  final GlobalKey<InfiniteCanvasState> canvasKey;

  const FloatingTopBar({super.key, required this.canvasKey});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CanvasState>();

    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconBtn(
            icon: Icons.undo_rounded,
            enabled: state.canUndo,
            onTap: state.undo,
          ),
          _IconBtn(
            icon: Icons.redo_rounded,
            enabled: state.canRedo,
            onTap: state.redo,
          ),
          const _Divider(),
          _IconBtn(
            icon: Icons.zoom_out_rounded,
            enabled: true,
            onTap: () => canvasKey.currentState?.zoomBy(0.85),
          ),
          _IconBtn(
            icon: Icons.center_focus_strong_rounded,
            enabled: true,
            onTap: () => canvasKey.currentState?.resetView(),
          ),
          _IconBtn(
            icon: Icons.zoom_in_rounded,
            enabled: true,
            onTap: () => canvasKey.currentState?.zoomBy(1.15),
          ),
          const _Divider(),

          _IconBtn(
            icon: Icons.delete_outline_rounded,
            enabled: state.selectedShapeIds.isNotEmpty,
            onTap: state.deleteSelected,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;
  const _Pill({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: child,
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? const Color(0xFF1A1A2E) : const Color(0xFFC3C6D0),
        ),
      ),
    );
  }
}
