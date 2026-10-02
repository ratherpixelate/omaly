# omaly — Flutter desktop frontend

Person 3's piece of ASCENT'26. Desktop-only Flutter app for the privacy-first
local photo library.

## Run it

```bash
flutter run -d linux      # or -d macos / -d windows
flutter test
flutter analyze
```

No backend needed to start: the app runs against hardcoded mock data by
default, so it works even before the FastAPI side exists.

### Previewing without any UI

To confirm the desktop app launches before building anything on top of it,
run the blank target — nothing but the base background colour:

```bash
flutter run -d linux -t lib/preview_blank.dart
```

Swap `-t lib/preview_blank.dart` for `-t lib/main.dart` to go back to the app.

### How the desktop build actually runs

There is no install step and nothing is written to system directories. Flutter
compiles your Dart into a native executable and wraps it in a thin GTK / Win32 /
Cocoa runner:

| Platform | Output | What it is |
| --- | --- | --- |
| Linux | `build/linux/x64/{debug,release}/bundle/frontend` | a single ELF executable |
| Windows | `build/windows/x64/runner/{Debug,Release}/` | `.exe` plus its DLLs |
| macOS | `build/macos/Build/Products/Release/omaly.app` | a `.app` bundle |

`flutter run` launches that executable and stays attached to it, which is what
gives you **hot reload** (press `r` in the terminal — UI-only changes, instant)
and **hot restart** (`R` — restarts Dart state). The built binary also runs
standalone by double-clicking it, but with no debugger attached, so there is no
hot reload.

Use `--release` for the demo: faster frame rendering, no debug banner, and it is
what you should ship on the demo machine. It takes longer to build than debug.

## Swapping mock -> real backend

One line, in `lib/config.dart`:

```dart
const bool kUseMockApi = true;   // flip to false when the backend is live
```

Nothing else changes. Screens depend on the `ApiClient` interface
(`lib/api/api_client.dart`), never on `http` or on mock data directly.

Flip it back to `true` if a teammate's endpoint breaks mid-demo — the mock is
kept working on purpose.

## Endpoint contract

Base URL: `http://localhost:8000` (`kApiBaseUrl` in `lib/config.dart`).

| Endpoint | Client method |
| --- | --- |
| `GET /health` | `ApiClient.health()` |
| `GET /search?q=&top_k=` | `ApiClient.search()` |
| `GET /best-shot?group_id=` | `ApiClient.bestShot()` |
| `GET /wrapped` | `ApiClient.wrapped()` |
| `GET /thumbnails/{id}` | `ApiClient.thumbnailUri()` |

Models in `lib/models/` parse the exact contract field names
(`thumbnail_url`, `taken_at`, `top_people`, `photo_count`, …). A response that
doesn't match fails loudly in the UI with the received keys listed, instead of
rendering a blank screen.

`location` is nullable in the contract, and is handled as nullable everywhere.

## Testing all three states without touching the backend

In mock mode the query text is special-cased:

- `fail` -> error state (simulates an unreachable backend)
- `empty` -> empty state (simulates zero results)
- anything else -> the hardcoded 12-result set, with two entries having
  `"location": null` to exercise the nullable path

## Notes

- **Thumbnails use `Image.network`, not `cached_network_image`.** That package
  depends on `flutter_cache_manager` -> `sqflite`, which has no Linux/Windows
  desktop implementation and throws `MissingPluginException` when it opens its
  cache DB. `Image.network` uses Flutter's built-in in-memory `ImageCache` and
  works on every desktop platform. All thumbnail rendering goes through
  `PhotoTile` (`lib/widgets/photo_tile.dart`) if you want to swap it later.
- Mock responses are stored as raw JSON strings so they can be diffed directly
  against a teammate's live response.

## Colours

Two surfaces define the app. Both live in `lib/theme/palette.dart`, and
`preview_blank.dart` imports the same constants, so the blank preview always
mirrors the shipping layout.

| Constant | Value | Where |
| --- | --- | --- |
| `kChromeColor` | `#121318` | sidebar rail — pinned, does not follow the theme |
| `kContentColor` | `#F9F8FE` | content surface, light (default) |
| `kContentColorDark` | `#17181E` | content surface, dark (after the theme toggle) |

Two consequences worth knowing before adding pages:

- The rail's background is fixed, so `HomeShell` wraps the sidebar in a `Theme`
  forced to `Brightness.dark`. Without that, light mode puts dark text on a
  near-black rail and the wordmark disappears.
- Pages should take their background from `Theme.of(context).scaffoldBackgroundColor`,
  not `colorScheme.surface`. M3's surface is only *near* `#F9F8FE`, and the
  small difference is visible against a hardcoded spec colour.

`kContentColorDark` is a shade lighter than `kChromeColor` on purpose: the
divider between the rail and the content is gone, so the two surfaces have to
stay distinguishable by value alone.
