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
    @State private var auth = AuthModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .checking:
                    PlayfulLoader(lines: ["Checking the mailbox…", "Sorting the post…", "Nearly there…"])
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cream.ignoresSafeArea())
                case .signedOut:
                    WelcomeView()
                case .needsProfile:
                    ProfileSetupView()
                case .signedIn:
                    ContentView()
                }
            }
            .environment(model)
            .environment(auth)
            .tint(Theme.ink)
            .preferredColorScheme(model.isOnDarkPage && auth.state == .signedIn ? .dark : .light)
            .task { await auth.restore() }
            // Signing out (or Apple revoking access) wipes what the last person left in memory.
            .onChange(of: auth.state) { _, state in
                if state == .signedOut { model.reset() }
            }
            // Puzzle progress is saved whenever the app goes into the background.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.saveProgress() }
            }
        }
    }
}
