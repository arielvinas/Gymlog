//
//  GuidedGymSessionView.swift
//  Maraton
//
//  Modo guiado de la sesión de gimnasio (iPhone). La máquina de estados vive en
//  `GuidedSessionEngine` (compartida con la app del reloj); esta vista solo la
//  dibuja y conecta el aviso de fin de descanso (sonido + vibración) y la
//  notificación local de respaldo.
//

import SwiftUI
import SwiftData
import AudioToolbox
import Combine

struct GuidedGymSessionView: View {
    @Bindable var day: WorkoutDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var engine = GuidedSessionEngine()
    @State private var showingQuitConfirm = false

    /// Tic del cronómetro (frecuente para que el anillo se vea fluido).
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var tint: Color { WorkoutType.fuerza.color }

    var body: some View {
        NavigationStack {
            Group {
                if engine.steps.isEmpty {
                    emptyState
                } else {
                    switch engine.phase {
                    case .logging: loggingScreen
                    case .resting: restingScreen
                    case .done:    doneScreen
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if engine.phase == .done {
                            dismiss()
                        } else {
                            showingQuitConfirm = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .principal) {
                    if let step = engine.currentStep, engine.phase != .done {
                        Text("Ejercicio \(step.exerciseIndex + 1) de \(step.exerciseCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog(
                "¿Salir de la sesión guiada?",
                isPresented: $showingQuitConfirm,
                titleVisibility: .visible
            ) {
                Button("Salir", role: .destructive) { dismiss() }
                Button("Seguir entrenando", role: .cancel) {}
            } message: {
                Text("Lo que cargaste hasta ahora queda guardado.")
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: start)
        .onDisappear(perform: cleanup)
        .onReceive(ticker) { engine.tickRest(now: $0) }
    }

    // MARK: - Pantalla de carga de serie

    @ViewBuilder
    private var loggingScreen: some View {
        if let step = engine.currentStep {
            VStack(spacing: 0) {
                progressBar

                ScrollView {
                    VStack(spacing: 16) {
                        if let imageName = step.exercise.imageName, UIImage(named: imageName) != nil {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        exerciseCard(step)

                        if let set = step.set {
                            LoggingCard(
                                exercise: step.exercise,
                                set: set,
                                tint: tint,
                                suggestedWeight: engine.suggestedWeight(for: step)
                            )
                            .id(step.id)
                        }
                    }
                    .padding()
                }

                bottomBar(
                    backAction: engine.goBackFromLogging,
                    backEnabled: engine.index > 0,
                    primaryTitle: step.set != nil ? "Completar serie" : "Marcar como hecho",
                    primaryIcon: "checkmark.circle.fill",
                    primaryAction: engine.completeCurrent
                )
            }
        }
    }

    private func exerciseCard(_ step: GuidedStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.exercise.name)
                .font(.title2.weight(.bold))

            if step.set != nil {
                Text("Serie \(step.setNumber) de \(step.setCount)")
                    .font(.headline)
                    .foregroundStyle(tint)
            }

            HStack(spacing: 16) {
                if let target = step.exercise.targetReps {
                    Label("\(target) reps", systemImage: "target")
                }
                Label(step.exercise.restOrDefault.restLabel, systemImage: "timer")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let notes = step.exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tint.opacity(0.12))
        )
    }

    // MARK: - Pantalla de descanso

    private var restingScreen: some View {
        let overtime = engine.isRestOvertime
        return VStack(spacing: 0) {
            progressBar

            Spacer()

            Text(overtime ? "Tiempo extra" : "Descanso")
                .font(.headline)
                .foregroundStyle(overtime ? Color.red : .secondary)

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: overtime ? 1 : engine.restFraction)
                    .stroke(overtime ? Color.red : tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: engine.restRemaining)

                VStack(spacing: 4) {
                    Text(overtime ? "+\(engine.restOvertime.countdownLabel)" : engine.restRemaining.countdownLabel)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(overtime ? Color.red : .primary)
                    Text(overtime ? "tocá para empezar la serie" : "de \(engine.restTotal.restLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 230, height: 230)
            .padding(.vertical, 24)

            HStack(spacing: 12) {
                Button { engine.adjustRest(by: -15) } label: {
                    Label("15 s", systemImage: "minus")
                        .frame(maxWidth: .infinity)
                }
                Button { engine.adjustRest(by: 15) } label: {
                    Label("15 s", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 40)

            if let next = engine.nextStep {
                Text("Sigue: \(preview(of: next))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .padding(.horizontal)
            }

            Spacer()

            bottomBar(
                backAction: engine.goBackFromResting,
                backEnabled: true,
                primaryTitle: overtime ? "Empezar serie" : "Saltear descanso",
                primaryIcon: overtime ? "play.fill" : "forward.fill",
                primaryAction: engine.skipRest
            )
        }
    }

    private func preview(of step: GuidedStep) -> String {
        if step.set != nil {
            return "\(step.exercise.name) · serie \(step.setNumber) de \(step.setCount)"
        }
        return step.exercise.name
    }

    // MARK: - Pantalla final

    private var doneScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("¡Sesión completa!")
                .font(.title.weight(.bold))

            Text("Guardamos tus pesos y repeticiones.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                summaryRow("Ejercicios", "\(engine.exerciseCount)")
                summaryRow("Series cargadas", "\(engine.loggedSetsCount)")
                if engine.totalVolume > 0 {
                    summaryRow("Volumen total", "\(engine.totalVolume.formattedKg) kg")
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal)

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Listo", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)
            .padding()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    // MARK: - Piezas compartidas

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * engine.progressFraction)
                    .animation(.easeInOut, value: engine.progressFraction)
            }
        }
        .frame(height: 6)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func bottomBar(
        backAction: @escaping () -> Void,
        backEnabled: Bool,
        primaryTitle: String,
        primaryIcon: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: backAction) {
                Label("Anterior", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!backEnabled)

            Button(action: primaryAction) {
                Label(primaryTitle, systemImage: primaryIcon)
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)
        }
        .padding()
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No hay ejercicios para guiar")
                .font(.headline)
            Button("Cerrar") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Ciclo de vida

    private func start() {
        // Conecta los avisos de descanso a las capacidades del iPhone.
        engine.onRestStarted = { seconds in
            NotificationManager.shared.scheduleRestEnd(after: seconds)
        }
        engine.onRestEnded = {
            NotificationManager.shared.cancelRestEnd()
        }
        engine.onRestAlert = {
            RestFeedback.fire()
        }
        engine.start(day: day, context: context)

        // Mantiene la pantalla encendida durante la sesión.
        UIApplication.shared.isIdleTimerDisabled = true
        Task { _ = await NotificationManager.shared.requestAuthorization() }
    }

    private func cleanup() {
        NotificationManager.shared.cancelRestEnd()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

// MARK: - Tarjeta de carga de peso y repeticiones

private struct LoggingCard: View {
    @Bindable var exercise: Exercise
    @Bindable var set: ExerciseSet
    let tint: Color
    var suggestedWeight: Double?

    @Environment(\.modelContext) private var context
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var lastSession: String?
    @FocusState private var focused: Field?

    private enum Field { case weight, reps }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                field(
                    title: "Peso",
                    placeholder: "kg",
                    text: $weightText,
                    keyboard: .decimalPad,
                    field: .weight
                )
                .onChange(of: weightText) { _, nuevo in
                    set.weight = Double(nuevo.replacingOccurrences(of: ",", with: "."))
                }

                field(
                    title: "Reps",
                    placeholder: exercise.targetReps ?? "reps",
                    text: $repsText,
                    keyboard: .numberPad,
                    field: .reps
                )
                .onChange(of: repsText) { _, nuevo in
                    set.reps = Int(nuevo)
                }
            }

            if let lastSession {
                Label("Última vez: \(lastSession)", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { focused = nil }
            }
        }
        .onAppear {
            if let w = set.weight {
                weightText = w.formattedKg
            } else if let s = suggestedWeight {
                weightText = s.formattedKg
                set.weight = s
            }
            if let r = set.reps { repsText = "\(r)" }
            lastSession = ExerciseHistory.lastSession(
                name: exercise.name,
                before: exercise.dayDate,
                context: context
            )
        }
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        field: Field
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .focused($focused, equals: field)
                .multilineTextAlignment(.center)
                .font(.title2.weight(.semibold))
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemFill))
                )
        }
    }
}

// MARK: - Aviso de fin de descanso (sonido + vibración)

private enum RestFeedback {
    static func fire() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1005)
    }
}

#Preview {
    GuidedGymSessionView(day: WorkoutSeed.allWorkoutDays().first { $0.type == .fuerza }!)
        .modelContainer(PreviewData.container)
}
