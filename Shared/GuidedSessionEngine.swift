//
//  GuidedSessionEngine.swift
//  Maraton (compartido iOS + watchOS)
//
//  Máquina de estados de la sesión de gimnasio guiada: recorre ejercicio por
//  ejercicio y serie por serie, registra peso/reps en los modelos existentes,
//  y maneja el cronómetro de descanso. Es agnóstica de UI y de plataforma: el
//  aviso de fin de descanso (sonido/vibración) y las notificaciones las conecta
//  cada plataforma vía los hooks `onRest*`.
//

import Foundation
import SwiftData

/// Un paso de la sesión: una serie concreta de un ejercicio (o un paso único
/// para los ejercicios sin series, como el core).
struct GuidedStep: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let set: ExerciseSet?       // nil para ejercicios sin series (core)
    let setNumber: Int          // número de serie dentro del ejercicio (1-based)
    let setCount: Int           // total de series del ejercicio
    let exerciseIndex: Int      // posición del ejercicio (0-based)
    let exerciseCount: Int
}

enum GuidedSessionPhase {
    case logging   // cargando peso/reps de la serie actual
    case resting   // cuenta regresiva de descanso
    case done      // sesión terminada
}

@Observable
@MainActor
final class GuidedSessionEngine {

    // Estado observable.
    private(set) var steps: [GuidedStep] = []
    private(set) var index = 0
    private(set) var phase: GuidedSessionPhase = .logging

    // Cronómetro de descanso.
    private(set) var restTotal = 0
    private(set) var restRemaining = 0
    /// Segundos transcurridos una vez que el descanso llegó a 0 (tiempo extra).
    /// Sigue contando hacia arriba hasta que el usuario confirma la próxima serie.
    private(set) var restOvertime = 0
    private var restEndDate: Date?
    /// Próximo segundo de tiempo extra en el que volver a avisar (vibrar).
    private var nextOvertimeAlert = 0
    /// Cada cuántos segundos de tiempo extra se repite el aviso.
    private let overtimeAlertInterval = 10

    /// `true` mientras el descanso ya se cumplió pero la próxima serie no se
    /// confirmó: la UI muestra el tiempo extra en rojo.
    var isRestOvertime: Bool {
        phase == .resting && restRemaining == 0
    }

    // Hooks de plataforma (no obligatorios).
    /// Se llama al arrancar/reprogramar un descanso, con los segundos restantes.
    /// La plataforma puede agendar una notificación local de respaldo.
    var onRestStarted: ((Int) -> Void)?
    /// Se llama cuando el descanso se corta antes de tiempo o se consume
    /// (saltear, volver atrás, terminar). La plataforma cancela su notificación.
    var onRestEnded: (() -> Void)?
    /// Se llama exactamente cuando la cuenta regresiva llega a 0: la plataforma
    /// dispara su aviso (vibración en la muñeca / sonido + háptica en iPhone).
    var onRestAlert: (() -> Void)?

    private var day: WorkoutDay?
    private var context: ModelContext?

    // MARK: - Ciclo de vida

    /// Arranca la sesión para un día. Idempotente: si ya está armada, no hace nada.
    func start(day: WorkoutDay, context: ModelContext) {
        attach(context: context)
        prepare(day: day)
    }

    /// Construye los pasos de la sesión a partir del día. No necesita contexto,
    /// así que se puede llamar en el `init` de la vista para que la UI tenga
    /// contenido en el primer render (sin depender de `onAppear`). Idempotente.
    func prepare(day: WorkoutDay) {
        guard steps.isEmpty else { return }
        self.day = day
        buildSteps(from: day)
        index = firstIncompleteIndex()
        phase = .logging
    }

    /// Asocia el contexto para poder guardar los cambios.
    func attach(context: ModelContext) {
        self.context = context
    }

    private func buildSteps(from day: WorkoutDay) {
        let exercises = day.orderedExercises
        var result: [GuidedStep] = []
        for (i, exercise) in exercises.enumerated() {
            let sets = exercise.orderedSets
            if sets.isEmpty {
                result.append(GuidedStep(
                    exercise: exercise, set: nil,
                    setNumber: 0, setCount: 0,
                    exerciseIndex: i, exerciseCount: exercises.count
                ))
            } else {
                for (j, set) in sets.enumerated() {
                    result.append(GuidedStep(
                        exercise: exercise, set: set,
                        setNumber: j + 1, setCount: sets.count,
                        exerciseIndex: i, exerciseCount: exercises.count
                    ))
                }
            }
        }
        steps = result
    }

    /// Primera serie sin completar (para retomar una sesión a medias); si están
    /// todas hechas, arranca desde el principio.
    private func firstIncompleteIndex() -> Int {
        steps.firstIndex { $0.set != nil && !($0.set?.isDone ?? true) } ?? 0
    }

    // MARK: - Pasos

    var currentStep: GuidedStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    var nextStep: GuidedStep? {
        steps.indices.contains(index + 1) ? steps[index + 1] : nil
    }

    var isLastStep: Bool {
        index >= steps.count - 1
    }

