//
//  WatchGuidedSessionView.swift
//  MaratonWatch Watch App
//
//  Sesión de gimnasio guiada desde la muñeca. Usa el `GuidedSessionEngine`
//  compartido (misma lógica que el iPhone) y `WatchWorkoutManager` para el
//  pulso en vivo. El peso/reps se cargan tocando el valor para seleccionarlo y
//  girando la corona digital; sin nada seleccionado la corona hace scroll de la
//  pantalla. Entre series arranca el descanso con vibración al terminar.
//

import SwiftUI
import SwiftData
import WatchKit
import Combine

struct WatchGuidedSessionView: View {
    @Bindable var day: WorkoutDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var engine: GuidedSessionEngine
    @State private var workout = WatchWorkoutManager()

    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    private var tint: Color { WorkoutType.fuerza.color }

    init(day: WorkoutDay) {
        _day = Bindable(wrappedValue: day)
        // Construye los pasos ya en el init, para que la pantalla tenga
        // contenido en el primer render (sin depender de `onAppear`).
        let engine = GuidedSessionEngine()
        engine.prepare(day: day)
        _engine = State(initialValue: engine)
    }

    var body: some View {
        Group {
            switch engine.phase {
            case .logging: loggingScreen
            case .resting: restingScreen
            case .done:    doneScreen
            }
        }
        .navigationTitle("Sesión")
        .task { startSession() }
        .onDisappear(perform: stopWorkoutIfNeeded)
        .onReceive(ticker) { engine.tickRest(now: $0) }
        .onChange(of: engine.phase) { _, newPhase in
            if newPhase == .done { saveWorkoutMetrics() }
        }
    }

    // MARK: - Logging

