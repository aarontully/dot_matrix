import 'package:flutter/material.dart';

/// Renders text using a 7xN dot-matrix grid, like a dot-matrix printer.
/// Currently supports: D o t M a t r i x (and space).
class DotMatrixText extends StatelessWidget {
  const DotMatrixText({
    super.key,
    this.text = 'DotMatrix',
    this.dotSize = 2.8,
    this.spacing = 3.6,
    this.letterGap = 2.0,
    this.color,
  });

  final String text;
  final double dotSize;
  final double spacing;
  final double letterGap;
  final Color? color;

  static const Map<String, List<List<int>>> _grids = {
    'D': [
      [1, 1, 1, 1, 0],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 1, 1, 1, 0],
    ],
    'o': [
      [0, 1, 1, 1, 0],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [0, 1, 1, 1, 0],
    ],
    't': [
      [0, 1, 0],
      [1, 1, 1],
      [0, 1, 0],
      [0, 1, 0],
      [0, 1, 0],
      [0, 1, 0],
      [0, 0, 1],
    ],
    'M': [
      [1, 0, 0, 0, 0, 0, 1],
      [1, 1, 0, 0, 0, 1, 1],
      [1, 0, 1, 0, 1, 0, 1],
      [1, 0, 0, 1, 0, 0, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 0, 0, 0, 0, 0, 1],
    ],
    'a': [
      [0, 1, 1, 1, 0],
      [0, 0, 0, 0, 1],
      [0, 1, 1, 1, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [0, 1, 1, 1, 1],
    ],
    'r': [
      [0, 1, 1, 1, 0],
      [0, 1, 0, 0, 1],
      [0, 1, 0, 0, 0],
      [0, 1, 0, 0, 0],
      [0, 1, 0, 0, 0],
      [0, 1, 0, 0, 0],
      [0, 1, 0, 0, 0],
    ],
    'i': [
      [0, 0, 0],
      [0, 1, 0],
      [0, 0, 0],
      [0, 1, 0],
      [0, 1, 0],
      [0, 1, 0],
      [0, 1, 0],
    ],
    'x': [
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
      [0, 1, 0, 1, 0],
      [0, 0, 1, 0, 0],
      [0, 1, 0, 1, 0],
      [1, 0, 0, 0, 1],
      [1, 0, 0, 0, 1],
    ],
  };

  List<List<List<int>>> _letterGrids(String text) {
    final result = <List<List<int>>>[];
    for (final ch in text.split('')) {
      final grid = _grids[ch];
      if (grid != null) result.add(grid);
    }
    return result;
  }

  double _computeWidth(List<List<List<int>>> grids) {
    var cols = 0.0;
    for (var i = 0; i < grids.length; i++) {
      cols += grids[i][0].length * spacing;
      if (i < grids.length - 1) cols += letterGap;
    }
    return cols;
  }

  double _computeHeight() => 7 * spacing;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    final grids = _letterGrids(text);
    final width = _computeWidth(grids);
    final height = _computeHeight();

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _DotMatrixTextPainter(
          grids: grids,
          dotSize: dotSize,
          spacing: spacing,
          letterGap: letterGap,
          color: effectiveColor,
        ),
      ),
    );
  }
}

class _DotMatrixTextPainter extends CustomPainter {
  const _DotMatrixTextPainter({
    required this.grids,
    required this.dotSize,
    required this.spacing,
    required this.letterGap,
    required this.color,
  });

  final List<List<List<int>>> grids;
  final double dotSize;
  final double spacing;
  final double letterGap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    var offsetX = 0.0;

    for (var li = 0; li < grids.length; li++) {
      final grid = grids[li];
      final rows = grid.length;
      final cols = grid[0].length;

      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          if (grid[r][c] == 1) {
            canvas.drawCircle(
              Offset(
                offsetX + c * spacing + spacing / 2,
                r * spacing + spacing / 2,
              ),
              dotSize / 2,
              paint,
            );
          }
        }
      }

      offsetX += cols * spacing + letterGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
