import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'data/demo_repository.dart';
import 'data/firebase_repository.dart';
import 'data/repository.dart';
import 'screens/analytics_screen.dart';
import 'screens/preferences_screen.dart';
import 'screens/swipe_feed_screen.dart';
import 'screens/upload_bill_screen.dart';

/// Demo mode is on unless built with --dart-define=DEMO=false, and the app
/// also falls back to it if Firebase isn't configured (no google-services.json).
const _demoRequested = bool.fromEnvironment('DEMO', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Repository repo = DemoRepository();
  if (!_demoRequested) {
    try {
      await Firebase.initializeApp();
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
      repo = FirebaseRepository();
    } catch (e) {
      debugPrint('Firebase unavailable, running in demo mode: $e');
    }
  }
  runApp(OnlyBillsApp(repo: repo));
}

class OnlyBillsApp extends StatelessWidget {
  final Repository repo;
  const OnlyBillsApp({super.key, required this.repo});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AppState(repo),
        child: MaterialApp(
          title: 'OnlyBills',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF00897B), useMaterial3: true),
          darkTheme:
              ThemeData(colorSchemeSeed: const Color(0xFF00897B), brightness: Brightness.dark, useMaterial3: true),
          home: const _Shell(),
        ),
      );
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;
  static const _pages = [SwipeFeedScreen(), UploadBillScreen(), AnalyticsScreen(), PreferencesScreen()];
  static const _dest = [
    (Icons.swipe, 'Fund'),
    (Icons.upload_file, 'Upload'),
    (Icons.insights, 'Impact'),
    (Icons.tune, 'Preferences'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 840;
    final body = IndexedStack(index: _index, children: _pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: _dest.map((d) => NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2))).toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _dest.map((d) => NavigationDestination(icon: Icon(d.$1), label: d.$2)).toList(),
      ),
    );
  }
}
