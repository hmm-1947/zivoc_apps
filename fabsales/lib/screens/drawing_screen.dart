import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/canvas_state.dart';
import '../widgets/floating_toolbar.dart';
import '../widgets/floating_top_bar.dart';
import '../widgets/infinite_canvas.dart';
import '../widgets/selection_actions.dart';
import '../widgets/text_style_bar.dart';

class DrawingScreen extends StatelessWidget {
  const DrawingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CanvasState(),
      child: const _DrawingBody(),
    );
  }
}

class _DrawingBody extends StatefulWidget {
  const _DrawingBody();

  @override
  State<_DrawingBody> createState() => _DrawingBodyState();
}

class _DrawingBodyState extends State<_DrawingBody> {
  final GlobalKey<InfiniteCanvasState> _canvasKey = GlobalKey<InfiniteCanvasState>();

  Listenable? _canvasListenable;

  @override
  void dispose() {
    _canvasListenable?.removeListener(_onCanvasTransformChanged);
    super.dispose();
  }

  void _onCanvasTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: InfiniteCanvas(
              key: _canvasKey,
              onControllerReady: (listenable) {
                _canvasListenable = listenable;
                listenable.addListener(_onCanvasTransformChanged);
              },
            ),
          ),
          SelectionActions(canvasKey: _canvasKey),
          Positioned(
            top: 64,
            left: 0,
            right: 0,
            child: Center(
              child: SafeArea(
                child: FloatingTopBar(canvasKey: _canvasKey),
              ),
            ),
          ),
          Positioned(
            top: 120,
            left: 0,
            right: 0,
            child: Center(
              child: SafeArea(
                child: TextStyleBar(),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: SafeArea(
                top: false,
                child: FloatingToolbar(canvasKey: _canvasKey),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  elevation: 6,
                  shape: const CircleBorder(),
                  color: Colors.white,
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1A2E)),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
