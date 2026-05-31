//
//  LastRunCard.swift
//  Maraton
//
//  Resumen de la última corrida registrada (distancia, ritmo y pulsaciones
//  promedio, estas últimas importadas de Apple Salud).
//

import SwiftUI

struct LastRunCard: View {
    let run: WorkoutDay

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Última corrida · \(run.date.weekdayName)",
                       systemImage: "clock.arrow.circlepath", tint: .blue)

            HStack(spacing: 12) {
                metric(value: distance, label: "distancia")
                metric(value: pace, label: "min/km")
                metric(value: heartRate, label: "ppm prom.")
            }
        }
        .dashboardCard()
    }

    private var distance: String {
        guard let km = run.actualKm else { return "—" }
        return "\(km.formattedKm) km"
    }

    private var pace: String {
        guard let secPerKm = run.paceSecondsPerKm else { return "—" }
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var heartRate: String {
        guard let hr = run.avgHeartRate else { return "—" }
        return "\(Int(hr.rounded()))"
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
