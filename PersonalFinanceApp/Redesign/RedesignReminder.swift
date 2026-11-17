//
//  RedesignReminder.swift
//  Nokael Money
//
//  A friendly reminder of what someone owes you, to send them: a calm card in Nokael's colours and a
//  short message, shared through the person's own Messages, WhatsApp or mail. Nothing is sent by the app.
//

import SwiftUI
import NokaelCore

extension Redesign {
    /// The App Store page, so whoever gets a reminder can find the app
    static let appStoreLink = URL(string: "https://apps.apple.com/app/id6749822478")!

    /// "Remind Sam": shares a card and a message saying what they owe, on a person who owes you
    struct OweReminder: View {
        let person: LedgerAccountRecord
        @Environment(AppModel.self) private var app

        var body: some View {
            let owed = app.snapshot.balance(person.id)
            if owed.isPositive {
                let card = ReminderCard(name: person.name, amount: app.money(owed, revealed: true),
                                        due: person.owedBackBy.map { app.fullDay($0) }, from: app.store.settings.displayName)
                let image = card.image()
                ShareLink(item: image, subject: Text("A friendly reminder"), message: Text(message(owed)),
                          preview: SharePreview("What \(person.name) owes", image: image)) {
                    Label("Remind \(person.name)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("remindPerson")
            }
        }

        private func message(_ owed: Money) -> String {
            let due = person.owedBackBy.map { " by \(app.fullDay($0))" } ?? ""
            return "Hi \(person.name), a friendly reminder about the \(app.money(owed, revealed: true)) you owe me. "
                + "Could you pay it back\(due)? Thanks!\n\nKept track of with Nokael Money: \(Redesign.appStoreLink.absoluteString)"
        }
    }

    /// The card itself, always in light colours so it looks the same in any chat
    struct ReminderCard: View {
        let name: String
        let amount: String
        let due: String?
        let from: String

        private let green = Color(red: 0.204, green: 0.298, blue: 0.239)      // Nokael's deep green
        private let cream = Color(red: 0.965, green: 0.961, blue: 0.941)
        private let sage = Color(red: 0.659, green: 0.722, blue: 0.627)

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf").font(.system(size: 20, weight: .light))
                    Text("Nokael Money").font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(green)

                Spacer(minLength: 28)
                Text("Hi \(name),").font(.system(size: 20)).foregroundStyle(green.opacity(0.8))
                Text("a friendly reminder").font(.system(size: 20)).foregroundStyle(green.opacity(0.8))
                Text(amount)
                    .font(.system(size: 44, weight: .semibold)).tracking(-1).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(green)
                    .padding(.top, 14)
                Text(from.trimmingCharacters(in: .whitespaces).isEmpty ? "you owe me" : "you owe \(from.trimmingCharacters(in: .whitespaces))")
                    .font(.system(size: 17)).foregroundStyle(green.opacity(0.75))
                if let due {
                    Text("Due by \(due)")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(green)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(sage.opacity(0.45), in: Capsule())
                        .padding(.top, 14)
                }
                Spacer(minLength: 28)
                Rectangle().fill(green.opacity(0.15)).frame(height: 1)
                Text("Kept track of with Nokael Money · on the App Store")
                    .font(.system(size: 12)).foregroundStyle(green.opacity(0.65))
                    .padding(.top, 12)
            }
            .padding(28)
            .frame(width: 360, height: 400, alignment: .topLeading)
            .background(
                LinearGradient(colors: [cream, Color(red: 0.918, green: 0.933, blue: 0.894)], startPoint: .top, endPoint: .bottom)
            )
            .environment(\.colorScheme, .light)
        }

        /// A sharp picture of the card to send
        @MainActor func image() -> Image {
            let renderer = ImageRenderer(content: self)
            renderer.scale = 3
            return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "leaf")
        }
    }
}
