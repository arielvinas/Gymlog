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
            if day.exercises.isEmpty {
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
            order: day.exercises.count,
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
                SetRow(set: set, index: set.order, targetReps: exercise.targetReps)
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
                Text("Objetivo: \(target) reps")
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
    var targetReps: String?

    @Environment(\.modelContext) private var context
    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack(spacing: 12) {
            Text("Serie \(index)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            field(placeholder: "kg", text: $weightText, keyboard: .decimalPad)
                .onChange(of: weightText) { _, nuevo in
                    set.weight = Double(nuevo.replacingOccurrences(of: ",", with: "."))
                }
            Text("kg")
                .font(.caption)
                .foregroundStyle(.secondary)

            field(placeholder: targetReps ?? "reps", text: $repsText, keyboard: .numberPad)
                .onChange(of: repsText) { _, nuevo in
                    set.reps = Int(nuevo)
                }

            Button {
                set.isDone.toggle()
                try? context.save()
            } label: {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(set.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            if let w = set.weight { weightText = w.formattedKg }
            if let r = set.reps { repsText = "\(r)" }
        }
    }

    private func field(placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
            )
    }
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

#Preview {
    NavigationStack {
        GymSessionView(day: WorkoutSeed.allWorkoutDays().first { $0.type == .fuerza }!)
    }
    .modelContainer(PreviewData.container)
}
