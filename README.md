# Sky Atlas for iOS

An iOS port of **[Sky Map v2](https://github.com/sky-map-team/stardroid/tree/master/stardroid-v2)**,
the open-source Android planetarium: point your phone at the sky and see the stars,
constellations, planets and deep-sky objects that are really there. It works entirely offline,
with no account and no ads.

> **Name:** "Sky Map" and its icons are trademarks/reserved assets of Penterakt LLC, and
> upstream's license requires independent distributions to use a distinct name and identity. So
> this port ships as **Sky Atlas** (a placeholder; change `INFOPLIST_KEY_CFBundleDisplayName`
> in the Xcode project) with its own icon and marker glyphs. See [LICENSE.md](LICENSE.md) and
> [NOTICE.md](NOTICE.md).

## Features

Ported from v2:

- **Real-time sky** that follows the phone (CoreMotion fused attitude, true north when
  location is available), or a **manual mode** with drag, pinch-zoom (0.03°–90°), two-finger
  rotate, fling momentum and auto-levelling of the horizon.
- **Nine layers:** stars (3,186), constellations (88 IAU figures), Messier & deep-sky (135),
  Sun/Moon/planets, meteor showers (10, shown only while active), RA/Dec grid, alt/az grid,
  horizon (with glow and cardinal points), and ecliptic. Each can be toggled, and the grids
  and planet disc size have the same options as v2.
- **Accurate Sun and Moon:** Meeus ch. 25 Sun and truncated ELP-2000/82 Moon, precessed into
  J2000 and corrected for topocentric parallax. Planets use JPL Keplerian elements (valid
  1800–2050).
- **Procedural phases:** the Moon, Mercury, Venus and Mars are drawn with a computed terminator
  oriented by the bright-limb angle.
- **Search** across 5,000+ names and designations ("M31", "α Cyg", "Deneb"), accent-insensitive
  and in the device language, using v2's locale fallback over its 31 locales of catalog names.
  In manual mode the view slews to the result; in sensor mode an arrow guides you.
- **Tap to identify**: info cards with photo, description, a fun fact, data rows, "see also"
  links, and the next **rise and set times** for your location.
- **Time travel**: pick any date and time from 1800 to 2049, jump to the next sunset, sunrise,
  moonrise, full or new moon, and run time forward or backward at up to a day per second.
- **Night mode** (everything red), a daylight sky gradient, a live **pointing readout**
  (RA/Dec, Alt/Az with compass point, FOV), a **photo gallery** of 250 celestial images, and
  adjustable label size.

Not yet ported (v2 features with no iOS equivalent here yet): satellites/ISS passes, eclipse
shading and alerts, the camera AR overlay and drag-to-align, home-screen widgets,
notifications, the onboarding tour, UI translations (catalog names and info cards *are*
localized), and magnetic-declination correction when true north is unavailable.

## Layout

```
SkyCore/            Swift package with no UIKit dependency, so it builds and tests on Linux too
  Sources/SkyCore/
    Math/           Vector3, Matrix3, RaDec, LatLong, rotations
    Astronomy/      time, Keplerian + Meeus ephemerides, precession, SkyModel, rise/set, phases
    Catalog/        loads the bundled source-data, with locale fallback, search and info cards
    Render/         renderer contract: primitives, camera, projection, styling, decluttering
    Layers/         layer producers that turn data into LayerScenes
    Map/            camera gestures (drag/zoom/rotate/fling/slew/level) and tap-to-identify
    Resources/catalog/   v2's source-data, verbatim
  Tests/            31 tests, including upstream's USNO/Almanac golden values
SkyAtlas/           the iOS app (SwiftUI + UIKit)
  AppModel.swift    state, settings, clock/time travel, scene caching, sensors → camera
  SkyRenderer.swift CoreGraphics backend (gnomonic projection, phases, labels, glyphs)
  SkyView.swift     display-link view and gestures
  Sensors.swift     CoreMotion orientation, CoreLocation
  MapScreen.swift, Sheets.swift   UI
Imagery/            planet discs and celestial photos (third-party, see NOTICE.md)
SkyAtlas.xcodeproj  Xcode 16 project (synchronized folders + local SkyCore package)
```

The architecture follows v2: **pure producers → immutable `LayerScene`s → a backend**. All of
the astronomy, catalog, layer and camera logic lives in `SkyCore` and is unit-tested. The iOS
side is a thin rendering, sensor and UI shell.

## Building

Requirements: Xcode 16+ and iOS 17+.

```sh
open SkyAtlas.xcodeproj    # select the SkyAtlas scheme, set your signing team, and run
```

Motion sensors and the compass need a real device. In the Simulator the app starts in manual
mode.

Run the core tests (macOS or Linux):

```sh
cd SkyCore && swift test
# or, without a local toolchain:
docker run --rm -v "$PWD/SkyCore":/pkg -w /pkg swift:6.0-noble swift test
```

CI (`.github/workflows/ci.yml`) runs the core tests on Linux and macOS and builds the app for
the iOS Simulator.

## Porting notes

- **Orientation convention.** v2's `SkyModel.pointing` expects Android's rotation matrix (rows =
  world East/North/Up in phone coordinates). iOS and Android share the same phone axes, so the
  port builds that matrix from `CMAttitude.rotationMatrix` in the `xTrueNorthZVertical`
  frame. Whether the matrix holds the reference axes as rows or columns is checked at runtime
  against `CMDeviceMotion.gravity`, so a wrong assumption gets corrected instead of producing
  a mirrored sky.
- **Rendering.** v2 uses GLES1. This port draws with CoreGraphics in the same gnomonic
  projection, where great circles become straight lines: lines are subdivided once per scene,
  labels from all layers are decluttered together using v2's FOV-to-magnitude rule, and phases
  use v2's `PhaseGeometry` terminator.
- **Catalog.** Android compiles `source-data/` into SQLite at build time. At this size the port
  simply parses the same files at launch (well under a second) and runs v2's queries in
  memory: magnitude cutoff 5.6, whole-object locale fallback, and search ranking.

## License

GPL-3.0-or-later, with upstream's section-7 app-store permission passed on (so App Store
distribution is allowed). See [LICENSE.md](LICENSE.md), [COPYING](COPYING) and
[NOTICE.md](NOTICE.md). Imagery and star-name data include CC BY 4.0 material, which requires
attribution; the app's About screen provides it.
