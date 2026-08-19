import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'glass_panel.dart';

const _nominatimUserAgent =
    'ShadeTraceMapFlutter/1.0 (contact: louis910729@gmail.com)';

/// Reverse-geocodes a lat/lng into a short display label (e.g. "Petaling
/// Jaya, Selangor, Malaysia") via the same free Nominatim API forward search
/// already uses - so a detected device location can show a real place name
/// instead of a generic "My Location" placeholder. Returns null on any
/// failure so callers can fall back to their own default label.
Future<String?> reverseGeocodeLabel(double lat, double lon) async {
  try {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
        .replace(
          queryParameters: {
            'format': 'json',
            'lat': '$lat',
            'lon': '$lon',
            'zoom': '14',
            'accept-language': 'en',
          },
        );
    final res = await http.get(
      uri,
      headers: {'User-Agent': _nominatimUserAgent},
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    final displayName = data is Map ? data['display_name'] as String? : null;
    if (displayName == null || displayName.isEmpty) return null;
    return displayName.split(',').take(3).join(',');
  } catch (_) {
    return null;
  }
}

/// Debounced Nominatim place search, shared by every screen that needs a
/// "search any place worldwide" field. Extracted out of ShadeMapScreen so
/// the Sun Simulator screen (which also needs a location) doesn't duplicate
/// the fetch/debounce/immediate-Enter logic.
class LocationSearchController extends ChangeNotifier {
  final textController = TextEditingController();
  List<dynamic> results = [];
  bool searching = false;

  Timer? _debounceTimer;
  int _gen = 0;

  Future<List<dynamic>> _fetchPlaces(String q) async {
    final gen = ++_gen;
    searching = true;
    notifyListeners();
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(
            queryParameters: {
              'format': 'json',
              'limit': '5',
              'q': q,
              'accept-language': 'en',
            },
          );
      final res = await http.get(
        uri,
        headers: {'User-Agent': _nominatimUserAgent},
      );
      if (gen != _gen) return [];
      final data = res.statusCode == 200 ? jsonDecode(res.body) : null;
      results = data is List ? data : [];
      notifyListeners();
      return results;
    } catch (_) {
      if (gen == _gen) {
        results = [];
        notifyListeners();
      }
      return [];
    } finally {
      if (gen == _gen) {
        searching = false;
        notifyListeners();
      }
    }
  }

  void onChanged(String q) {
    _debounceTimer?.cancel();
    final trimmed = q.trim();
    if (trimmed.length < 3) {
      results = [];
      notifyListeners();
      return;
    }
    _debounceTimer = Timer(
      const Duration(milliseconds: 400),
      () => _fetchPlaces(trimmed),
    );
  }

  /// Enter submits the search right away instead of waiting on the
  /// debounce: use whatever results already loaded, or fetch immediately.
  Future<void> submit(ValueChanged<dynamic> onSelect) async {
    final q = textController.text.trim();
    if (q.length < 3) return;
    if (results.isNotEmpty) {
      onSelect(results.first);
      return;
    }
    _debounceTimer?.cancel();
    final r = await _fetchPlaces(q);
    if (r.isNotEmpty) onSelect(r.first);
  }

  void selected(String label) {
    textController.text = label;
    results = [];
    notifyListeners();
  }

  void clear() {
    textController.clear();
    results = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    textController.dispose();
    super.dispose();
  }
}

class LocationSearchField extends StatelessWidget {
  const LocationSearchField({
    super.key,
    required this.controller,
    required this.onSelect,
    this.hintText = 'Search any place worldwide…',
  });

  final LocationSearchController controller;
  final ValueChanged<dynamic> onSelect;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark ? const Color(0xFF15171C) : const Color(0xFFE9EBEE);
    final textColor = isDark
        ? const Color(0xFFF2F2F2)
        : const Color(0xFF1B1D22);
    final mutedColor = isDark
        ? const Color(0xFF9AA0A8)
        : const Color(0xFF6B7078);
    return AnimatedBuilder(
      // Merge in textController so the clear button appears/disappears on
      // every keystroke, not just when the controller's own notifyListeners
      // fires (which only happens once the debounced search resolves).
      animation: Listenable.merge([controller, controller.textController]),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  controller.clear();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GlassPanel(
                borderRadius: 11,
                tint: tint,
                // A higher, near-opaque tint reads as the same solid color
                // regardless of what's blurred behind it - the live 3D map
                // on the ShadeMap tab vs. a flat background on Sun
                // Simulator - instead of visibly picking up map colors.
                tintOpacity: 0.75,
                padding: EdgeInsets.zero,
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    TextField(
                      controller: controller.textController,
                      style: TextStyle(color: textColor, fontSize: 13.5),
                      cursorColor: const Color(0xFF3B7CFF),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(color: mutedColor, fontSize: 13.5),
                        filled: false,
                        contentPadding: EdgeInsets.fromLTRB(
                          14,
                          12,
                          controller.searching ||
                                  controller.textController.text.isNotEmpty
                              ? 34
                              : 14,
                          12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: const BorderSide(
                            color: Color(0xFF3B7CFF),
                            width: 1.4,
                          ),
                        ),
                      ),
                      onChanged: controller.onChanged,
                      onSubmitted: (_) => controller.submit(onSelect),
                    ),
                    if (controller.searching)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: mutedColor,
                          ),
                        ),
                      )
                    else if (controller.textController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton(
                          onPressed: controller.clear,
                          icon: Icon(Icons.close, size: 16, color: mutedColor),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: 16,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (controller.results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GlassPanel(
                  borderRadius: 11,
                  tint: tint,
                  tintOpacity: 0.78,
                  blurSigma: 14,
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(5),
                      shrinkWrap: true,
                      itemCount: controller.results.length,
                      itemBuilder: (ctx, i) {
                        final r = controller.results[i] as Map;
                        return InkWell(
                          onTap: () => onSelect(r),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 7,
                            ),
                            child: Text(
                              '${r['display_name']}',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