    @ViewBuilder
    private var loggingScreen: some View {
        if let step = engine.currentStep {
            WatchLoggingView(
                exercise: step.exercise,
                set: step.set,
                stepNumber: step.setNumber,
                stepCount: step.setCount,
                tint: tint,
                suggestedWeight: engine.suggestedWeight(for: step),
                heartRate: workout.currentHeartRate,
                canGoBack: engine.index > 0,
                onDone: engine.completeCurrent,
                onBack: engine.goBackFromLogging
            )
            .id(step.id)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Sin ejercicios para hoy")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: - Descanso

    private var restingScreen: some View {
        ScrollView {
            VStack(spacing: 12) {
                hrChip

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: engine.restFraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: engine.restRemaining)
                    VStack(spacing: 0) {
                        Text(engine.restRemaining.countdownLabel)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("descanso")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)

                HStack(spacing: 8) {
                    Button { engine.adjustRest(by: -15) } label: {
                        Image(systemName: "minus")
                    }
                    Button { engine.adjustRest(by: 15) } label: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button { engine.skipRest() } label: {
                    Label("Saltear", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Fin

    private var doneScreen: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("¡Sesión completa!")
                    .font(.headline)
                Text("Guardada con tus pesos y pulso.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    summaryRow("Series", "\(engine.loggedSetsCount)")
                    if let hr = day.avgHeartRate {
                        summaryRow("Pulso prom.", "\(Int(hr)) bpm")
                    }
                    if engine.totalVolume > 0 {
                        summaryRow("Volumen", "\(engine.totalVolume.formattedKg) kg")
                    }
                }
                .padding(.vertical, 4)

                Button { dismiss() } label: {
                    Label("Cerrar", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
            .padding(.horizontal, 4)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.caption)
    }

    private var hrChip: some View {
        Label(workout.currentHeartRate > 0 ? "\(workout.currentHeartRate)" : "—", systemImage: "heart.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Ciclo de vida

    private func startSession() {
        engine.onRestAlert = {
            WKInterfaceDevice.current().play(.notification)
        }
        // Los pasos ya se construyeron en el init; acá solo asociamos el contexto
        // para guardar y arrancamos la sesión de entrenamiento (pulso en vivo).
        engine.attach(context: context)
        Task {
            await workout.requestAuthorization()
            workout.start()
        }
    }

    private func saveWorkoutMetrics() {
        Task {
            let metrics = await workout.end()
            if let hr = metrics.avgHeartRate { day.avgHeartRate = hr }
            if let kcal = metrics.activeCalories { day.activeCalories = kcal }
            if let minutes = metrics.minutes { day.durationMinutes = minutes }
            try? context.save()
        }
    }

    private func stopWorkoutIfNeeded() {
        // Si se sale antes de terminar, cierra la sesión de entrenamiento.
        if workout.isRunning {
            Task { await workout.end() }
        }
    }
}

// MARK: - Carga de una serie (peso/reps con corona + botones)

private struct WatchLoggingView: View {
    @Bindable var exercise: Exercise
    let set: ExerciseSet?
    let stepNumber: Int
    let stepCount: Int
    let tint: Color
    let suggestedWeight: Double?
    let heartRate: Int
    let canGoBack: Bool
    let onDone: () -> Void
    let onBack: () -> Void

    /// Qué valor está "agarrado" por la corona. `nil` ⇒ la corona hace scroll.
    private enum Field { case weight, reps }
    /// `armed` habilita la focusabilidad de la celda; `focused` le da el foco.
    /// Se separan porque watchOS descarta la asignación de foco si la celda no
    /// era focusable en el render anterior: primero la armamos (focusable) y
    /// recién en el ciclo siguiente la enfocamos.
    @State private var armed: Field?
    @FocusState private var focused: Field?

    @State private var weight: Double = 0
    @State private var reps: Double = 0

    /// Alterna qué valor maneja la corona. Al tocar de nuevo el activo, lo
    /// suelta y la corona vuelve a hacer scroll.
    private func toggle(_ field: Field) {
        if armed == field {
            armed = nil
            focused = nil
        } else {
            armed = field
            DispatchQueue.main.async { focused = field }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Label(heartRate > 0 ? "\(heartRate)" : "—", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(exercise.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if set != nil {
                    Text("Serie \(stepNumber) de \(stepCount)")
                        .font(.caption)
                        .foregroundStyle(tint)
                    if let target = exercise.targetReps {
                        Text("Objetivo \(target) reps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    weightControl
                    repsControl

                    Text(armed == nil ? "Tocá un valor y girá la corona" : "Girá la corona para ajustar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                }

                Button {
                    commit()
                    onDone()
                } label: {
                    Label(set != nil ? "Hecho" : "Listo", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)

                if canGoBack {
                    Button(action: onBack) {
                        Label("Anterior", systemImage: "chevron.left")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear(perform: prefill)
    }

    /// Peso: tocá para seleccionar y girá la corona (paso 1.25 kg).
    private var weightControl: some View {
        valueCell(title: "Peso",
                  value: weight > 0 ? "\(weight.formattedKg) kg" : "—",
                  field: .weight)
            .focusable(armed == .weight)
            .focused($focused, equals: .weight)
            .digitalCrownRotation(
                $weight,
                from: 0,
                through: 600,
                by: 1.25,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
    }

    /// Reps: tocá para seleccionar y girá la corona (paso 1 rep).
    private var repsControl: some View {
        valueCell(title: "Reps",
                  value: reps > 0 ? "\(Int(reps))" : "—",
                  field: .reps)
            .focusable(armed == .reps)
            .focused($focused, equals: .reps)
            .digitalCrownRotation(
                $reps,
                from: 0,
                through: 100,
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
    }

    /// Celda tocable que muestra un valor. Al tocarla, agarra la corona
    /// (resalta con el tint); tocándola de nuevo la suelta y la corona
    /// vuelve a hacer scroll de la pantalla.
    private func valueCell(title: String, value: String, field: Field) -> some View {
        let isActive = armed == field
        return HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if isActive {
                Image(systemName: "digitalcrown.arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isActive ? tint : .primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? tint.opacity(0.25) : Color.gray.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? tint : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggle(field)
        }
    }

    private func prefill() {
        guard let set else { return }
        weight = set.weight ?? suggestedWeight ?? 0
        reps = Double(set.reps ?? 0)
    }

    private func commit() {
        guard let set else { return }
        set.weight = weight > 0 ? weight : nil
        set.reps = reps > 0 ? Int(reps) : nil
    }
}
