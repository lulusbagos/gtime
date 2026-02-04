import 'package:flutter/material.dart';

/// ============================================
/// SHITCORNER PREMIUM - COLOR PALETTE
/// ============================================
///
/// This file documents the complete color system
/// used throughout the Shitcorner Premium app.

// ============================================
// PRIMARY COLORS
// ============================================

/// Professional Blue - Main brand color
/// Used for: Primary buttons, links, icons, borders
/// Hex: #0066FF | RGB: (0, 102, 255)
const Color PRIMARY_BLUE = Color(0xFF0066FF);

/// Premium Orange - Accent color
/// Used for: Secondary actions, highlights, badges
/// Hex: #FF8C42 | RGB: (255, 140, 66)
const Color SECONDARY_ORANGE = Color(0xFFFF8C42);

// ============================================
// NEUTRAL COLORS
// ============================================

/// Light Gray - Backgrounds, dividers
/// Used for: Input backgrounds, disabled states, subtle backgrounds
/// Hex: #F5F5F5 | RGB: (245, 245, 245)
const Color LIGHT_GRAY = Color(0xFFF5F5F5);

/// Dark Gray - Primary text
/// Used for: Headings, body text, main content
/// Hex: #333333 | RGB: (51, 51, 51)
const Color DARK_GRAY = Color(0xFF333333);

/// Text Gray - Secondary text
/// Used for: Subtitles, helper text, secondary info
/// Hex: #666666 | RGB: (102, 102, 102)
const Color TEXT_GRAY = Color(0xFF666666);

// ============================================
// SEMANTIC COLORS
// ============================================

/// Success Color - Green
/// Used for: Success messages, confirmed status
const Color SUCCESS = Color(0xFF4CAF50);

/// Error Color - Red
/// Used for: Error messages, destructive actions
const Color ERROR = Color(0xFFE53935);

/// Warning Color - Amber
/// Used for: Warning messages, caution alerts
const Color WARNING = Color(0xFFFFA726);

/// Info Color - Light Blue
/// Used for: Informational messages
const Color INFO = Color(0xFF29B6F6);

// ============================================
// SURFACE COLORS
// ============================================

/// White - Pure white for cards and surfaces
const Color WHITE = Color(0xFFFFFFFF);

/// Near White - Very light background
const Color NEAR_WHITE = Color(0xFFFAFAFA);

// ============================================
// OPACITY VARIATIONS
// ============================================

extension ColorOpacity on Color {
  /// Get color with reduced opacity for subtle effects
  /// Example: primaryBlue.withSoftOpacity() -> primaryBlue.withOpacity(0.3)
  Color withSoftOpacity() => withOpacity(0.3);

  /// Get color with very soft opacity for backgrounds
  /// Example: primaryBlue.withVeryLight() -> primaryBlue.withOpacity(0.08)
  Color withVeryLight() => withOpacity(0.08);

  /// Get color with disabled opacity
  /// Example: primaryBlue.withDisabled() -> primaryBlue.withOpacity(0.5)
  Color withDisabled() => withOpacity(0.5);
}

// ============================================
// SHADOW DEFINITIONS
// ============================================

/// Subtle shadow for cards and light elements
const List<BoxShadow> SUBTLE_SHADOW = [
  BoxShadow(
    color: Color(0x0F000000),
    blurRadius: 12,
    spreadRadius: 0,
    offset: Offset(0, 4),
  ),
];

/// Medium shadow for elevated elements
const List<BoxShadow> MEDIUM_SHADOW = [
  BoxShadow(
    color: Color(0x14000000),
    blurRadius: 20,
    spreadRadius: 0,
    offset: Offset(0, 8),
  ),
];

/// Focus shadow for interactive elements
const List<BoxShadow> FOCUS_SHADOW = [
  BoxShadow(
    color: Color(0x33007FFF),
    blurRadius: 8,
    spreadRadius: 2,
    offset: Offset(0, 2),
  ),
];

// ============================================
// GRADIENT DEFINITIONS
// ============================================

