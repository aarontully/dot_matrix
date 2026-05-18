import 'package:flutter/material.dart';

/// A logo that renders "DM" using a grid of dots, mimicking the look of
/// text printed by a dot-matrix printer.
class DotMatrixLogo extends StatelessWidget {
  const DotMatrixLogo({
    super.key,
    this.size = 42,
    this.dotSize = 3.5,
    this.spacing = 5.5,
    this.color,
  });

  final double size;
  final double dotSize;
  final double spacing;
  final Color? color;

  // Grid definition for "D" (7 rows x 5 cols) and "M" (7 rows x 7 cols)
  // 1 = filled dot, 0 = empty
  static const List<List<int>> _dGrid = [
    [1, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [1, 1, 1, 1, 0],
  ];

  static const List<List<int>> _mGrid = [
    [1, 0, 0, 0, 0, 0, 1],
    [1, 1, 0, 0, 0, 1, 1],
    [1, 0, 1, 0, 1, 0, 1],
    [1, 0, 0, 1, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 1],
  ];

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DotMatrixPainter(
          dGrid: _dGrid,
          mGrid: _mGrid,
          dotSize: dotSize,
          spacing: spacing,
          color: effectiveColor,
        ),
      ),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  const _DotMatrixPainter({
    required this.dGrid,
    required this.mGrid,
    required this.dotSize,
    required this.spacing,
    required this.color,
  });

  final List<List<int>> dGrid;
  final List<List<int>> mGrid;
  final double dotSize;
  final double spacing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dCols = dGrid[0].length;
    final mCols = mGrid[0].length;
    final rows = dGrid.length;

    final gap = spacing * 0.6;
    final totalWidth =
        dCols * spacing + gap + mCols * spacing;
    final totalHeight = rows * spacing;

    final offsetX = (size.width - totalWidth) / 2;
    final offsetY = (size.height - totalHeight) / 2;

    // Draw D
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < dCols; c++) {
        if (dGrid[r][c] == 1) {
          canvas.drawCircle(
            Offset(
              offsetX + c * spacing + spacing / 2,
              offsetY + r * spacing + spacing / 2,
            ),
            dotSize / 2,
            paint,
          );
        }
      }
    }

    // Draw M
    final mOffsetX = offsetX + dCols * spacing + gap;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < mCols; c++) {
        if (mGrid[r][c] == 1) {
          canvas.drawCircle(
            Offset(
              mOffsetX + c * spacing + spacing / 2,
              offsetY + r * spacing + spacing / 2,
            ),
            dotSize / 2,
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
