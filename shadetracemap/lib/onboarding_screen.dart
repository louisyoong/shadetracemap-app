import 'package:flutter/material.dart';

// The sun/sunrise accent used for the sun marker and sun-path line on the
// Sun Simulator screen - reused here so "Get Started" reads as part of the
// same visual language rather than a generic Material button color.
const _sunAccent = Color(0xFFFFD580);

// How long the loading state shows after "Get Started" before handing off
// to the main app - gives the ShadeMap tab's native map view a head start
// on its own load (style fetch, building/shadow layers) while the user is
// still looking at this screen instead of a blank/half-drawn map.
const _handoffDelay = Duration(seconds: 2);

/// First-launch-only welcome screen: the branded onboarding graphic fills
/// the whole screen edge-to-edge (it already bakes in its own dark
/// background, logo and wordmark), with just the tagline and "Get Started"
/// action overlaid near the bottom, in the blank space the graphic was
/// designed to leave there. Hands off to the main app (ShadeMap tab) after
/// a short loading beat.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;

  void _handleGetStarted() {
    setState(() => _loading = true);
    Future.delayed(_handoffDelay, widget.onGetStarted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/icon/onboadingtwo.png', fit: BoxFit.cover),
          // A soft bottom scrim keeps the tagline/button legible regardless
          // of what's underneath at that spot in the source image, instead
          // of leaning entirely on the graphic's own baked-in darkness.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.55, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Find real-time shade and\nsun exposure anywhere in\nthe world.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.32,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _sunAccent,
                          foregroundColor: const Color(0xFF2A2620),
                          disabledBackgroundColor: _sunAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        onPressed: _loading ? null : _handleGetStarted,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFF2A2620),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Get Started',
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 19),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
