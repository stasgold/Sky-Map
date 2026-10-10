# Notices

## Provenance

This project is a Swift/iOS port of **Sky Map v2**, the open-source Android planetarium
(<https://github.com/sky-map-team/stardroid>, directory `stardroid-v2/`), which is
© 2026 Penterakt LLC and contributors and licensed GPL-3.0-or-later with an app-store
permission under section 7. Sky Map itself descends from Google Sky Map (Google Inc.,
open-sourced under Apache-2.0); see upstream `NOTICE.md` for that ancestry.

This port is **not affiliated with or endorsed by** the Sky Map team or Penterakt LLC.
"Sky Map" is used here only to describe where the code comes from.

| Upstream (Kotlin) | This port (Swift) |
|---|---|
| `core/math` | `SkyCore/Sources/SkyCore/Math` |
| `core/astronomy` (ephemerides, precession, sky model, rise/set, lunar phase, bright limb) | `SkyCore/Sources/SkyCore/Astronomy` |
| `core/catalog`, `data/generator/SourceDataLoader`, `data/RoomCatalogRepository` | `SkyCore/Sources/SkyCore/Catalog` |
| `render/api`, parts of `render/gles1` (stellar styling, label decluttering) | `SkyCore/Sources/SkyCore/Render` |
| `app/…/layers` | `SkyCore/Sources/SkyCore/Layers` |
| `app/…/ui/map/MapViewModel` (gestures, slew, leveling), tap-to-identify | `SkyCore/Sources/SkyCore/Map`, `StellarNavigator/AppModel.swift` |
| `source-data/` | `SkyCore/Sources/SkyCore/Resources/catalog` (verbatim) |
| `app/src/main/assets/planets`, `…/celestial_images` | `Imagery/` (verbatim) |

## Data and imagery

The catalog data (`source-data`) is factual/public-domain material inherited from Sky Map v1's
data files. Star proper names come from the IAU Working Group on Star Names (WGSN) Catalog of
Star Names (**CC BY 4.0**); Bayer/Flamsteed designations from the Yale Bright Star Catalogue,
5th ed. Info-card text and translations were written for Sky Map by its contributors (GPLv3).

Data sources: Centre de Données astronomiques de Strasbourg; The Bright Star Catalogue, 5th
Revised Ed. (Hoffleit & Warren); IAU Catalog of Star Names (CC BY 4.0); The HYG Database v1.0;
Corwin, *History and Accurate Positions for the NGC/IC Objects*; Sulentic & Tifft, *Revised New
General Catalogue*; SFA Star Charts; USNO; Meeus, *Astronomical Algorithms*.

Image credits:

- Hubble Space Telescope images: NASA, ESA, and the Space Telescope Science Institute
- Planet images: NASA/JPL-Caltech, NASA/Johns Hopkins APL/Carnegie (MESSENGER),
  NASA/Johns Hopkins APL/SwRI (New Horizons); Sun: NASA/SDO (HMI)
- Moon image: NASA/GSFC/Arizona State University (Lunar Reconnaissance Orbiter)
- Star field images: ESO Digitized Sky Survey 2 — **CC BY 4.0**
- Constellation charts: IAU and Sky & Telescope (Roger Sinnott & Rick Fienberg) — **CC BY 4.0**
- Additional deep-sky object images: Gemini Observatory/NOIRLab/NSF/AURA
- M31 image: Peter Kennett (Wikimedia Commons)
- Sagittarius A* image: EHT Collaboration — **CC BY 4.0**
- Cygnus X-1 illustration: NASA/CXC/M.Weiss

Per-file provenance for the planet discs is in `Imagery/planets/SOURCES.md`.

## Not included

Upstream's reserved brand assets (the "Sky Map" name and logos, launcher/notification icons,
welcome backdrop, sky-marker icon set) are **not** part of this port. The app icon here is
original artwork and the deep-sky/meteor markers are drawn as vectors in code.
