//
//  WorkoutEditView.swift
//  Maraton
//
//  Crear o editar un día del plan.
//

import SwiftUI
import SwiftData

struct WorkoutEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutDay.date) private var days: [WorkoutDay]

    /// Día a editar; `nil` para crear uno nuevo.
    let editing: WorkoutDay?

    @State private var date = Date()
    @State private var type: WorkoutType = .rodaje
    @State private var title = ""
    @State private var detail = ""
    @State private var longDescription = ""
    @State private var validationError: String?

    private var isCreating: Bool { editing == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fecha y tipo") {
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_AR"))
                    Picker("Tipo", selection: $type) {
                        ForEach(WorkoutType.allCases) { t in
                            Label(t.displayName, systemImage: t.symbolName).tag(t)
                        }
                    }
                }

                Section("Entrenamiento") {
                    TextField("Título (ej. Fondo largo 14 km)", text: $title)
                    TextField("Detalle (ej. Z2 conversacional)", text: $detail)
                }

                Section("Descripción") {
                    TextField("Cómo encararlo", text: $longDescription, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isCreating ? "Nuevo día" : "Editar día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: cargar)
            .alert("No se pudo guardar", isPresented: .constant(validationError != nil)) {
                Button("Entendido") { validationError = nil }
            } message: {
                Text(validationError ?? "")
            }
        }
    }

    private func cargar() {
        guard let editing else { return }
        date = editing.date
        type = editing.type
        title = editing.title
        detail = editing.detail
        longDescription = editing.longDescription
    }

    private func guardar() {
        let cal = PlanConstants.calendar
        let nuevoInicio = cal.startOfDay(for: date)

        // Validación: no puede haber otro día en la misma fecha.
        let chocaConOtro = days.contains { otro in
            otro.persistentModelID != editing?.persistentModelID &&
            cal.isDate(otro.date, inSameDayAs: nuevoInicio)
        }
        if chocaConOtro {
            validationError = "Ya existe un entrenamiento en esa fecha. Elegí otra o editá el existente."
            return
        }

        let tituloLimpio = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detalleLimpio = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let descripcionLimpia = longDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing {
            editing.date = date
            editing.type = type
            editing.title = tituloLimpio
            editing.detail = detalleLimpio
            editing.longDescription = descripcionLimpia
            // Reasigna la semana por si cambió la fecha.
            let info = WeekAssigner.weekInfo(for: date, among: days.filter { $0.persistentModelID != editing.persistentModelID })
            editing.weekTitle = info.title
            editing.weekTag = info.tag
            editing.weekOrder = info.order
        } else {
            let info = WeekAssigner.weekInfo(for: date, among: days)
            let nuevo = WorkoutDay(
                date: date,
                title: tituloLimpio,
                detail: detalleLimpio,
                longDescription: descripcionLimpia,
                type: type,
                weekTitle: info.title,
                weekTag: info.tag,
                weekOrder: info.order
            )
            context.insert(nuevo)
        }

        try? context.save()
        dismiss()
    }
}

#Preview {
    WorkoutEditView(editing: nil)
        .modelContainer(PreviewData.container)
}
