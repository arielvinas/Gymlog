//
//  SupplementsTodayCard.swift
//  Maraton
//
//  Marcado rápido de suplementos del día (un tap por suplemento).
//

import SwiftUI
import SwiftData

struct SupplementsTodayCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SupplementLog.date) private var logs: [SupplementLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Suplementos", systemImage: "pills.fill", tint: .teal)
                Spacer()
                NavigationLink {
                    SupplementSettingsView()
                } label: {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(SupplementKind.allCases) { kind in
                SupplementToggleRow(
                    kind: kind,
                    taken: SupplementTracker.isTaken(kind, on: Date(), logs: logs),
                    streak: SupplementTracker.currentStreak(kind, logs: logs)
                ) {
                    SupplementTracker.toggle(kind, on: Date(), logs: logs, context: context)
                }
            }
        }
        .dashboardCard()
    }
}

// MARK: - Fila con toggle

private struct SupplementToggleRow: View {
    let kind: SupplementKind
    let taken: Bool
    let streak: Int
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(kind.color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if streak > 0 {
                        Text("🔥 \(streak) \(streak == 1 ? "día" : "días")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(taken ? "¡Tomado hoy!" : "Pendiente")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(taken ? kind.color : .secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScrollView {
        SupplementsTodayCard()
            .padding()
    }
    .modelContainer(PreviewData.container)
}
