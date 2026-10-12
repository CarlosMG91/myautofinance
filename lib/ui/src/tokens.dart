import 'package:flutter/material.dart';

/// Espejo del contrato identidad/tokens-visuales.json, comprobado por pruebas.
abstract final class AfTokens {
  static const canvas = Color(0xfff6f5f1);
  static const surface = Color(0xffffffff);
  static const surfaceSubtle = Color(0xffefeee8);
  static const text = Color(0xff202e32);
  static const muted = Color(0xff526267);
  static const border = Color(0xffd5dddc);
  static const controlBorder = Color(0xff738481);
  static const accent = Color(0xff14645f);
  static const accentHover = Color(0xff104e4a);
  static const accentTint = Color(0xffe5f2ee);
  static const onAccent = Color(0xffffffff);
  static const favorable = Color(0xff21613d);
  static const favorableTint = Color(0xffeaf3eb);
  static const unfavorable = Color(0xff923b32);
  static const unfavorableTint = Color(0xfffbefea);
  static const warning = Color(0xff775015);
  static const warningTint = Color(0xfffff4da);
  static const error = Color(0xff9a3038);
  static const errorTint = Color(0xfffcedef);
  static const focus = Color(0xff284db1);
  static const seriesReal = accent;
  static const seriesBudget = Color(0xff65569c);
  static const seriesAsset = Color(0xff355f91);
  static const seriesDebt = unfavorable;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 48.0;
  static const controlRadius = 8.0;
  static const cardRadius = 16.0;
  static const badgeRadius = 6.0;
  static const compactMax = 599.0;
  static const wideMin = 840.0;
  static const contentMax = 1200.0;
  static const formMax = 560.0;
  static const touchTarget = 48.0;
  static const desktopRowMin = 44.0;
  static const family = 'AfRoboto';
  static const motion = Duration(milliseconds: 120);
  static const reducedMotion = Duration.zero;

  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context)
      ? reducedMotion
      : motion;

  static bool reflow(BuildContext context, double width) =>
      width <= compactMax || MediaQuery.textScalerOf(context).scale(16) >= 24;
}
