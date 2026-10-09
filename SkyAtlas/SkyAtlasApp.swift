/*
 * Copyright (c) 2026 Penterakt LLC and contributors.
 * Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI

@main
struct SkyAtlasApp: App {
    var body: some Scene {
        WindowGroup {
            MapScreen()
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
