import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two isolated environments inside the one KuikChat app.
///
/// Switching scope swaps the entire navigation model. Personal and Business
/// never share repositories, clients, or backend projects.
enum PlatformScope { personal, business }

final platformScopeProvider = StateProvider<PlatformScope>((ref) => PlatformScope.personal);
