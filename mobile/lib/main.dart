import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/personal_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The Personal Supabase project is the ONLY backend this entry point
  // initialises. Business will get its own isolated client and entry wiring
  // when that vertical slice starts; it must never reuse this client.
  if (PersonalEnv.isConfigured) {
    await Supabase.initialize(
      url: PersonalEnv.supabaseUrl,
      anonKey: PersonalEnv.supabaseAnonKey,
    );
  }

  runApp(const ProviderScope(child: KuikChatApp()));
}
