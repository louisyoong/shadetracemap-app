import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

const _hasRatedPrefsKey = 'has_rated_app';

const _appStoreReviewUrl =
    'https://apps.apple.com/app/$appStoreId?action=write-review';

Future<bool> hasRatedApp() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_hasRatedPrefsKey) ?? false;
}

Future<void> _markRated() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_hasRatedPrefsKey, true);
}

/// Shows a "rate this app" prompt, unless the user has already told us
/// they rated it. Intended to be called whenever the Settings tab is
/// opened - there's no reliable way to detect an actual App Store
/// submission from inside the app (Apple deliberately hides that), so
/// tapping a star is treated as the signal to stop asking, same as most
/// apps' own rating prompts.
Future<void> maybeShowRatingDialog(BuildContext context) async {
  if (await hasRatedApp()) return;
  if (!context.mounted) return;

  showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => const _RatingDialog(),
  );
}

Future<void> _submitRating() async {
  await _markRated();
  final uri = Uri.parse(_appStoreReviewUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Mirrors the look of Apple's own native "Enjoying [App]? Tap a star to
/// rate it" prompt (SKStoreReviewController) - five tappable stars that
/// immediately fill up to the tapped one and auto-dismiss shortly after,
/// rather than a separate "Submit" button to press. A custom dialog is
/// used instead of the real SKStoreReviewController because Apple
/// deliberately doesn't tell the calling app whether the user actually
/// left a review, which this app needs to know so it can stop asking.
class _RatingDialog extends StatefulWidget {
  const _RatingDialog();

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int? _selectedStars;

  void _selectStars(int stars) {
    setState(() => _selectedStars = stars);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      _submitRating();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filledUpTo = _selectedStars ?? 0;
    // Slightly gold-tinted even when empty (rather than plain grey) to
    // read as "this control is about stars" at a glance, matching the
    // reference iOS rating prompt's own tinted-outline look.
    const starAccent = Color(0xFFFFB300);

    return CupertinoAlertDialog(
      title: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/icon/logonew.png',
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
          const Text('Enjoying ShadeTrace Map?'),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          children: [
            const Text('Tap a star to rate it on the App Store.'),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                final filled = starIndex <= filledUpTo;
                return GestureDetector(
                  onTap: _selectedStars == null
                      ? () => _selectStars(starIndex)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(
                      filled ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      color: starAccent,
                      size: 26,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not Now'),
        ),
      ],
    );
  }
}