/// Premium gradient from blue to lighter blue
final LinearGradient PREMIUM_GRADIENT = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [PRIMARY_BLUE.withOpacity(0.1), PRIMARY_BLUE.withOpacity(0.05)],
);

/// Subtle background gradient
final LinearGradient SUBTLE_BACKGROUND_GRADIENT = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [PRIMARY_BLUE.withOpacity(0.08), PRIMARY_BLUE.withOpacity(0.02)],
);

/// Radial gradient for decorative elements
RadialGradient createDecorativeRadialGradient(Color color) {
  return RadialGradient(
    colors: [color.withOpacity(0.15), color.withOpacity(0.0)],
  );
}

// ============================================
// USAGE GUIDELINES
// ============================================

///
/// PRIMARY COLOR USAGE:
/// - Main brand color for primary actions
/// - Navigation highlights
/// - Key UI elements
/// - Links and interactive text
///
/// Example:
///   ElevatedButton(
///     style: ElevatedButton.styleFrom(
///       backgroundColor: PRIMARY_BLUE,
///     ),
///   )
///

///
/// SECONDARY COLOR USAGE:
/// - Call-to-action secondary buttons
/// - Accent highlights
/// - Badge accents
/// - Loading indicators (alternative)
///
/// Example:
///   StatusBadge(
///     backgroundColor: SECONDARY_ORANGE,
///   )
///

///
/// NEUTRAL COLOR USAGE:
/// - Backgrounds and surfaces
/// - Text content
/// - Dividers and borders
/// - Disabled states
///
/// Example:
///   Container(
///     color: LIGHT_GRAY,
///     child: Text(
///       'Hello',
///       style: TextStyle(color: DARK_GRAY),
///     ),
///   )
///

///
/// SEMANTIC COLORS:
/// - Use for status indicators
/// - Error and success states
/// - Warning messages
/// - Info messages
///
/// Example:
///   StatusBadge(
///     label: 'Success',
///     backgroundColor: SUCCESS,
///   )
///

// ============================================
// QUICK REFERENCE CHEAT SHEET
// ============================================

/*

┌─────────────────────────────────────────────────────────┐
│         SHITCORNER PREMIUM - COLOR PALETTE              │
├─────────────────────────────────────────────────────────┤
│ PRIMARY        #0066FF  •●●●●●●●●●●●●  Professional Blue  │
│ SECONDARY      #FF8C42  ●●●●●●●●●●●●●●  Premium Orange     │
│                                                         │
│ LIGHT GRAY     #F5F5F5  ░░░░░░░░░░░░░░  Backgrounds      │
│ DARK GRAY      #333333  ███████████████  Primary Text     │
│ TEXT GRAY      #666666  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  Secondary Text   │
│                                                         │
│ SUCCESS        #4CAF50  ✓ Green                         │
│ ERROR          #E53935  ✗ Red                           │
│ WARNING        #FFA726  ⚠ Amber                         │
│ INFO           #29B6F6  ⓘ Light Blue                    │
└─────────────────────────────────────────────────────────┘

OPACITY SCALE:
├─ Full (100%)      = 1.0  │ Solid colors, main content
├─ Soft (30%)       = 0.3  │ Icons, helper elements
├─ Very Light (8%)  = 0.08 │ Background gradients
├─ Disabled (50%)   = 0.5  │ Disabled states
└─ Hint (40%)       = 0.4  │ Hint text, placeholders

SPACING SYSTEM (multiples of 8px):
├─ xs:  4px  │ Very small gaps
├─ sm:  8px  │ Small gaps
├─ md: 16px  │ Medium spacing
├─ lg: 24px  │ Large spacing
└─ xl: 32px  │ Extra large spacing

BORDER RADIUS:
├─ Small:       12px  │ Buttons, small components
├─ Medium:      16px  │ Cards, containers
└─ Large:       20px  │ Large dialogs, expansive elements

FONT SIZES:
├─ Headline:    22-28px  │ Bold titles
├─ Subtitle:    16-18px  │ Secondary titles
├─ Body:        14px     │ Main content
├─ Caption:     11-13px  │ Small text
└─ Tiny:        10px     │ Helper text

*/
