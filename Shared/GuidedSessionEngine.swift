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

    /// Identifica la sesión en vivo actual (para el sync con el iPhone). El
    /// reloj la renueva al empezar cada sesión con `beginLiveSession()`.
    private(set) var sessionID = UUID()

    // Cronómetro de descanso.
    private(set) var restTotal = 0
    private(set) var restRemaining = 0
    /// Segundos transcurridos una vez que el descanso llegó a 0 (tiempo extra).
    /// Sigue contando hacia arriba hasta que el usuario confirma la próxima serie.
    private(set) var restOvertime = 0
    private(set) var restEndDate: Date?
    /// Próximo segundo de tiempo extra en el que volver a avisar (vibrar).
    private var nextOvertimeAlert = 0
    /// Cada cuántos segundos de tiempo extra se repite el aviso.
    private let overtimeAlertInterval = 10

    /// De dónde sale "ahora". En la app es el reloj del sistema; en los tests se inyecta uno
    /// controlado, así no hay que calcular los tiempos a mano contra `restEndDate`.
    ///
    /// `tickRest(now:)` **ya** recibía la fecha desde afuera; lo que faltaba era el resto:
    /// `startRest`, `adjustRest` y `makeSnapshot` leían `Date()` por su cuenta, y eso hacía que
    /// un test no pudiera fijar el punto de partida.
    var clock: () -> Date = Date.init

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

    /// Se llama tras cada cambio de estado relevante (avance de serie, descanso,
    /// fin). El reloj lo usa para difundir un `LiveSessionSnapshot` al iPhone.
    /// No se dispara en cada tick del cronómetro: la cuenta regresiva la dibuja
    /// cada cliente con `restEndDate`, así no inundamos el canal.
    var onStateChanged: (() -> Void)?

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
        prefillCurrentSet()
    }

    /// Asocia el contexto para poder guardar los cambios.
    func attach(context: ModelContext) {
        self.context = context
        // Con el contexto ya disponible se completa el peso desde el historial.
        prefillCurrentSet()
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

    /// Ejercicios del día que todavía tienen series pendientes y no son el actual:
    /// candidatos para traer al lugar del siguiente (p. ej. si la máquina del que
    /// venía está ocupada y se quiere intercalar otro del plan).
    var switchableExercises: [Exercise] {
        guard let day, let current = currentStep?.exercise else { return [] }
        return day.orderedExercises.filter { exercise in
            exercise !== current && exercise.orderedSets.contains { !$0.isDone }
        }
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

    // MARK: - Prellenado

    /// Pre-carga la serie actual para registrar más rápido: las **reps** quedan en
    /// el objetivo del plan (solo se editan si no se llega) y el **peso** en el
    /// último usado (la serie previa de esta sesión, o el de la última sesión del
    /// ejercicio; solo se edita si se sube). Solo completa valores vacíos: nunca
    /// pisa lo que el usuario ya cargó.
    private func prefillCurrentSet() {
        guard let step = currentStep, let set = step.set else { return }

        if set.reps == nil, let target = targetReps(of: step.exercise) {
            set.reps = target
        }

        if step.exercise.tracksWeight, set.weight == nil {
            if let previous = suggestedWeight(for: step) {
                set.weight = previous
            } else if let context, let last = ExerciseHistory.lastWeight(
                name: step.exercise.name,
                before: step.exercise.dayDate,
                context: context
            ) {
                set.weight = last
            }
        }

        save()
    }

    /// Repeticiones objetivo del plan como número: el valor más alto que aparece
    /// en `targetReps` (ej. "6-8" → 8, "10" → 10, "30 s" → 30). La meta a alcanzar.
    private func targetReps(of exercise: Exercise) -> Int? {
        guard let text = exercise.targetReps else { return nil }
        let numbers = text.split { !$0.isNumber }.compactMap { Int($0) }
        return numbers.max()
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
        onStateChanged?()
    }

    private func advance() {
        restEndDate = nil
        restOvertime = 0
        index += 1
        phase = .logging
        prefillCurrentSet()
    }

    /// Trae `exercise` para que sea el **próximo** ejercicio: lo mueve justo
    /// después del ejercicio actual, preservando la posición y todo lo registrado.
    /// Sirve cuando la máquina del que seguía está ocupada y se intercala otro del
    /// plan. No corta el descanso en curso (si está descansando, el nuevo queda
    /// como "Sigue").
    func bringExerciseNext(_ exercise: Exercise) {
        guard let day, let current = currentStep else { return }
        let currentExercise = current.exercise
        guard exercise !== currentExercise else { return }
        let savedSet = current.set

        // Reordena los ejercicios del día: el elegido pasa a estar justo después
        // del actual; se reasignan los `order` para persistir el nuevo orden.
        var ordered = day.orderedExercises
        ordered.removeAll { $0 === exercise }
        guard let currentIdx = ordered.firstIndex(where: { $0 === currentExercise }) else { return }
        ordered.insert(exercise, at: currentIdx + 1)
        for (i, ex) in ordered.enumerated() { ex.order = i }
        save()

        // Reconstruye los pasos y reubica el índice en la misma serie actual.
        buildSteps(from: day)
        if let newIndex = steps.firstIndex(where: { $0.exercise === currentExercise && $0.set === savedSet }) {
            index = newIndex
        }
        onStateChanged?()
    }

    /// Vuelve a la serie anterior para corregirla (la des-marca para recargarla).
    func goBackFromLogging() {
        guard index > 0 else { return }
        index -= 1
        phase = .logging
        currentStep?.set?.isDone = false
        save()
        onStateChanged?()
    }

    /// Desde el descanso, vuelve a la serie recién cargada para corregirla.
    func goBackFromResting() {
        onRestEnded?()
        restEndDate = nil
        phase = .logging
        onStateChanged?()
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
        restEndDate = clock().addingTimeInterval(TimeInterval(seconds))
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
        // Transición a "tiempo extra": un único snapshot para que el iPhone
        // pinte el descanso en rojo (la cuenta sigue corriendo sola por fecha).
        let enteringOvertime = restRemaining > 0
        restRemaining = 0
        restOvertime = Int((-remaining).rounded(.down))
        if restOvertime >= nextOvertimeAlert {
            onRestAlert?()
            nextOvertimeAlert += overtimeAlertInterval
        }
        if enteringOvertime { onStateChanged?() }
    }

    /// Confirma que se empieza la próxima serie: corta el descanso (o el tiempo
    /// extra) y avanza. También es el "saltear descanso" cuando todavía corre.
    func skipRest() {
        onRestEnded?()
        advance()
        onStateChanged?()
    }

    /// Ajusta el descanso (±segundos), tanto la cuenta en curso como el valor
    /// recomendado del ejercicio, para que quede recordado.
    func adjustRest(by delta: Int) {
        guard phase == .resting, let end = restEndDate, let exercise = currentStep?.exercise else { return }
        let newRemaining = max(1, Int(end.timeIntervalSince(clock()).rounded(.up)) + delta)
        restEndDate = clock().addingTimeInterval(TimeInterval(newRemaining))
        restRemaining = newRemaining
        restOvertime = 0
        nextOvertimeAlert = 0
        restTotal = max(15, restTotal + delta)

        exercise.restSeconds = restTotal
        save()

        onRestStarted?(newRemaining)
        onStateChanged?()
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
        (day?.orderedExercises ?? []).reduce(0) { acc, ex in
            acc + ex.orderedSets.filter { $0.reps != nil || $0.weight != nil }.count
        }
    }

    /// Cantidad de ejercicios del día.
    var exerciseCount: Int {
        day?.orderedExercises.count ?? 0
    }

    /// Volumen total levantado (kg) = Σ peso × reps.
    var totalVolume: Double {
        (day?.orderedExercises ?? []).reduce(0) { acc, ex in
            acc + ex.orderedSets.reduce(0) { sAcc, set in
                guard let w = set.weight, let r = set.reps else { return sAcc }
                return sAcc + w * Double(r)
            }
        }
    }

    private func save() {
        try? context?.save()
    }

    // MARK: - Sesión en vivo (sync reloj ↔ iPhone)

    /// Renueva el id de sesión al empezar (el reloj lo llama al arrancar la
    /// sesión guiada, antes de difundir el primer snapshot).
    func beginLiveSession() {
        sessionID = UUID()
    }

    /// Fase actual en el tipo Codable que viaja por el canal en vivo.
    var livePhase: LiveSessionPhase {
        switch phase {
        case .logging: return .logging
        case .resting: return .resting
        case .done:    return .done
        }
    }

    /// Arma la foto del estado actual para difundir al iPhone. El pulso lo
    /// inyecta la plataforma (el engine no conoce HealthKit).
    func makeSnapshot(heartRate: Int? = nil) -> LiveSessionSnapshot {
        let step = currentStep
        let exercise = step?.exercise

        let bodyweight: Bool = exercise.map { !$0.tracksWeight } ?? false
        let timeBased: Bool = exercise?.isTimeBased ?? false
        let restEnd: Date? = (phase == .resting) ? restEndDate : nil
        let dayDate: Date = day?.date ?? clock()

        let snapshot = LiveSessionSnapshot(
            sessionID: sessionID,
            dayDate: dayDate,
            phase: livePhase,
            exerciseName: exercise?.name ?? "",
            exerciseIndex: step?.exerciseIndex ?? 0,
            exerciseCount: step?.exerciseCount ?? exerciseCount,
            setNumber: step?.setNumber ?? 0,
            setCount: step?.setCount ?? 0,
            targetReps: exercise?.targetReps,
            isBodyweight: bodyweight,
            isTimeBased: timeBased,
            weight: step?.set?.weight,
            reps: step?.set?.reps,
            restEndDate: restEnd,
            restTotal: restTotal,
            isOvertime: isRestOvertime,
            heartRate: heartRate,
            progressFraction: progressFraction,
            loggedSetsCount: loggedSetsCount,
            totalVolume: totalVolume,
            updatedAt: clock()
        )
        return snapshot
    }

    /// Aplica un comando remoto recibido del iPhone. Ignora los de otra sesión.
    /// Cada acción dispara `onStateChanged` por dentro, así que el reloj re-emite
    /// el snapshot automáticamente.
    func apply(_ command: LiveSessionCommand) {
        guard command.sessionID == sessionID else { return }
        switch command.action {
        case .completeCurrent:
            if phase == .logging { completeCurrent() }
        case .skipRest:
            if phase == .resting { skipRest() }
        case .goBack:
            if phase == .resting { goBackFromResting() }
            else if index > 0 { goBackFromLogging() }
        case .adjustRest(let delta):
            adjustRest(by: delta)
        case .end:
            endSession()
        }
    }

    /// Termina la sesión a distancia (botón de cerrar desde el iPhone). No marca
    /// todas las series: solo cierra la sesión en curso.
    private func endSession() {
        guard phase != .done else { return }
        onRestEnded?()
        restEndDate = nil
        phase = .done
        save()
        onStateChanged?()
    }
}
