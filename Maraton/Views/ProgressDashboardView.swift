//
//  ProgressDashboardView.swift
//  Maraton
//
//  Pantalla de progreso: cuenta regresiva, km acumulados y días completados.
//

import SwiftUI
import SwiftData

struct ProgressDashboardView: View {
    @Query private var days: [WorkoutDay]

    /// Días restantes hasta la carrera (mínimo 0).
    private var daysToRace: Int {
        let cal = PlanConstants.calendar
        let today = cal.startOfDay(for: Date())
        let race = cal.startOfDay(for: PlanConstants.raceDate)
        let diff = cal.dateComponents([.day], from: today, to: race).day ?? 0
        return max(diff, 0)
    }

    /// Suma de kilómetros reales registrados en días completados.
    private var totalKm: Double {
        days.compactMap { $0.isCompleted ? $0.actualKm : nil }.reduce(0, +)
    }

    private var completedCount: Int {
        days.filter { $0.isCompleted }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    countdownCard

                    HStack(spacing: 16) {
                        StatCard(
                            title: "Km corridos",
                            value: totalKm.formattedKm,
                            unit: "km",
                            symbol: "figure.run",
                            color: .blue
                        )
                        StatCard(
                            title: "Completados",
                            value: "\(completedCount)",
                            unit: "de \(days.count)",
                            symbol: "checkmark.seal.fill",
                            color: .green
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Progreso")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var countdownCard: some View {
        VStack(spacing: 8) {
            Text("Faltan para la carrera")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Text("\(daysToRace)")
                .font(.system(size: 80, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text(daysToRace == 1 ? "día" : "días")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.9))

            Text("Media Maratón Córdoba · \(PlanConstants.raceDistanceKm.formattedKm) km")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Tarjeta de estadística

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    ProgressDashboardView()
        .modelContainer(PreviewData.container)
}
