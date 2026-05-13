//
//  TrackGym_Watch_AppApp.swift
//  TrackGym Watch App Watch App
//
//  Created by Maximilian Ehling on 26.02.26.
//

import SwiftUI

@main
struct TrackGym_Watch_App_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    WatchConnectivityManager.shared.activate()
                }
        }
    }
}
