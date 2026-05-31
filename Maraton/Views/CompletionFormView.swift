//
//  CompletionFormView.swift
//  Maraton
//
//  Formulario para registrar los datos de una corrida al completarla.
//

import SwiftUI
import SwiftData

struct CompletionFormView: View {
    @Bindable var day: WorkoutDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kmText: String = ""
    @State private var minutesText: String = ""
    @State private var effort: Double = 5
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Registro de la corrida") {
                    LabeledContent("Kilómetros") {
                        TextField("0", text: $kmText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Duración (min)") {
                        TextField("0", text: $minutesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Esfuerzo percibido: \(Int(effort))/10") {
                    Slider(value: $effort, in: 1...10, step: 1)
                }

                Section("Notas") {
                    TextField("¿Cómo te sentiste?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Completar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                }
            }
            .onAppear(perform: cargarValoresExistentes)
        }
    }

    private func cargarValoresExistentes() {
        if let km = day.actualKm { kmText = km.formattedKm }
        if let minutes = day.durationMinutes { minutesText = "\(minutes)" }
        if let e = day.perceivedEffort { effort = Double(e) }
        if let n = day.notes { notes = n }
    }

    private func guardar() {
        // Acepta coma o punto como separador decimal.
        let normalizedKm = kmText.replacingOccurrences(of: ",", with: ".")
        day.actualKm = Double(normalizedKm)
        day.durationMinutes = Int(minutesText)
        day.perceivedEffort = Int(effort)
        day.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        day.isCompleted = true
        try? context.save()
        dismiss()
    }
}

#Preview {
    CompletionFormView(day: WorkoutSeed.allWorkoutDays()[1])
        .modelContainer(PreviewData.container)
}
