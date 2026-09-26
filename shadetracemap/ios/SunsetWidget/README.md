# Sunset home-screen widget — one-time Xcode setup

`SunsetWidget.swift` in this folder is the widget's UI (current time via
WidgetKit's own live clock, plus today's sunset written by the Flutter app).
The Dart side (`lib/home_widget_service.dart`) is already wired up and
syncing. What's left has to be done in Xcode once, because creating an
extension target and enabling an App Group both require Xcode itself (a
signed-in Apple Developer team, and Xcode's own project-file management) —
they can't be scripted safely from the command line.

## 1. Create the Widget Extension target

1. Open `ios/Runner.xcworkspace` in Xcode (**not** `Runner.xcodeproj`).
2. **File → New → Target…**, choose **Widget Extension**, and set:
   - Product Name: `SunsetWidget` (must match exactly — it's referenced by
     name from both the Dart side and this Swift file)
   - Team: your Apple Developer team
   - Uncheck "Include Configuration Intent" (this widget is static, no
     user-configurable options)
   - Language: Swift
3. When Xcode asks to activate the new scheme, either choice is fine.

Xcode generates its own boilerplate Swift file(s) inside a new
`SunsetWidget` group. **Delete those generated `.swift` files** (keep
`Assets.xcassets` and `Info.plist`), then drag this folder's
`SunsetWidget.swift` into that group in Xcode's navigator, making sure its
**Target Membership** (in the File Inspector) is checked for `SunsetWidget`
only, not `Runner`.

## 2. Enable the App Group on both targets

The app and the widget extension are separate processes — an App Group is
how they share data (the sunset time the Dart side writes).

1. Select the **Runner** target → **Signing & Capabilities** → **+
   Capability** → **App Groups**.
2. Click **+** under the App Groups list and add exactly:
   `group.com.shadetracemap.shadetracemap`
   (This project already has `ios/Runner/Runner.entitlements` with this
   group pre-filled — Xcode should pick it up automatically when you add the
   capability; if it creates its own new entitlements file instead, that's
   fine too, as long as the same group id ends up checked.)
3. Select the **SunsetWidget** target → **Signing & Capabilities** → **+
   Capability** → **App Groups** → check the **same**
   `group.com.shadetracemap.shadetracemap` group (it should now appear in
   the list since Runner just registered it).

Both targets need a valid signing Team selected for this to work — App
Groups requires provisioning, which Xcode handles automatically with
"Automatically manage signing" once a Team is picked.

## 3. Build and add the widget

1. Build/run the **Runner** scheme as usual (from Xcode or `flutter run`).
2. Open the app once — this triggers the location permission prompt (same
   one the rest of the app already uses) and pushes today's sunset time
   into the widget's shared storage.
3. On the device/simulator: long-press the home screen → **+** (top-left) →
   search "Sunset" → add the small widget.

If you ever change the app's bundle id or the App Group name, update the
group string in all three places it's hardcoded: `Runner.entitlements`,
`SunsetWidget.swift`'s `widgetGroupId`, and
`lib/home_widget_service.dart`'s `_iosAppGroupId`.
