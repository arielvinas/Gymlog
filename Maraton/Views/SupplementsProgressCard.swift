//
//  SupplementsProgressCard.swift
//  Maraton
//
//  Adherencia semanal/mensual y rachas de suplementos en el dashboard.
//

import SwiftUI
import SwiftData

struct SupplementsProgressCard: View {
    @Query(sort: \SupplementLog.date) private var logs: [SupplementLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Suplementos", systemImage: "pills.fill", tint: .teal)

            ForEach(Array(SupplementKind.allCases.enumerated()), id: \.element) { index, kind in
                supplementBlock(kind)
                if index < SupplementKind.allCases.count - 1 {
                    Divider()
                }
            }
        }
        .dashboardCard()
    }

    private func supplementBlock(_ kind: SupplementKind) -> some View {
        let streak = SupplementTracker.currentStreak(kind, logs: logs)
        let semana = SupplementTracker.adherence(kind, lastDays: 7, logs: logs)
        let mes = SupplementTracker.adherence(kind, lastDays: 30, logs: logs)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(kind.displayName, systemImage: kind.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kind.color)
                Spacer()
                if streak > 0 {
                    Text("🔥 \(streak) \(streak == 1 ? "día" : "días")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                adherenceBar(title: "7 días", value: semana, tint: kind.color)
                adherenceBar(title: "30 días", value: mes, tint: kind.color)
            }
        }
    }

    private func adherenceBar(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: value)
                .tint(tint)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ScrollView {
        SupplementsProgressCard()
            .padding()
    }
    .modelContainer(PreviewData.container)
}
