//
//  GymSessionView.swift
//  Maraton
//
//  Sesión de gimnasio de un día de fuerza: ejercicios, series, peso y reps.
//

import SwiftUI
import SwiftData

struct GymSessionView: View {
    @Bindable var day: WorkoutDay
    @Environment(\.modelContext) private var context

    @State private var showingAddExercise = false
    @State private var newExerciseName = ""
    @State private var showingGuidedSession = false

    var body: some View {
        List {
            if day.orderedExercises.isEmpty {
                emptyState
            } else {
                Section {
                    Button {
                        showingGuidedSession = true
                    } label: {
                        Label("Empezar sesión guiada", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(WorkoutType.fuerza.color)
                }
            }

            ForEach(day.orderedExercises) { exercise in
                ExerciseSection(exercise: exercise) {
                    eliminar(exercise)
                }
            }

            Section {
                Button {
                    newExerciseName = ""
                    showingAddExercise = true
                } label: {
                    Label("Agregar ejercicio", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Rutina")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Nuevo ejercicio", isPresented: $showingAddExercise) {
            TextField("Nombre (ej. Press banca)", text: $newExerciseName)
            Button("Agregar") { agregarEjercicio() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ingresá el nombre del ejercicio.")
        }
        .fullScreenCover(isPresented: $showingGuidedSession) {
            GuidedGymSessionView(day: day)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Todavía no hay ejercicios")
                .font(.headline)
            Text("Agregá tu primer ejercicio para empezar a registrar series, peso y repeticiones.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }

    // MARK: - Acciones

    private func agregarEjercicio() {
        let nombre = newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else { return }
        let exercise = Exercise(
            name: nombre,
            order: day.orderedExercises.count,
            dayDate: day.date,
            day: day
        )
        context.insert(exercise)
        // Arranca con una serie vacía para agilizar la carga.
        let primeraSerie = ExerciseSet(order: 1, exercise: exercise)
        context.insert(primeraSerie)
        try? context.save()
    }

    private func eliminar(_ exercise: Exercise) {
        context.delete(exercise)
        try? context.save()
    }
}

// MARK: - Sección de un ejercicio

private struct ExerciseSection: View {
    @Bindable var exercise: Exercise
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var lastSession: String?
    @State private var showingRename = false
    @State private var renameText = ""

    var body: some View {
        Section {
            ForEach(exercise.orderedSets) { set in
                SetRow(set: set, index: set.order, exercise: exercise)
            }
            .onDelete(perform: eliminarSeries)

            Button {
                agregarSerie()
            } label: {
                Label("Agregar serie", systemImage: "plus")
                    .font(.subheadline)
            }
        } header: {
            header
        } footer: {
            if let lastSession {
                Label("Última vez: \(lastSession)", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
        }
        .onAppear(perform: cargarHistorico)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseThumbnail(imageName: exercise.imageName)
            VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise.name)
                    .font(.headline)
                    .textCase(nil)
                Spacer()
                Menu {
                    Button {
                        renameText = exercise.name
                        showingRename = true
                    } label: {
                        Label("Renombrar", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Eliminar ejercicio", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            if let target = exercise.targetReps {
                Text("Objetivo: \(target)\(exercise.isTimeBased ? "" : " reps")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WorkoutType.fuerza.color)
                    .textCase(nil)
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            }
        }
        .alert("Renombrar ejercicio", isPresented: $showingRename) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                let nuevo = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nuevo.isEmpty {
                    exercise.name = nuevo
                    try? context.save()
                    cargarHistorico()
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func cargarHistorico() {
        lastSession = ExerciseHistory.lastSession(
            name: exercise.name,
            before: exercise.dayDate,
            context: context
        )
    }

    private func agregarSerie() {
        let ultima = exercise.orderedSets.last
        let nueva = ExerciseSet(
            order: (exercise.orderedSets.last?.order ?? 0) + 1,
            weight: ultima?.weight, // sugiere el peso de la serie anterior
            exercise: exercise
        )
        context.insert(nueva)
        try? context.save()
    }

    private func eliminarSeries(at offsets: IndexSet) {
        let ordenadas = exercise.orderedSets
        for index in offsets {
            context.delete(ordenadas[index])
        }
        try? context.save()
    }
}

// MARK: - Fila de una serie

private struct SetRow: View {
    @Bindable var set: ExerciseSet
    let index: Int
    let exercise: Exercise

    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Text("Serie \(index)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            if exercise.tracksWeight {
                WeightWheelField(weight: $set.weight, onCommit: save)
            }

            CountWheelField(
                count: $set.reps,
                unit: exercise.countUnit,
                options: ExerciseInput.countOptions(timeBased: exercise.isTimeBased),
                defaultValue: ExerciseInput.leadingInt(exercise.targetReps) ?? (exercise.isTimeBased ? 30 : 10),
                placeholder: exercise.isTimeBased ? "Tiempo" : "Reps",
                onCommit: save
            )

            Button {
                set.isDone.toggle()
                save()
            } label: {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(set.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func save() { try? context.save() }
}

// MARK: - Miniatura de la foto del ejercicio

/// Muestra la foto del ejercicio (asset `imageName`). Si no hay imagen, dibuja
/// un marcador con el ícono de mancuerna. Compartida con la sesión guiada.
struct ExerciseThumbnail: View {
    let imageName: String?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Campos de selección por rueda (estilo alarma)

/// Opciones para los selectores de conteo (reps / segundos).
enum ExerciseInput {
    static let repOptions = Array(1...50)
    static let secondOptions = Array(stride(from: 5, through: 180, by: 5))

    static func countOptions(timeBased: Bool) -> [Int] {
        timeBased ? secondOptions : repOptions
    }

    /// Primer número de un objetivo (ej. "6-8" → 6, "30 s" → 30).
    static func leadingInt(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Int(text.prefix { $0.isNumber })
    }
}

/// Chip que muestra el valor elegido (o un placeholder) con un ícono de rueda.
private struct WheelChip: View {
    let text: String?
    let placeholder: String
    var prominent: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(text ?? placeholder)
                .foregroundStyle(text == nil ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(prominent ? .title3.weight(.semibold) : .subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, prominent ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: prominent ? 12 : 8)
                .fill(Color(.tertiarySystemFill))
        )
        .contentShape(Rectangle())
    }
}

/// Campo de peso: muestra el valor y, al tocarlo, abre una hoja con dos ruedas
/// (kilos enteros y fracción) para elegirlo deslizando, sin teclado.
struct WeightWheelField: View {
    @Binding var weight: Double?
    var prominent = false
    var onCommit: () -> Void = {}

    @State private var showing = false
    @State private var whole = 20
    @State private var fraction = 0.0

    private static let wholeRange = Array(0...250)
    private static let fractions: [Double] = [0, 0.25, 0.5, 0.75]

    var body: some View {
        Button {
            prepare()
            showing = true
        } label: {
            WheelChip(text: weight.map { "\($0.formattedKg) kg" }, placeholder: "Peso", prominent: prominent)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            NavigationStack {
                HStack(spacing: 0) {
                    Picker("kg", selection: $whole) {
                        ForEach(Self.wholeRange, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("fracción", selection: $fraction) {
                        ForEach(Self.fractions, id: \.self) { Text(fractionLabel($0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 90)

                    Text("kg")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
                .padding(.horizontal)
                .navigationTitle("Peso")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") {
                            weight = Double(whole) + fraction
                            onCommit()
                            showing = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    private func prepare() {
        let value = weight ?? 20
        whole = min(max(Int(value), 0), Self.wholeRange.last ?? 250)
        let frac = value - Double(Int(value))
        fraction = Self.fractions.min(by: { abs($0 - frac) < abs($1 - frac) }) ?? 0
    }

    private func fractionLabel(_ f: Double) -> String {
        switch f {
        case 0.25: return ",25"
        case 0.5:  return ",50"
        case 0.75: return ",75"
        default:   return ",00"
        }
    }
}

/// Campo de conteo (reps o segundos): muestra el valor y abre una hoja con una
/// rueda para elegirlo deslizando, sin teclado.
struct CountWheelField: View {
    @Binding var count: Int?
    var unit: String = "reps"
    var options: [Int] = ExerciseInput.repOptions
    var defaultValue: Int = 10
    var placeholder: String = "Reps"
    var prominent = false
    var onCommit: () -> Void = {}

    @State private var showing = false
    @State private var draft = 0

    var body: some View {
        Button {
            draft = count ?? clampedDefault()
            showing = true
        } label: {
            WheelChip(text: count.map { "\($0) \(unit)" }, placeholder: placeholder, prominent: prominent)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            NavigationStack {
                HStack(spacing: 0) {
                    Picker(unit, selection: $draft) {
                        ForEach(options, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60)
                }
                .padding(.horizontal)
                .navigationTitle(unit == "seg" ? "Segundos" : "Repeticiones")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") {
                            count = draft
                            onCommit()
                            showing = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    private func clampedDefault() -> Int {
        if options.contains(defaultValue) { return defaultValue }
        return options.min(by: { abs($0 - defaultValue) < abs($1 - defaultValue) }) ?? options.first ?? 0
    }
}

#Preview {
    NavigationStack {
        GymSessionView(day: WorkoutSeed.allWorkoutDays().first { $0.type == .fuerza }!)
    }
    .modelContainer(PreviewData.container)
}
