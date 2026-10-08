//
//  SlidingApp.swift
//  Sliding
//
//  Created by Shuvam Shrestha on 7/10/2026.
//

import SwiftUI

@main
struct SlidingApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(Theme.ink)
                .preferredColorScheme(model.isOnDarkPage ? .dark : .light)
        }
    }
}
