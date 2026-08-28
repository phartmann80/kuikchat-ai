// Isolated probe to verify lucide_icons_flutter 1.33.0 compatibility
// with Flutter 3.47.2 and all 34 required icons.
//
// This file is NOT production code. It is a verification probe only.
// Run with: flutter analyze lucide_probe.dart

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// 34 required icons for KuikChat
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
