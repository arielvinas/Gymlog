//
//  CompletionFormView.swift
//  Maraton
//
//  Formulario para registrar los datos de una corrida al completarla.
//  Permite importar las métricas desde Apple Salud.
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
    @State private var hrText: String = ""
    @State private var calText: String = ""

    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                if HealthManager.isHealthAvailable {
                    Section {
                        Button {
                            Task { await importarDeSalud() }
                        } label: {
                            HStack {
                                Label("Importar de Apple Salud", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isImporting)
                    } footer: {
                        Text("Trae distancia, duración, frecuencia cardíaca y calorías del entrenamiento de tu Apple Watch.")
                    }
                }

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
                    if let pace = paceCalculado {
                        LabeledContent("Ritmo", value: pace)
                    }
                }

                Section("Métricas (Apple Salud)") {
                    LabeledContent("Frec. cardíaca (bpm)") {
                        TextField("—", text: $hrText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Calorías (kcal)") {
                        TextField("—", text: $calText)
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
            .alert("Apple Salud", isPresented: .constant(importError != nil)) {
                Button("Entendido") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    /// Ritmo calculado en vivo a partir de los km y minutos cargados.
    private var paceCalculado: String? {
        let km = Double(kmText.replacingOccurrences(of: ",", with: "."))
        let minutes = Int(minutesText)
        guard let km, km > 0, let minutes, minutes > 0 else { return nil }
        return ((Double(minutes) * 60.0) / km).formattedPace
    }

    private func cargarValoresExistentes() {
        if let km = day.actualKm { kmText = km.formattedKm }
        if let minutes = day.durationMinutes { minutesText = "\(minutes)" }
        if let e = day.perceivedEffort { effort = Double(e) }
        if let n = day.notes { notes = n }
        if let hr = day.avgHeartRate { hrText = "\(Int(hr))" }
        if let cal = day.activeCalories { calText = "\(Int(cal))" }
    }

    private func importarDeSalud() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let data = try await HealthManager.shared.importRun(for: day.date)
            if let km = data.km { kmText = km.formattedKm }
            if let minutes = data.minutes { minutesText = "\(minutes)" }
            if let hr = data.avgHeartRate { hrText = "\(Int(hr.rounded()))" }
            if let cal = data.activeCalories { calText = "\(Int(cal.rounded()))" }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func guardar() {
        let normalizedKm = kmText.replacingOccurrences(of: ",", with: ".")
        day.actualKm = Double(normalizedKm)
        day.durationMinutes = Int(minutesText)
        day.perceivedEffort = Int(effort)
        day.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        day.avgHeartRate = Double(hrText)
        day.activeCalories = Double(calText)
        day.isCompleted = true
        try? context.save()
        dismiss()
    }
}

#Preview {
    CompletionFormView(day: WorkoutSeed.allWorkoutDays()[1])
        .modelContainer(PreviewData.container)
}
