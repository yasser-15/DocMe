import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../features/discover/discover_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/records/records_screen.dart';

/// Root navigation shell.
///
/// One `GlassScaffold` owns the chrome for the whole app: glass app bar, glass
/// tab bar, and the gradient backdrop. Tab bodies are swapped in an
/// `IndexedStack` so scroll position and in-progress state survive tab changes.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Today', 'Discover', 'Records', 'Profile'];

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: const DocMeBackdrop(),
      statusBarStyle: GlassStatusBarStyle.auto,
      contentAwareBrightness: false,

      // GlassAppBar takes `actions:` — there is no `trailing:` parameter.
      appBar: GlassAppBar(
        title: Text(_titles[_tab]),
        actions: [
          GlassIconButton(
            // GlassIconButton takes `onPressed`, the opposite of GlassButton.
            icon: const Icon(CupertinoIcons.bell, size: 20),
            onPressed: _showNotifications,
            semanticLabel: 'Notifications',
          ),
          const SizedBox(width: 4),
        ],
      ),

      // `GlassBottomBar` was deleted in 1.0 — `GlassTabBar.bottom` replaces it.
      bottomBar: GlassTabBar.bottom(
        selectedIndex: _tab,
        onTabSelected: (i) => setState(() => _tab = i),
        tabs: const [
          GlassTab(
            icon: Icon(CupertinoIcons.house, size: 22),
            activeIcon: Icon(CupertinoIcons.house_fill, size: 22),
            label: 'Today',
          ),
          GlassTab(
            icon: Icon(CupertinoIcons.search, size: 22),
            activeIcon: Icon(CupertinoIcons.search_circle_fill, size: 22),
            label: 'Discover',
          ),
          GlassTab(
            icon: Icon(CupertinoIcons.square_list, size: 22),
            activeIcon: Icon(CupertinoIcons.square_list_fill, size: 22),
            label: 'Records',
          ),
          GlassTab(
            icon: Icon(CupertinoIcons.person, size: 22),
            activeIcon: Icon(CupertinoIcons.person_fill, size: 22),
            label: 'Profile',
          ),
        ],
      ),

      body: IndexedStack(
        index: _tab,
        children: const [
          HomeScreen(),
          DiscoverScreen(),
          RecordsScreen(),
          ProfileScreen(),
        ],
      ),
    );
  }

  void _showNotifications() {
    // GlassModalSheet.show takes `context` + `builder` plus optional detents.
    GlassModalSheet.show<void>(
      context: context,
      initialState: GlassSheetState.half,
      halfSize: 0.5,
      peekSize: 100,
      builder: (sheetContext) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            for (final n in _notifications)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ContentCard(
                  // blur: 0 — sheets already sit on a glass backdrop, and a
                  // stack of blurred cards in a scrolling sheet is expensive.
                  blur: 0,
                  accent: n.accent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(n.icon, size: 18, color: n.accent.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              n.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: DocMeColors.inkDarkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Notification {
  const _Notification(this.icon, this.title, this.subtitle, this.accent);

  final IconData icon;
  final String title;
  final String subtitle;
  final DocMeAccent accent;
}

const _notifications = <_Notification>[
  _Notification(
    CupertinoIcons.arrow_2_circlepath,
    'Refill due in 3 days',
    'Metformin 500mg · 6 tablets remaining.',
    DocMeAccent.medication,
  ),
  _Notification(
    CupertinoIcons.doc_text_fill,
    'Visit summary ready',
    'Dr. Amara Osei published notes from 12 Sept.',
    DocMeAccent.primary,
  ),
  _Notification(
    CupertinoIcons.checkmark_seal_fill,
    'Appointment confirmed',
    'Cardiology · Tue 15 Sept, 10:30.',
    DocMeAccent.info,
  ),
];