//
//  ProfileView.swift
//  Sliding
//

import SwiftUI

/// Your profile, from the ⋯ menu: who you are, a few numbers, and your account.
struct ProfileView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    private var solvedCount: Int { model.stories.filter { !$0.isSent && $0.isSolved }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let profile = auth.profile {
                    hero(profile)
                        .padding(.bottom, 10)
                }

                HStack(spacing: 12) {
                    StatTile(value: model.sent.count, label: "Sent", symbol: "paperplane.fill", color: Theme.sky)
                    StatTile(value: solvedCount, label: "Solved", symbol: "puzzlepiece.fill", color: Theme.green)
                    StatTile(value: model.connected.count, label: "People", symbol: "person.2.fill",
                             color: Theme.purple)
                }

                SectionLabel(title: "Account")

                SettingsRow(symbol: "apple.logo", title: "Signed in with Apple",
                            detail: "Your name and username are only shown to your connections")

                Button { confirmSignOut = true } label: {
                    SettingsRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out",
                                tint: Theme.orange)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .screenBackground()
        .screenTitle("Profile")
        // A centered alert: a popover would point at the top of the page, not the button.
        .alert("Sign out of Postcards?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in with Apple any time.")
        }
    }

    /// Orange and wavy like the highlighted cards, tilted and floating, with your initials as the stamp.
    private func hero(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Avatar(name: profile.displayName, size: 76, ringed: true)
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 40, height: 46)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.orange.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [3, 3])))
                    .rotationEffect(.degrees(10))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(Theme.display(30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("@\(profile.username)")
                    .font(Theme.body(16, weight: .semibold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wavyCard(Theme.orange)
        .floaty(tilt: -2, seed: 0.4)
        .shadow(color: Theme.orange.opacity(0.3), radius: 14, y: 8)
    }
}

/// A small number card: icon, count, label.
private struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(Theme.display(26))
                Text(label.uppercased())
                    .font(Theme.display(11))
                    .kerning(0.5)
                    .foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
        .accessibilityElement(children: .combine)
    }
}

/// A rounded row with an icon in a paper circle, like the story rows.
struct SettingsRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = Theme.ink

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(Theme.paper, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(17))
                if let detail {
                    Text(detail)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(8)
        .padding(.trailing, 10)
        .softCard(radius: 38)
        .contentShape(Rectangle())
    }
}
