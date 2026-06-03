//
//  WatchRootView.swift
//  MaratonWatch Watch App
//
//  Pantalla principal del reloj: muestra el día de gimnasio de hoy (o el
//  próximo día de fuerza) y un botón grande para empezar la sesión guiada.
//

import SwiftUI
import SwiftData

struct WatchRootView: View {
    @Query(sort: \WorkoutDay.date) private var days: [WorkoutDay]

    private var tint: Color { WorkoutType.fuerza.color }

    /// Día de fuerza de hoy; si no hay, el próximo día de fuerza desde hoy.
    private var gymDay: WorkoutDay? {
        let cal = Calendar.current
        if let today = days.first(where: { cal.isDateInToday($0.date) && $0.type == .fuerza }) {
            return today
        }
        let start = cal.startOfDay(for: Date())
        return days.first { $0.type == .fuerza && $0.date >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let day = gymDay {
                    gymCard(day)
                } else {
                    noGymState
                }
            }
            .navigationTitle("Maratón")
        }
        .tint(tint)
    }

    private func gymCard(_ day: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(esHoy(day) ? "Hoy" : day.date.weekdayAndDay, systemImage: "dumbbell.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(day.title)
                .font(.headline)

            if !day.detail.isEmpty {
                Text(day.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(day.exercises.count) ejercicio\(day.exercises.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)

            NavigationLink {
                WatchGuidedSessionView(day: day)
            } label: {
                Label("Empezar", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(day.exercises.isEmpty)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tint.opacity(0.18))
        )
        .padding(.horizontal, 2)
    }

    private var noGymState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No hay días de gimnasio próximos")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func esHoy(_ day: WorkoutDay) -> Bool {
        Calendar.current.isDateInToday(day.date)
    }
}
