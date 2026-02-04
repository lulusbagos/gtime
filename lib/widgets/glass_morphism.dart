import 'dart:ui';

import 'package:flutter/material.dart';

/// A glass container with optional gradient border. Designed for a PS5-like modern glass look.
class GlassmorphicContainer extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final double blur;
  final Alignment alignment;
  final double border;
  final Gradient? linearGradient;
  final Gradient? borderGradient;
  final Widget? child;
  final EdgeInsetsGeometry? margin;

  const GlassmorphicContainer({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 12.0,
    this.blur = 6.0,
    this.alignment = Alignment.center,
    this.border = 1.5,
    this.linearGradient,
    this.borderGradient,
    this.child,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    // Outer container paints the border gradient if provided, inner container holds the blurred content.
    return Container(
      width: width,
      height: height,
      margin: margin,
      alignment: alignment,
      decoration: borderGradient != null
          ? BoxDecoration(
              gradient: borderGradient,
              borderRadius: BorderRadius.circular(borderRadius),
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // If border was provided via borderGradient we add padding to show the border.
            Positioned.fill(
              child: Container(
                padding: borderGradient != null
                    ? EdgeInsets.all(border)
                    : EdgeInsets.zero,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient:
                          linearGradient ??
                          LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.06),
                              Colors.white.withOpacity(0.02),
                            ],
                          ),
                      borderRadius: BorderRadius.circular(
                        borderRadius - border,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.02),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                      border: borderGradient == null
                          ? Border.all(
                              color: Colors.white.withOpacity(0.12),
                              width: border,
                            )
                          : null,
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
