import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZeroHourLauncherApp());
}

class ZeroHourLauncherApp extends StatelessWidget {
  const ZeroHourLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zero Hour Launcher',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080B0C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE6A33A),
          brightness: Brightness.dark,
        ),
      ),
      home: const LauncherScreen(),
    );
  }
}

class GameProfile {
  const GameProfile({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.version,
    required this.kind,
    required this.author,
    required this.description,
    required this.posterUrl,
    required this.accent,
  });

  final String id;
  final String name;
  final String subtitle;
  final String version;
  final String kind;
  final String author;
  final String description;
  final String posterUrl;
  final Color accent;
}

const profiles = <GameProfile>[
  GameProfile(
    id: 'vanilla',
    name: 'Zero Hour',
    subtitle: 'Original',
    version: '1.04',
    kind: 'Original game',
    author: 'EA Los Angeles',
    description:
        'Original Command & Conquer: Generals - Zero Hour profile without gameplay modifications.',
    posterUrl:
        'https://images.launchbox-app.com/901299f0-74da-411c-b4b6-42dd1f66dc69.jpg',
    accent: Color(0xFFE7A138),
  ),
  GameProfile(
    id: 'enhanced',
    name: 'Zero Hour Enhanced',
    subtitle: 'Modernized overhaul',
    version: '1.0.0',
    kind: 'Gameplay and visual overhaul',
    author: 'Acoustic Alpha / VectorIV',
    description:
        'A large Zero Hour overhaul focused on infantry, vehicles, environments, effects, balance and higher-detail presentation.',
    posterUrl:
        'https://media.moddb.com/images/mods/1/57/56865/profile/icon.jpg',
    accent: Color(0xFFF2B74C),
  ),
  GameProfile(
    id: 'contra-x',
    name: 'Contra X',
    subtitle: 'Total conversion',
    version: 'Beta 2',
    kind: 'Total conversion',
    author: 'Contra Mod Team',
    description:
        'Contra X pushes Zero Hour toward heavier warfare with new units, buildings, weapons, effects and balance changes.',
    posterUrl:
        'https://media.moddb.com/images/members/1/292/291992/profile/Contra_X_Beta_2_Banner_For_Artic.jpg',
    accent: Color(0xFFD94D37),
  ),
];

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  static const _channel = MethodChannel('generalsx.launcher');

  int selected = 1;
  bool motion = true;

  GameProfile get profile => profiles[selected];

  void _select(int index) {
    setState(() => selected = index);
  }

  void _move(int delta) {
    final next = (selected + delta).clamp(0, profiles.length - 1).toInt();
    setState(() => selected = next);
  }

  Future<void> _play() async {
    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>(
          'launchProfile',
          <String, Object>{'profile': profile.id},
        );
        return;
      } on PlatformException catch (error) {
        _notice('iOS bridge: ' + (error.message ?? error.code));
        return;
      }
    }

    _notice('Windows preview - PLAY ' + profile.name.toUpperCase());
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          width: 440,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF171D20),
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _move(1);
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _move(-1);
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          _play();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 980;
            return Stack(
              fit: StackFit.expand,
              children: [
                _Background(profile: profile),
                const _Atmosphere(),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 18 : 28),
                    child: Column(
                      children: [
                        _Header(
                          motion: motion,
                          onToggleMotion: () => setState(() => motion = !motion),
                        ),
                        SizedBox(height: compact ? 18 : 26),
                        Expanded(
                          child: compact
                              ? _CompactLayout(
                                  profiles: profiles,
                                  selected: selected,
                                  onSelect: _select,
                                  onPlay: _play,
                                  motion: motion,
                                )
                              : _WideLayout(
                                  profiles: profiles,
                                  selected: selected,
                                  onSelect: _select,
                                  onPlay: _play,
                                  motion: motion,
                                ),
                        ),
                        SizedBox(height: compact ? 12 : 18),
                        _Footer(profile: profile),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({required this.profile});

  final GameProfile profile;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: Stack(
        key: ValueKey(profile.id),
        fit: StackFit.expand,
        children: [
          _RemotePoster(profile: profile, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: Container(color: Colors.black.withValues(alpha: .55)),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x6A050708),
                  Color(0xB0080B0C),
                  Color(0xFA080B0C),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Atmosphere extends StatelessWidget {
  const _Atmosphere();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(.62, -.78),
            radius: 1.2,
            colors: [
              const Color(0xFFE7A138).withValues(alpha: .11),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.motion,
    required this.onToggleMotion,
  });

  final bool motion;
  final VoidCallback onToggleMotion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFFE7A138),
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(color: Color(0x66E7A138), blurRadius: 14),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'ZERO HOUR',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'LAUNCHER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
            color: Colors.white.withValues(alpha: .42),
          ),
        ),
        const Spacer(),
        Text(
          '3 PROFILES',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: .38),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Toggle poster motion',
          onPressed: onToggleMotion,
          icon: Icon(
            motion
                ? Icons.motion_photos_on_rounded
                : Icons.motion_photos_off_rounded,
          ),
        ),
      ],
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.profiles,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.motion,
  });

  final List<GameProfile> profiles;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onPlay;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: _HeroCard(
            profile: profiles[selected],
            motion: motion,
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 330,
          child: _SidePanel(
            profiles: profiles,
            selected: selected,
            onSelect: onSelect,
            onPlay: onPlay,
          ),
        ),
      ],
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.profiles,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.motion,
  });

  final List<GameProfile> profiles;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onPlay;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final profile = profiles[selected];

    return Column(
      children: [
        Expanded(
          child: _HeroCard(profile: profile, motion: motion),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 148,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: profiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => SizedBox(
                    width: 220,
                    child: _ProfileTile(
                      profile: profiles[index],
                      active: selected == index,
                      onTap: () => onSelect(index),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: _PlayButton(profile: profile, onPressed: onPlay),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.profile,
    required this.motion,
  });

  final GameProfile profile;
  final bool motion;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  Offset pointer = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final shift = widget.motion ? pointer : Offset.zero;

    return MouseRegion(
      onHover: (event) {
        if (!widget.motion) return;
        final size = context.size;
        if (size == null) return;

        final x = (event.localPosition.dx / size.width - .5) * 8;
        final y = (event.localPosition.dy / size.height - .5) * 8;
        setState(() => pointer = Offset(x, y));
      },
      onExit: (_) {
        if (widget.motion) setState(() => pointer = Offset.zero);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              child: Transform.translate(
                key: ValueKey(widget.profile.id),
                offset: shift,
                child: Transform.scale(
                  scale: widget.motion ? 1.035 : 1,
                  child: _RemotePoster(
                    profile: widget.profile,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x08000000),
                    Color(0x2A000000),
                    Color(0xE6000000),
                  ],
                  stops: [0, .48, 1],
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: _Pill(
                text: widget.profile.version,
                color: widget.profile.accent,
              ),
            ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 26,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Column(
                  key: ValueKey(widget.profile.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.profile.subtitle.toUpperCase(),
                      style: TextStyle(
                        color: widget.profile.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.profile.name,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 11),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 690),
                      child: Text(
                        widget.profile.description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: .72),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.profiles,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
  });

  final List<GameProfile> profiles;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final profile = profiles[selected];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xD0101416),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 12),
            child: Text(
              'SELECT PROFILE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.white.withValues(alpha: .4),
              ),
            ),
          ),
          ...List.generate(
            profiles.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _ProfileTile(
                profile: profiles[index],
                active: selected == index,
                onTap: () => onSelect(index),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.kind.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: profile.accent,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  profile.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: .58),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 62,
            width: double.infinity,
            child: _PlayButton(profile: profile, onPressed: onPlay),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.active,
    required this.onTap,
  });

  final GameProfile profile;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? Colors.white.withValues(alpha: .075)
          : Colors.white.withValues(alpha: .025),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 86,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active
                  ? profile.accent.withValues(alpha: .72)
                  : Colors.white.withValues(alpha: .055),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 70,
                  height: double.infinity,
                  child: _RemotePoster(
                    profile: profile,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      profile.version,
                      style: TextStyle(
                        fontSize: 11,
                        color: active
                            ? profile.accent
                            : Colors.white.withValues(alpha: .42),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: active ? 1 : 0,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: profile.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: profile.accent.withValues(alpha: .55),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.profile,
    required this.onPressed,
  });

  final GameProfile profile;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: profile.accent,
        foregroundColor: const Color(0xFF12100B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      onPressed: onPressed,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_arrow_rounded, size: 24),
          SizedBox(width: 8),
          Text(
            'PLAY',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemotePoster extends StatelessWidget {
  const _RemotePoster({
    required this.profile,
    required this.fit,
  });

  final GameProfile profile;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      profile.posterUrl,
      fit: fit,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      frameBuilder: (context, child, frame, syncLoaded) {
        if (syncLoaded || frame != null) return child;
        return _PosterFallback(profile: profile);
      },
      errorBuilder: (_, __, ___) => _PosterFallback(profile: profile),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.profile});

  final GameProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            profile.accent.withValues(alpha: .34),
            const Color(0xFF151B1F),
            const Color(0xFF080A0C),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -35,
            top: -20,
            child: Icon(
              Icons.radar_rounded,
              size: 220,
              color: Colors.white.withValues(alpha: .05),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Text(
              profile.name.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: .65),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
          ),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.profile});

  final GameProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'GENERALSX',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .28),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const Spacer(),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: profile.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          profile.name + ' - ' + profile.version,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .42),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