    /// Peso sugerido para la serie actual: el de la serie previa del mismo
    /// ejercicio que tenga peso cargado (solo si la serie actual aún no tiene).
    func suggestedWeight(for step: GuidedStep) -> Double? {
        guard let set = step.set, set.weight == nil else { return nil }
        let sets = step.exercise.orderedSets
        guard let i = sets.firstIndex(where: { $0 === set }) else { return nil }
        for j in stride(from: i - 1, through: 0, by: -1) {
            if let w = sets[j].weight { return w }
        }
        return nil
    }

    // MARK: - Acciones

    /// Marca la serie actual como hecha y avanza: al descanso (si hay próxima
    /// serie) o a la pantalla final (si era la última).
    func completeCurrent() {
        guard let step = currentStep else { return }
        step.set?.isDone = true
        save()

        if isLastStep {
            finish()
        } else if step.set != nil {
            startRest(seconds: step.exercise.restOrDefault)
        } else {
            advance()
        }
    }

    private func advance() {
        restEndDate = nil
        restOvertime = 0
        index += 1
        phase = .logging
    }

    /// Vuelve a la serie anterior para corregirla (la des-marca para recargarla).
    func goBackFromLogging() {
        guard index > 0 else { return }
        index -= 1
        phase = .logging
        currentStep?.set?.isDone = false
        save()
    }

    /// Desde el descanso, vuelve a la serie recién cargada para corregirla.
    func goBackFromResting() {
        onRestEnded?()
        restEndDate = nil
        phase = .logging
    }

    private func finish() {
        onRestEnded?()
        day?.isCompleted = true
        save()
        phase = .done
    }

    // MARK: - Cronómetro de descanso

    private func startRest(seconds: Int) {
        restTotal = seconds
        restRemaining = seconds
        restOvertime = 0
        nextOvertimeAlert = 0
        restEndDate = Date().addingTimeInterval(TimeInterval(seconds))
        phase = .resting
        onRestStarted?(seconds)
    }

    /// La UI debe llamar a esto periódicamente (timer) mientras dura el descanso.
    /// Al llegar a 0 no avanza solo: entra en "tiempo extra" y cuenta hacia
    /// arriba, repitiendo el aviso, hasta que el usuario confirme la próxima
    /// serie (`skipRest`).
    func tickRest(now: Date) {
        guard phase == .resting, let end = restEndDate else { return }
        let remaining = end.timeIntervalSince(now)
        if remaining > 0 {
            restRemaining = Int(remaining.rounded(.up))
            restOvertime = 0
            return
        }
        restRemaining = 0
        restOvertime = Int((-remaining).rounded(.down))
        if restOvertime >= nextOvertimeAlert {
            onRestAlert?()
            nextOvertimeAlert += overtimeAlertInterval
        }
    }

    /// Confirma que se empieza la próxima serie: corta el descanso (o el tiempo
    /// extra) y avanza. También es el "saltear descanso" cuando todavía corre.
    func skipRest() {
        onRestEnded?()
        advance()
    }

    /// Ajusta el descanso (±segundos), tanto la cuenta en curso como el valor
    /// recomendado del ejercicio, para que quede recordado.
    func adjustRest(by delta: Int) {
        guard phase == .resting, let end = restEndDate, let exercise = currentStep?.exercise else { return }
        let newRemaining = max(1, Int(end.timeIntervalSinceNow.rounded(.up)) + delta)
        restEndDate = Date().addingTimeInterval(TimeInterval(newRemaining))
        restRemaining = newRemaining
        restOvertime = 0
        nextOvertimeAlert = 0
        restTotal = max(15, restTotal + delta)

        exercise.restSeconds = restTotal
        save()

        onRestStarted?(newRemaining)
    }

    /// Fracción del anillo de descanso (0…1).
    var restFraction: Double {
        guard restTotal > 0 else { return 0 }
        return min(1, Double(restRemaining) / Double(restTotal))
    }

    // MARK: - Progreso y resumen

    /// Fracción de avance general de la sesión (0…1).
    var progressFraction: Double {
        guard !steps.isEmpty else { return 0 }
        switch phase {
        case .logging: return Double(index) / Double(steps.count)
        case .resting: return Double(index + 1) / Double(steps.count)
        case .done:    return 1
        }
    }

    /// Series con datos cargados en todo el día.
    var loggedSetsCount: Int {
        (day?.exercises ?? []).reduce(0) { acc, ex in
            acc + ex.sets.filter { $0.reps != nil || $0.weight != nil }.count
        }
    }

    /// Cantidad de ejercicios del día.
    var exerciseCount: Int {
        day?.exercises.count ?? 0
    }

    /// Volumen total levantado (kg) = Σ peso × reps.
    var totalVolume: Double {
        (day?.exercises ?? []).reduce(0) { acc, ex in
            acc + ex.sets.reduce(0) { sAcc, set in
                guard let w = set.weight, let r = set.reps else { return sAcc }
                return sAcc + w * Double(r)
            }
        }
    }

    private func save() {
        try? context?.save()
    }
}
