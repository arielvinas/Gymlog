//
//  DashboardCards.swift
//  Maraton
//
//  Tarjetas de progreso: preparación, consistencia, proyección y fuerza.
//

import SwiftUI

// MARK: - P2: Preparación para Córdoba

struct ReadinessCard: View {
    let readiness: Readiness

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardHeader(title: "Preparación para Córdoba", systemImage: "target", tint: .red)
                Spacer()
                Text("\(readiness.status.emoji) \(readiness.status.label)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readiness.status.color)
            }

            ProgressView(value: readiness.adherence) {
                HStack {
                    Text("Adherencia al plan")
                    Spacer()
                    Text("\(Int((readiness.adherence * 100).rounded()))%")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
            .tint(readiness.status.color)

            HStack(spacing: 12) {
                metric(value: "\(readiness.completedCount)/\(readiness.dueCount)", label: "Hechos")
                metric(value: readiness.longestFondoKm.map { "\($0.formattedKm) km" } ?? "—", label: "Fondo máx.")
                metric(value: "\(readiness.activeWeeks)", label: "Semanas activas")
            }
        }
        .dashboardCard()
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

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

// MARK: - P3: Proyección actual

struct ProjectionCard: View {
    let projection: RaceProjection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Proyección actual", systemImage: "chart.line.uptrend.xyaxis", tint: .blue)

            if let projection {
                HStack(spacing: 12) {
                    projectionBox(distance: "10 km", time: projection.time10kSeconds.formattedRaceTime)
                    projectionBox(distance: "21,1 km", time: projection.timeHalfSeconds.formattedRaceTime)
                }

                Text("Estimado según tu ritmo de \(projection.basePaceSecPerKm.formattedPace). Es una referencia, no una predicción exacta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Completá algunas corridas con distancia y duración para ver tu proyección.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }

    private func projectionBox(distance: String, time: String) -> some View {
        VStack(spacing: 4) {
            Text(distance)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(time)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill))
        )
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
