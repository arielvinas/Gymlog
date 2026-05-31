//
//  WorkoutDetailView.swift
//  Maraton
//
//  Detalle de un día del plan, con opción de marcarlo como completado.
//

import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Bindable var day: WorkoutDay
    @Environment(\.modelContext) private var context

    @State private var showingForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                description

                if day.type == .fuerza {
                    gymLink
                }

                if day.isCompleted {
                    completedSummary
                }

                actionButton
            }
            .padding()
        }
        .navigationTitle(day.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingForm) {
            CompletionFormView(day: day)
        }
    }

    // MARK: - Secciones

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: day.type.symbolName)
                    .foregroundStyle(day.type.color)
                Text(day.type.displayName.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(day.type.color)
            }

            Text(day.title)
                .font(.title2)
                .fontWeight(.bold)

            if !day.detail.isEmpty {
                Text(day.detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(day.date.longDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var gymLink: some View {
        NavigationLink {
            GymSessionView(day: day)
        } label: {
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(WorkoutType.fuerza.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rutina de gimnasio")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(day.exercises.isEmpty
                         ? "Cargá tus ejercicios y series"
                         : "\(day.exercises.count) ejercicio\(day.exercises.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(WorkoutType.fuerza.color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cómo encararlo")
                .font(.headline)
            Text(day.longDescription)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var completedSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Completado", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if day.type.isRun {
                if let km = day.actualKm {
                    summaryRow(label: "Distancia", value: "\(km.formattedKm) km")
                }
                if let minutes = day.durationMinutes {
                    summaryRow(label: "Duración", value: "\(minutes) min")
                }
                if let effort = day.perceivedEffort {
                    summaryRow(label: "Esfuerzo", value: "\(effort)/10")
                }
            }
            if let notes = day.notes, !notes.isEmpty {
                summaryRow(label: "Notas", value: notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.12))
        )
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var actionButton: some View {
        if day.isCompleted {
            Button(role: .destructive) {
                desmarcar()
            } label: {
                Label("Desmarcar", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                completar()
            } label: {
                Label("Marcar como completado", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Acciones

    private func completar() {
        // Las corridas abren el formulario de registro; el resto se marca directo.
        if day.type.isRun {
            showingForm = true
        } else {
            day.isCompleted = true
            try? context.save()
        }
    }

    private func desmarcar() {
        day.isCompleted = false
        day.actualKm = nil
        day.durationMinutes = nil
        day.perceivedEffort = nil
        day.notes = nil
        try? context.save()
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(day: WorkoutSeed.allWorkoutDays()[1])
    }
    .modelContainer(PreviewData.container)
}
