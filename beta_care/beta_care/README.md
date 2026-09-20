# Beta Care

The parent/caregiver companion app for the Beta AI elderly-assistance ecosystem, built from the Beta Care spec: Firebase auth, elderly↔caregiver family linking, granular backend-enforced permissions, a one-glance dashboard, medication/health/location/device monitoring, and emergency alerts.

## Quick start

This runs with **zero setup** - no Firebase project, no backend - because it defaults to an in-memory mock of the entire Beta backend:

```bash
flutter pub get
flutter run
```

Sign in with any email and any password 6+ characters long (the mock accepts anything that meets that shape). You'll land on a dashboard for "Dad" with realistic sample data matching the worked examples in the spec.

Run the tests with:

```bash
flutter test
```

## Demo mode vs. the real backend

Everything hinges on one flag, in `lib/core/app_config.dart`:

```dart
static const bool useMockBackend = true;
```

While `true`, `main.dart` wires up `MockAuthService`, `MockBetaApiClient`, and `MockNotificationService` - pure in-memory implementations with no network calls at all. Flip it to `false` once you have:

1. A real Firebase project, with `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) added and Firebase initialization uncommented in `main.dart`.
2. `AppConfig.backendBaseUrl` pointed at the real Beta backend.

From there, `main.dart` switches to `FirebaseAuthService`, `HttpBetaApiClient`, and `FirebaseNotificationService` - no other file needs to change, because every screen and provider only ever depends on the abstract `AuthService` / `BetaApiClient` / `NotificationService` interfaces, never a concrete implementation.

### Matching this to your actual backend

`lib/services/http_beta_api_client.dart` implements the endpoint list from the spec (`GET /users/me`, `/family`, `/health`, `/medications`, `/location/latest`, `/devices`, `/alerts`, `/notifications`, etc.), sending the caregiver's Firebase ID token as `Authorization: Bearer <token>` on every call. Two things in there are **assumptions you should verify against your real backend** (flagged with comments in the file):

- How a caregiver with more than one elderly connection is disambiguated - this implementation passes `elderlyUserId` as a query parameter on every per-person endpoint.
- The "other caregivers" list (section 15) isn't in the spec's endpoint table, so it's assumed to live at `/family/{elderlyUserId}/caregivers`.

There's no dedicated `/dashboard` endpoint in the spec, so `getDashboardSummary()` composes the dashboard from the other calls in parallel and folds the result down to one status. If your backend gains a real aggregate endpoint later, that's the one method to simplify.

## Architecture

```
lib/
├── main.dart              # wires mock or real services, then MultiProvider
├── core/                  # theme, config, exceptions, time formatting, root routing
├── models/                # plain Dart data classes + fromJson, one file per domain
├── services/              # AuthService, BetaApiClient, NotificationService -
│                          #   each an abstract interface + mock + real implementation
├── providers/             # one ChangeNotifier per domain (loading/data/error)
├── widgets/                # StatusIndicator/StatusRingAvatar, cards, banners, empty/error states
└── screens/               # one folder per spec section: auth, dashboard, family,
                           #   health, medications, location, alerts, devices, settings
```

**State management** is `provider` + `ChangeNotifier` - no code generation, easy to read top to bottom. **Networking** is a hand-rolled `http`-based client rather than a generated one, since the backend contract is small and explicit. Every model is a plain immutable class with `fromJson`; there's no serialization code generation to run (which matters here since generators need `pub.dev` access to fetch).

### Permission enforcement is layered, on purpose

The backend is the real authority (section 21) - this app never assumes otherwise. But the UI *also* checks `PermissionsProvider` before rendering a screen's data, for a better experience than "call the API, get a 403, show an error": an ungranted category shows a calm "hasn't been shared with you" state immediately, and never even fires the underlying request. Section 4's "don't rely on the Flutter app to hide information" is about security, not about UX - both layers exist because they solve different problems.

### Offline handling

`ConnectivityProvider` drives the app-wide "you're offline" banner. `DashboardProvider` additionally caches its last successful snapshot to `shared_preferences` and falls back to it on a network failure, flagging `isShowingCachedData` so the UI is honest about it rather than presenting old data as current (section 25). The same pattern is worth extending to the Health/Medication/Location providers as a next step - it's only built out for the dashboard here, as the screen that most needs to work with no signal.

### A few deliberate simplifications

- **One primary elderly connection drives the monitoring tabs.** The data model (`FamilyLink`) supports a caregiver having several, and the Family screen lists all of them, but - matching every worked example in the spec, which only ever shows one person - the Dashboard/Health/Medication/Location/Devices/Alerts tabs all operate on the first *active* link. A "switch person" selector is the natural next step if that's needed.
- **No embedded map.** Rather than pull in `google_maps_flutter` (which needs platform API keys this project can't supply), the Location screen shows the address/coordinates the backend returns plus an "Open in Maps" button that hands off to the device's own Maps app.
- **Emergency alerts can't be muted.** Every other notification category is a real, backend-persisted toggle; emergency is shown in the Notifications screen but the switch is permanently on, on purpose.
- **Design**: a specific calm/muted palette (see `AppColors` in `lib/core/theme.dart`) instead of Flutter's default purple, and one deliberate signature element - the colored status ring around the elderly person's initial on the dashboard - kept restrained everywhere else, per the project's own design guidance about spending boldness in one place rather than spreading it thin.

## What's genuinely done vs. what's next

Built and wired end-to-end with mock data: registration/login, family linking + invite flow, permission-gated Dashboard/Health/Medications/Location/Devices/Alerts, emergency alert treatment with View Location/Call/Mark as Responded, notification preferences, the "Your Access" privacy screen, offline banner + dashboard caching, light/dark theme.

Not done, and worth treating as the next milestones rather than gaps in this pass: wiring a real Firebase project and the real backend (the seams are ready, see above); push-notification deep-linking from a tapped notification straight to the relevant alert; a "switch elderly person" selector for caregivers with more than one connection; richer health history (currently a simple list, not a chart); and the full test matrix from section 27 of the spec (two representative tests are included - one unit, one widget - as a pattern to build on, not full coverage).

## A note on this sandbox

This was written and organized here but **not compiled** - this container doesn't have network access to `pub.dev` (or the Flutter SDK installer), so `flutter pub get` couldn't be run to verify it. Everything was written carefully and consistently, but budget time for `flutter pub get && flutter analyze` to catch anything that slipped through, especially around exact Flutter API surface (things like Material widget parameter names do shift between versions).
