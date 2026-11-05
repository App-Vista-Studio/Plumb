//
//  PlumbApp.swift
//  Plumb
//
//  Created by Admin on 9/30/26.
//

import SwiftUI

@main
struct PlumbApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() { StorageGuard.trimOnLaunch() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Retry a save that failed on a full disk before the app is suspended.
            if phase == .background, MeasurementStore.shared.saveFailed { MeasurementStore.shared.writeNow() }
        }
    }
}
