SPDX-License-Identifier: GPL-3.0-or-later

Stellar Navigator for iOS — a Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).

Copyright (c) 2026 Penterakt LLC and contributors (the original Kotlin program and its data).
Copyright (c) 2026 the Stellar Navigator for iOS contributors (the Swift port).

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. The full license text is in `COPYING`.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

---

The upstream program carries the following additional permission, which this port passes on
unchanged for the parts derived from it:

## Additional Permission under GNU GPL Version 3, Section 7

As an additional permission under section 7 of the GNU General Public License version 3, the
copyright holders of this Program grant you permission to convey the Program, or a work based on
the Program, through an application distribution service or platform — including without
limitation the Apple App Store, Google Play, and comparable services — notwithstanding that the
terms of service of such a platform impose restrictions on recipients' exercise of the rights
granted by this License, including without limitation:

  (a) restrictions on redistribution or further conveyance of the conveyed copy;
  (b) limits on the number of devices or accounts on which the conveyed copy may be installed
      or used;
  (c) a requirement that recipients accept the platform operator's terms of service; and
  (d) technical measures that control the installation or execution of the conveyed copy.

This additional permission applies solely to conveyance through such a platform. It does not
restrict any other right granted by the License, and it does not affect the availability of the
Corresponding Source, which remains available under the terms of the License for every version
conveyed.

As provided in section 7 of the License, you may remove this additional permission from any copy
of the Program, or from any part of it, that you convey.

**Why this exists.** The Free Software Foundation's position is that some application-store terms
impose conditions the GPL forbids adding, which is why GPL-licensed applications have previously
been withdrawn from such stores. This permission resolves that conflict so Sky Map can be
distributed through those channels while the source remains free software under GPLv3.

---

## What is not covered

- **Sky Map brand assets are not included.** Upstream reserves the "Sky Map" name, its launcher
  and notification icons, the welcome backdrop and the sky-marker icon set (All Rights Reserved,
  Penterakt LLC; see upstream `ASSET-LICENSES.txt`). This port ships none of them: it uses its
  own name, its own app icon (`StellarNavigator/Assets.xcassets/AppIcon.appiconset`, GPLv3) and draws
  its own vector marker glyphs (`StellarNavigator/SkyRenderer.swift`).
- **Scientific data and imagery keep their own terms.** `Imagery/` and the catalog data under
  `SkyCore/Sources/SkyCore/Resources/catalog/` are a mix of public-domain material (NASA, ESA,
  JPL, USNO and public catalogs) and **CC BY 4.0** material (ESO, IAU, IAU/Sky & Telescope,
  EHT), which requires attribution. Attribution is given in the app's About screen and in
  `NOTICE.md`.
