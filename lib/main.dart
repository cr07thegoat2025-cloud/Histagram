import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';

// The project URL and publishable (anon) key are meant to be public: they ship
// inside every client app. Access is protected by Row Level Security.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://sgzbbbrhoskipnvclskl.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_KEY',
    defaultValue: 'sb_publishable_Mzlu_uSXfnGzaWYI2dp1og_ha7RJV1W');

const brand = Color(0xFF5B3DF5);

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const HistagramApp());
}

class HistagramApp extends StatelessWidget {
  const HistagramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Histagram',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark),
      ),
      themeMode: ThemeMode.system,
      home: StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, snap) {
          final session = snap.data?.session ?? db.auth.currentSession;
          return session != null ? const HomeShell() : const AuthScreen();
        },
      ),
    );
  }
}
