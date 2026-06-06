//
//  SupplementsTodayCard.swift
//  Maraton
//
//  Marcado rápido de suplementos del día (un tap por suplemento).
//

import SwiftUI
import SwiftData

struct SupplementsTodayCard: View {
    /// Día sobre el que se registran los suplementos (por defecto, hoy).
    var date: Date = Date()

    @Environment(\.modelContext) private var context
    @Query(sort: \SupplementLog.date) private var logs: [SupplementLog]

    private var isToday: Bool {
        PlanConstants.calendar.isDate(date, inSameDayAs: Date())
    }

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
                    taken: SupplementTracker.isTaken(kind, on: date, logs: logs),
                    streak: isToday ? SupplementTracker.currentStreak(kind, logs: logs) : 0,
                    isToday: isToday
                ) {
                    SupplementTracker.toggle(kind, on: date, logs: logs, context: context)
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
    var isToday: Bool = true
    var onToggle: () -> Void

    /// Subtítulo según el día: racha y "hoy" para el día actual; tomado/sin
    /// registrar para días pasados.
    private var subtitle: String {
        guard isToday else { return taken ? "Tomado" : "Sin registrar" }
        if streak > 0 { return "🔥 \(streak) \(streak == 1 ? "día" : "días")" }
        return taken ? "¡Tomado hoy!" : "Pendiente"
    }

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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
