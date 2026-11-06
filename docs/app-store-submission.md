# App Store submission — Star Nav 1.0.0

Everything App Store Connect asks for, ready to paste. Bundle ID `io.github.stasgold.skyatlas`.

## Listing

**Name** (30 max): `Star Nav`

**Subtitle** (30 max): `Live star map & sky guide`

**Promotional text** (170 max):
> Point your phone at the sky and see the stars, planets and constellations that are really
> there. Fully offline, no account, no ads.

**Description** (4000 max):
> Star Nav is a real-time map of the night sky. Hold your phone up and the map follows where
> you point it, labelling the stars, constellations, planets and deep-sky objects in that part
> of the sky.
>
> SEE WHAT'S UP THERE
> • More than 3,000 stars, 88 constellations and 135 galaxies, nebulae and clusters
> • The Sun, the Moon and the planets in their true positions, with the Moon's real phase
> • Meteor showers shown while they are active
> • RA/Dec and alt/az grids, the horizon and the ecliptic, each easy to switch on or off
>
> FIND ANYTHING
> • Search by name or catalog designation: "Andromeda", "M31", "Vega"
> • Follow the arrow to your target, or let the map glide to it
> • Tap any object for a photo, a description, fun facts and when it next rises and sets
>
> EXPLORE TIME
> • Travel to any date from 1800 to 2049 and watch the sky move
> • Jump to the next sunset, sunrise, moonrise, full moon or new moon
>
> MADE FOR NIGHT USE
> • Night mode turns everything red to protect your dark-adapted eyes
> • Works entirely offline: no account, no ads, no tracking
>
> Star Nav is free, open-source software (GPLv3), built on an open-source Android planetarium.
> Imagery courtesy of NASA, ESA, ESO, the IAU and others, credited in the app.

**Keywords** (100 max):
`astronomy,stars,planets,constellations,night sky,stargazing,planetarium,telescope,moon,galaxy`

**Support URL:** `https://github.com/stasgold/Sky-Map/issues`
**Marketing URL** (optional): `https://github.com/stasgold/Sky-Map`
**Privacy Policy URL:** `https://github.com/stasgold/Sky-Map/blob/main/PRIVACY.md`

**Category:** Primary **Education**, secondary **Reference**
**Copyright:** `2026 Penterakt LLC and contributors` (the upstream code and data; add your name for the port if you like)

## App Privacy (the "nutrition label")

Answer **"No, we do not collect data from this app."** Location and motion are used only on the
device and never sent to the developer, which Apple does not count as collection. The bundled
privacy manifest (`PrivacyInfo.xcprivacy`) declares no tracking and no collected data types.

## Age rating

Answer **None / No** to every question → rated **4+**. (No unrestricted web access, no
user-generated content, no gambling, no contests.)

## Content rights

"Does your app contain, show, or access third-party content?" → **Yes**, and **you have the
rights**: the catalog and imagery are public domain (NASA, ESA, JPL, USNO) or CC BY 4.0 (ESO,
IAU, IAU/Sky & Telescope, EHT), attributed on the in-app About screen as the licences require.

## Export compliance

Already answered in the build (`ITSAppUsesNonExemptEncryption = NO`): the app uses no
encryption beyond what iOS provides. App Store Connect will not ask again.

## App Review notes

> Star Nav is an offline planetarium. No login is required and there is no in-app purchase.
>
> • Point the device at the sky (or anywhere): the star map follows the device orientation
>   using the motion sensors. Tap the hand/compass button (bottom right) to switch to manual
>   mode, then drag to pan and pinch to zoom.
> • Location permission is optional; if denied, the app uses a default location, and one can be
>   entered under ⋯ → Settings.
> • Try: Search (magnifier) → "Moon" or "M31"; tap any labelled object for its info card;
>   Time Travel (clock icon) → "Full Moon".
> • All content is bundled; the app makes no network requests of its own.
> • The app is free software (GPLv3, source at https://github.com/stasgold/Sky-Map). It is an
>   independent iOS port of an open-source Android planetarium and uses its own name and
>   artwork; third-party imagery is credited under ⋯ → About & Credits.

## Screenshots

Generated from the real app by the **App Store screenshots** workflow (Actions tab →
"App Store screenshots" → Run workflow), which drives the app's real screens in the iOS
Simulator with a UI test at a place where it is late evening at run time. Download them from
the [`app-store-screenshots` branch](https://github.com/stasgold/Sky-Map/tree/app-store-screenshots)
or the run's `screenshots` artifact:

| Folder | Device class in App Store Connect | Size |
|---|---|---|
| `iphone-6.9/` | iPhone 6.9" display | 1320 × 2868 |
| `ipad-13/` | iPad 13" display | 2064 × 2752 |

Seven screens each: `01-sky`, `02-info-card`, `03-search`, `04-find-orion`, `05-layers`,
`06-time-travel`, `07-night-mode`. Upload them in that order (or drop any you don't want;
the minimum is one per device class).

## Before you press Submit

- [ ] Name in App Store Connect → App Information is **Star Nav**
- [ ] Build **1.0.0 (12 or later)** selected on the version page; builds 11 and earlier have the
      info-card crash fixed in 12
- [ ] Screenshots uploaded for each required device class
- [ ] Privacy Policy URL set, App Privacy answered "Data Not Collected"
- [ ] Age rating questionnaire completed
- [ ] Review notes pasted; sign-in information: none required
