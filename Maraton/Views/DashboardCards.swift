//
//  DashboardCards.swift
//  Maraton
//
//  Tarjetas de progreso: preparación, consistencia, proyección y fuerza.
//

import SwiftUI

// MARK: - P4: Consistencia

struct ConsistencyCard: View {
    let weekStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Consistencia", systemImage: "flame.fill", tint: .orange)

            if weekStreak > 0 {
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(weekStreak) \(weekStreak == 1 ? "semana" : "semanas") consecutivas")
                            .font(.title3.weight(.bold))
                        Text("Con al menos un entrenamiento completado.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Completá un entrenamiento esta semana para arrancar tu racha.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }
}

// MARK: - P3: Tendencia de volumen

struct VolumeTrendCard: View {
    let weeks: [WeekVolume]

    private var maxKm: Double { max(weeks.map(\.runKm).max() ?? 0, 1) }
    private var maxTonnage: Double { max(weeks.map(\.tonnage).max() ?? 0, 1) }
    private var hasData: Bool { weeks.contains { $0.runKm > 0 || $0.tonnage > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Volumen por semana", systemImage: "chart.bar.fill", tint: .blue)

            if hasData {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(weeks) { week in
                        weekColumn(week)
                    }
                }

                HStack(spacing: 14) {
                    legend(color: .blue, text: "km corridos")
                    legend(color: .purple, text: "kg levantados")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("Registrá corridas o series de gimnasio para ver tu volumen semanal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }

    /// Una semana: dos barras (corrida y gimnasio) escaladas a su propio máximo,
    /// porque km y kg no son comparables entre sí.
    private func weekColumn(_ week: WeekVolume) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                bar(fraction: week.runKm / maxKm, color: .blue)
                bar(fraction: week.tonnage / maxTonnage, color: .purple)
            }
            .frame(height: 70)

            Text(week.weekStart.dayMonth)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(fraction: Double, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.gradient)
            .frame(width: 10, height: max(2, 70 * fraction))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

// MARK: - P6: Evolución de fuerza

struct StrengthEvolutionCard: View {
    let improvements: [ExerciseImprovement]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Evolución de fuerza", systemImage: "dumbbell.fill", tint: .purple)

            if improvements.isEmpty {
                Text("Registrá al menos dos sesiones del mismo ejercicio para ver tu progreso.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(improvements) { item in
                    improvementRow(item)
                    if item.id != improvements.last?.id {
                        Divider()
                    }
                }
            }
        }
        .dashboardCard()
    }

    private func improvementRow(_ item: ExerciseImprovement) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(item.previous.text)  →  \(item.last.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(changeText(item.percentChange))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(changeColor(item.percentChange))
        }
    }

    private func changeText(_ value: Double) -> String {
        let signo = value > 0 ? "+" : ""
        return "\(signo)\(String(format: "%.1f", value))%"
    }

    private func changeColor(_ value: Double) -> Color {
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }
}
