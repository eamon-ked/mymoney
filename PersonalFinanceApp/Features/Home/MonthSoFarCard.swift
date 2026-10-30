//
//  MonthSoFarCard.swift
//  Nokael Money
//

import SwiftUI

/// The month under Safe to spend. Tapping it goes deeper.
struct MonthSoFarCard: View {
    let sentence: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This month so far").font(.caption.weight(.semibold)).foregroundStyle(Palette.brand)
                    Text(sentence).font(.subheadline).foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("monthSoFar")
    }
}
