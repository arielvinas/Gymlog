//
//  WatchWorkoutView.swift
//  MaratonWatch Watch App
//
//  Detalle del entrenamiento de un día en el reloj. Para los días de fuerza
//  ofrece el botón "Empezar" que abre la sesión guiada; para el resto muestra
//  la info del día. Si ya se completó, muestra el resumen guardado.
//

import SwiftUI
import SwiftData

struct WatchWorkoutView: View {
    let day: WorkoutDay

    private var tint: Color { day.type.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label(day.type.displayName, systemImage: day.type.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(day.title)
                    .font(.headline)

                if !day.detail.isEmpty {
                    Text(day.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: day.dailyStatus.symbolName)
                    Text(day.dailyStatus.label)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(day.dailyStatus.color)

                if day.type == .fuerza {
                    gymAction
                }

                if day.isCompleted {
                    completedSummary
                }

                if !day.longDescription.isEmpty {
                    Text(day.longDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Hoy")
    }

    @ViewBuilder
    private var gymAction: some View {
        if day.exercises.isEmpty {
            Label("Sin ejercicios cargados", systemImage: "dumbbell")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            NavigationLink {
                WatchGuidedSessionView(day: day)
            } label: {
                Label(day.isCompleted ? "Repetir sesión" : "Empezar", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var completedSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Completado", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            if let hr = day.avgHeartRate {
                summaryLine("Pulso prom.", "\(Int(hr)) bpm")
            }
            if let cal = day.activeCalories {
                summaryLine("Calorías", "\(Int(cal)) kcal")
            }
            if let minutes = day.durationMinutes {
                summaryLine("Duración", "\(minutes) min")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.15)))
    }

    private func summaryLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.caption2)
    }
}
