// Isolated verification probe for lucide_icons_flutter 3.1.17.
//
// This is NOT production code. It exists only to prove, on the pinned
// Flutter 3.47.2 toolchain, that:
//   1. lucide_icons_flutter 3.1.17 resolves exactly.
//   2. Every one of the 34 KuikChat icons is assignable to IconData.
//   3. flutter analyze compiles all 34 symbols.
//
// Run with: flutter analyze lib/icon_probe.dart
// (the CI job performs the full check sequence, including source inspection).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// 34 required icons for KuikChat (matches the production usage).
const requiredIcons = <IconData>[
  LucideIcons.alertCircle,
  LucideIcons.alertTriangle,
  LucideIcons.arrowLeft,
  LucideIcons.atSign,
  LucideIcons.ban,
  LucideIcons.briefcase,
  LucideIcons.building2,
  LucideIcons.check,
  LucideIcons.checkCheck,
  LucideIcons.chevronRight,
  LucideIcons.clock,
  LucideIcons.edit,
  LucideIcons.inbox,
  LucideIcons.info,
  LucideIcons.lock,
  LucideIcons.logOut,
  LucideIcons.mail,
  LucideIcons.messageCircle,
  LucideIcons.messageSquare,
  LucideIcons.messageSquarePlus,
  LucideIcons.messagesSquare,
  LucideIcons.moon,
  LucideIcons.palette,
  LucideIcons.refreshCw,
  LucideIcons.scrollText,
  LucideIcons.send,
  LucideIcons.serverOff,
  LucideIcons.settings,
  LucideIcons.shieldAlert,
  LucideIcons.smartphone,
  LucideIcons.user,
  LucideIcons.userCircle,
  LucideIcons.users,
  LucideIcons.wifiOff,
];

void main() {
  for (final icon in requiredIcons) {
    Icon(icon);
  }
}
