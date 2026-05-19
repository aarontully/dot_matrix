import 'package:flutter/material.dart';
import 'dart:math' as math;

class DotMatrixLoader extends StatefulWidget {
  final double size;
  final double dotSize;
  final Color? color;
  final double spacing;
  final Duration duration;

  const DotMatrixLoader({
    super.key,
    this.size = 40,
    this.dotSize = 5,
    this.color,
    this.spacing = 3,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<DotMatrixLoader> createState() => _DotMatrixLoaderState();
}

class _DotMatrixLoaderState extends State<DotMatrixLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const int _rows = 5;
  static const int _cols = 5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dotOpacity(int row, int col, double t) {
    final distance = (row + col) / (_rows + _cols - 2);
    final wave = (t * 2 - distance).clamp(0.0, 1.0);
    final fade = math.sin(wave * math.pi);
    return fade.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.color ?? Theme.of(context).colorScheme.primary;
    final totalWidth = _cols * widget.dotSize + (_cols - 1) * widget.spacing;
    final totalHeight = _rows * widget.dotSize + (_rows - 1) * widget.spacing;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: SizedBox(
          width: totalWidth,
          height: totalHeight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int r = 0; r < _rows; r++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int c = 0; c < _cols; c++)
                          Container(
                            width: widget.dotSize,
                            height: widget.dotSize,
                            margin: EdgeInsets.only(
                              right: c < _cols - 1 ? widget.spacing : 0,
                              bottom: r < _rows - 1 ? widget.spacing : 0,
                            ),
                            decoration: BoxDecoration(
                              color: dotColor.withValues(
                                alpha: _dotOpacity(r, c, t),
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
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

class DotMatrixLoadingText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const DotMatrixLoadingText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DotMatrixLoader(
          size: 16,
          dotSize: 2.5,
          color: style?.color ??
              DefaultTextStyle.of(context).style.color,
        ),
        const SizedBox(width: 10),
        Text(text, style: style),
      ],
    );
  }
}
