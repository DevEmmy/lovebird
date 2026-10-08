import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/colors.dart';
import '../../state/session.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(membershipProvider);
    final circle = ref.watch(circleProvider);
    final error = membership.error ?? circle.error;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LBColors.heroGradient),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const LovebirdMark(size: 72, color: Colors.white),
          const SizedBox(height: 16),
          Text('Lovebird', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
          const SizedBox(height: 28),
          if (error == null)
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(friendlyError(error), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
              onPressed: () {
                ref.invalidate(membershipProvider);
                ref.invalidate(circleProvider);
              },
              child: const Text('Try again'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The Lovebird mark: two birds forming a heart. Drawn, so it's crisp at any size.
class LovebirdMark extends StatelessWidget {
  const LovebirdMark({super.key, this.size = 40, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Lovebird',
        image: true,
        child: CustomPaint(size: Size.square(size), painter: _MarkPainter(color ?? LBColors.rose)),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    // Heart body
    final heart = Path()
      ..moveTo(w * 0.5, h * 0.88)
      ..cubicTo(w * 0.12, h * 0.62, w * 0.02, h * 0.38, w * 0.18, h * 0.22)
      ..cubicTo(w * 0.32, h * 0.08, w * 0.46, h * 0.16, w * 0.5, h * 0.3)
      ..cubicTo(w * 0.54, h * 0.16, w * 0.68, h * 0.08, w * 0.82, h * 0.22)
      ..cubicTo(w * 0.98, h * 0.38, w * 0.88, h * 0.62, w * 0.5, h * 0.88)
      ..close();
    canvas.drawPath(heart, paint);
    // Two little beaks meeting at the top — the "birds"
    final beak = Paint()..color = color.withValues(alpha: 0.85);
    canvas.drawPath(Path()..moveTo(w * 0.24, h * 0.2)..lineTo(w * 0.12, h * 0.14)..lineTo(w * 0.22, h * 0.27)..close(), beak);
    canvas.drawPath(Path()..moveTo(w * 0.76, h * 0.2)..lineTo(w * 0.88, h * 0.14)..lineTo(w * 0.78, h * 0.27)..close(), beak);
    // Eyes
    final eye = Paint()..color = (color.computeLuminance() > 0.6 ? LBColors.rose : Colors.white);
    canvas.drawCircle(Offset(w * 0.3, h * 0.3), w * 0.035, eye);
    canvas.drawCircle(Offset(w * 0.7, h * 0.3), w * 0.035, eye);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
