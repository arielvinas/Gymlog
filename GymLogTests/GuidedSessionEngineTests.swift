//
//  GuidedSessionEngineTests.swift
//  GymLogTests
//
//  La máquina de estados de la sesión de gimnasio guiada: el corazón de la app.
//  Corre en el reloj (que es la autoridad) y se espeja en el iPhone y en la Live
//  Activity, así que un error acá no se ve como un crash — se ve como una serie
//  que se saltea, un descanso que no avisa, o un peso que se pierde.
//
//  El engine no necesita refactor para testearse: el `ModelContext` es opcional,
//  sus cuatro efectos externos son closures que se espían con contadores, y
//  `tickRest(now:)` recibe la fecha, así que el cronómetro se simula sin esperar
//  tiempo real.
//
//  Backlog: TESTING.md · I-01..I-20
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Sesión guiada · máquina de estados")
struct GuidedSessionEngineTests {

    /// Un día de fuerza con dos ejercicios: 3 series y 2 series. Total: 5 pasos.
    /// Es la forma típica de una sesión y sirve de base para casi todos los tests.
    @MainActor
    private func dayWithTwoExercises(in context: ModelContext) -> WorkoutDay {
        let day = makeDay(date(2026, 7, 1), type: .fuerza, title: "Fuerza A", in: context)
        makeExercise(
            "Press banca", on: day, order: 0,
            targetReps: "6-8", restSeconds: 90,
            sets: [(nil, nil), (nil, nil), (nil, nil)],
            in: context
        )
        makeExercise(
            "Remo", on: day, order: 1,
            targetReps: "10", restSeconds: 60,
            sets: [(nil, nil), (nil, nil)],
            in: context
        )
        return day
    }

    // MARK: - I-01

    @Test("I-01 · start arma un paso por cada serie de cada ejercicio")
    func startBuildsOneStepPerSet() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.steps.count == 5)

        // Los pasos van en orden: primero las 3 series del press, después las 2 del remo.
        #expect(engine.steps.map(\.exercise.name) == [
            "Press banca", "Press banca", "Press banca", "Remo", "Remo",
        ])
        // `setNumber` es 1-based dentro de cada ejercicio; `exerciseIndex` es 0-based.
        #expect(engine.steps.map(\.setNumber) == [1, 2, 3, 1, 2])
        #expect(engine.steps.map(\.setCount) == [3, 3, 3, 2, 2])
        #expect(engine.steps.map(\.exerciseIndex) == [0, 0, 0, 1, 1])
        #expect(engine.steps.allSatisfy { $0.exerciseCount == 2 })
    }

    @Test("I-01 · Una sesión nueva arranca en la primera serie, cargando")
    func startBeginsAtFirstSetLogging() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.index == 0)
        #expect(engine.phase == .logging)
        #expect(engine.currentStep?.exercise.name == "Press banca")
        #expect(engine.currentStep?.setNumber == 1)
        #expect(engine.nextStep?.setNumber == 2)
    }

    @Test("I-01 · Retomar una sesión a medias arranca en la primera serie incompleta")
    func startResumesAtFirstIncompleteSet() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        // Las dos primeras series del press ya están hechas.
        let press = day.orderedExercises[0]
        press.orderedSets[0].isDone = true
        press.orderedSets[1].isDone = true

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.index == 2, "Debería retomar en la 3ª serie, no volver al principio")
        #expect(engine.currentStep?.setNumber == 3)
        #expect(engine.phase == .logging)
    }

    @Test("I-01 · Un ejercicio sin series (core) ocupa un solo paso")
    func exerciseWithoutSetsIsASingleStep() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        makeExercise("Plancha", on: day, order: 0, sets: [], in: db.context)
        makeExercise("Press banca", on: day, order: 1, sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.steps.count == 2)

        // El paso de core no tiene serie asociada: no hay peso ni reps que cargar.
        #expect(engine.steps[0].set == nil)
        #expect(engine.steps[0].setNumber == 0)
        #expect(engine.steps[0].setCount == 0)
        #expect(engine.steps[1].set != nil)
    }

    @Test("I-01 · start es idempotente")
    func startIsIdempotent() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.start(day: day, context: db.context)

        // La vista puede llamar a `prepare` en el init y a `start` en el onAppear:
        // rearmar los pasos perdería el progreso de la sesión en curso.
        #expect(engine.steps.count == 5)
    }

    // MARK: - I-02

    @Test("I-02 · Completar una serie la marca y arranca el descanso del ejercicio")
    func completeCurrentStartsTheRest() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var restStartedWith: [Int] = []
        engine.onRestStarted = { restStartedWith.append($0) }
        engine.start(day: day, context: db.context)

        let primeraSerie = engine.currentStep?.set
        engine.completeCurrent()

        #expect(primeraSerie?.isDone == true)
        #expect(engine.phase == .resting)

        // El descanso sale del ejercicio, no de una constante: el press pidió 90 s.
        #expect(engine.restTotal == 90)
        #expect(engine.restRemaining == 90)
        #expect(restStartedWith == [90], "La plataforma tiene que enterarse para agendar su aviso")

        // Todavía no avanzó: el índice se mueve recién al salir del descanso.
        #expect(engine.index == 0)
    }

    @Test("I-02 · Cada ejercicio impone su propio descanso")
    func restComesFromTheCurrentExercise() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Consume las 3 series del press (90 s) hasta llegar al remo (60 s).
        for _ in 0..<3 {
            engine.completeCurrent()
            engine.skipRest()
        }

        #expect(engine.currentStep?.exercise.name == "Remo")
        engine.completeCurrent()
        #expect(engine.restTotal == 60)
    }

    @Test("I-02 · Completar la última serie termina la sesión")
    func completingTheLastSetFinishesTheSession() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Las 4 primeras series pasan por descanso; la 5ª es la última.
        for _ in 0..<4 {
            engine.completeCurrent()
            engine.skipRest()
        }
        #expect(engine.isLastStep)

        engine.completeCurrent()

        #expect(engine.phase == .done)
        #expect(day.isCompleted, "Terminar la sesión tiene que marcar el día como completado")
        #expect(engine.progressFraction == 1)

        // La última serie no abre un descanso que nadie va a consumir.
        #expect(engine.restEndDate == nil)
    }

    @Test("I-02 · Cada transición avisa al iPhone")
    func everyTransitionNotifiesTheMirror() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var cambios = 0
        engine.onStateChanged = { cambios += 1 }
        engine.start(day: day, context: db.context)

        // `onStateChanged` es lo que dispara el broadcast del snapshot al iPhone y a
        // la Live Activity: si una transición no lo emite, el espejo queda congelado.
        engine.completeCurrent()
        #expect(cambios == 1)

        engine.skipRest()
        #expect(cambios == 2)
    }

    // MARK: - I-03

    /// Día con un ejercicio de core (sin series) intercalado entre dos con series.
    /// El core no lleva peso ni reps: se hace y se sigue.
    @MainActor
    private func dayWithCoreInTheMiddle(in context: ModelContext) -> WorkoutDay {
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: context)
        makeExercise("Press banca", on: day, order: 0, restSeconds: 90,
                     sets: [(nil, nil)], in: context)
        makeExercise("Plancha", on: day, order: 1, restSeconds: 90,
                     sets: [], in: context)
        makeExercise("Remo", on: day, order: 2, restSeconds: 60,
                     sets: [(nil, nil)], in: context)
        return day
    }

    @Test("I-03 · El core no abre descanso: se completa y sigue de largo")
    func coreStepSkipsTheRest() {
        let db = TestDB()
        let day = dayWithCoreInTheMiddle(in: db.context)

        let engine = GuidedSessionEngine()
        var descansos = 0
        engine.onRestStarted = { _ in descansos += 1 }
        engine.start(day: day, context: db.context)

        // Serie del press: sí descansa.
        engine.completeCurrent()
        #expect(engine.phase == .resting)
        engine.skipRest()

        // Ahora estamos en la plancha.
        #expect(engine.currentStep?.exercise.name == "Plancha")
        #expect(engine.currentStep?.set == nil)

        engine.completeCurrent()

        // No descansa: avanza directo al remo, sigue cargando.
        #expect(engine.phase == .logging, "El core no debería abrir un descanso")
        #expect(engine.currentStep?.exercise.name == "Remo")
        #expect(descansos == 1, "El único descanso fue el del press")
    }

    @Test("I-03 · El paso de core nunca queda marcado como hecho")
    func coreStepIsNeverMarkedDone() {
        let db = TestDB()
        let day = dayWithCoreInTheMiddle(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.completeCurrent()   // press
        engine.skipRest()
        engine.completeCurrent()   // plancha

        // `completeCurrent` marca `step.set?.isDone`, y el core no tiene serie: la
        // marca es un no-op. Suena a bug pero no lo es — `firstIncompleteIndex` solo
        // mira pasos **con** serie, así que al retomar la sesión el core se saltea
        // igual y no bloquea nada. Queda escrito para que nadie lo "arregle" de más.
        let plancha = day.orderedExercises[1]
        #expect(plancha.orderedSets.isEmpty)

        let retomado = GuidedSessionEngine()
        retomado.start(day: day, context: db.context)
        #expect(
            retomado.currentStep?.exercise.name == "Remo",
            "Al retomar debería caer en el remo, no volver a la plancha"
        )
    }

    // MARK: - I-04

    @Test("I-04 · skipRest corta el descanso y avanza a la serie siguiente")
    func skipRestAdvancesToTheNextSet() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var descansosTerminados = 0
        engine.onRestEnded = { descansosTerminados += 1 }
        engine.start(day: day, context: db.context)

        engine.completeCurrent()
        #expect(engine.phase == .resting)
        #expect(engine.index == 0)

        engine.skipRest()

        #expect(engine.phase == .logging)
        #expect(engine.index == 1, "Recién acá se mueve el índice")
        #expect(engine.currentStep?.setNumber == 2)

        // La plataforma tiene que enterarse para cancelar la notificación local que
        // había agendado al arrancar el descanso.
        #expect(descansosTerminados == 1)
    }

    @Test("I-04 · Al avanzar se limpia el estado del descanso anterior")
    func advancingClearsThePreviousRest() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        engine.completeCurrent()
        #expect(engine.restEndDate != nil)

        engine.skipRest()

        // Si `restEndDate` sobreviviera al avance, el snapshot que va al iPhone
        // seguiría mostrando una cuenta regresiva sobre una serie que ya no descansa.
        #expect(engine.restEndDate == nil)
        #expect(engine.restOvertime == 0)
    }

    @Test("I-04 · skipRest funciona igual en tiempo extra")
    func skipRestWorksDuringOvertime() throws {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.completeCurrent()

        // Simula que pasaron 20 s desde que venció el descanso: estamos en tiempo extra.
        // `tickRest(now:)` recibe la fecha, así que no hace falta esperar tiempo real.
        let fin = try #require(engine.restEndDate)
        engine.tickRest(now: fin.addingTimeInterval(20))
        #expect(engine.isRestOvertime)

        // "Empezar serie" es el mismo `skipRest`: es como se sale del tiempo extra.
        engine.skipRest()

        #expect(engine.phase == .logging)
        #expect(engine.index == 1)
        #expect(engine.restOvertime == 0)
    }

    // MARK: - I-05

    // ⭐ **La regla más importante del engine.**
    //
    // Cuando el descanso llega a cero, el engine **no avanza solo**: entra en tiempo
    // extra, cuenta hacia arriba y espera a que el usuario confirme la próxima serie.
    //
    // Es una decisión de diseño deliberada, no un descuido. Si avanzara solo, el
    // reloj daría por empezada una serie que el usuario todavía no arrancó —y las
    // reps y el peso quedarían asignados al momento equivocado. Hasta ahora esa
    // decisión solo la sostenía un comentario en el código.

    /// Lleva el engine hasta el descanso de la primera serie y devuelve la fecha de
    /// fin, para poder simular el paso del tiempo a partir de ahí.
    @MainActor
    private func engineResting(in db: TestDB) throws -> (GuidedSessionEngine, Date) {
        let day = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.completeCurrent()
        return (engine, try #require(engine.restEndDate))
    }

    @Test("I-05 · Al llegar a cero, el descanso NO avanza solo")
    func restDoesNotAutoAdvanceAtZero() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        engine.tickRest(now: fin)

        #expect(engine.phase == .resting, "El engine avanzó solo: se rompió la regla central")
        #expect(engine.index == 0, "La serie siguiente no debe empezar sin confirmación")
        #expect(engine.restRemaining == 0)
        #expect(engine.isRestOvertime)
    }

    @Test("I-05 · El tiempo extra cuenta hacia arriba y sigue esperando")
    func overtimeCountsUpAndKeepsWaiting() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        engine.tickRest(now: fin.addingTimeInterval(10))
        #expect(engine.restOvertime == 10)

        engine.tickRest(now: fin.addingTimeInterval(45))
        #expect(engine.restOvertime == 45)

        // Aunque pasen cinco minutos, la sesión sigue esperando en el mismo lugar.
        engine.tickRest(now: fin.addingTimeInterval(300))
        #expect(engine.restOvertime == 300)
        #expect(engine.phase == .resting)
        #expect(engine.index == 0)
    }

    @Test("I-05 · Solo la confirmación del usuario saca del tiempo extra")
    func onlyUserConfirmationLeavesOvertime() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        // Muchos ticks: ni uno solo avanza la sesión.
        for segundos in stride(from: 1, through: 120, by: 1) {
            engine.tickRest(now: fin.addingTimeInterval(TimeInterval(segundos)))
        }
        #expect(engine.index == 0)
        #expect(engine.phase == .resting)

        engine.skipRest()

        #expect(engine.index == 1, "Recién la confirmación explícita avanza")
        #expect(engine.phase == .logging)
    }

    @Test("I-05 · Mientras queda descanso, la cuenta baja y no hay tiempo extra")
    func restCountsDownBeforeReachingZero() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        engine.tickRest(now: fin.addingTimeInterval(-60))
        #expect(engine.restRemaining == 60)
        #expect(engine.restOvertime == 0)
        #expect(!engine.isRestOvertime)

        engine.tickRest(now: fin.addingTimeInterval(-1))
        #expect(engine.restRemaining == 1)
        #expect(!engine.isRestOvertime)
    }

    // MARK: - I-06

    @Test("I-06 · Entrar en tiempo extra avisa al iPhone una sola vez")
    func enteringOvertimeNotifiesTheMirrorExactlyOnce() throws {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.completeCurrent()

        // A partir de acá contamos solo los avisos del cronómetro.
        var cambios = 0
        engine.onStateChanged = { cambios += 1 }
        let fin = try #require(engine.restEndDate)

        // Ticks mientras todavía queda descanso: no avisan (la cuenta regresiva la
        // dibuja cada cliente solo, a partir de `restEndDate`; inundar el canal de
        // WatchConnectivity con un snapshot por tick sería carísimo).
        engine.tickRest(now: fin.addingTimeInterval(-30))
        engine.tickRest(now: fin.addingTimeInterval(-10))
        #expect(cambios == 0)

        // El cruce a tiempo extra sí: el iPhone tiene que pintar el descanso en rojo.
        engine.tickRest(now: fin.addingTimeInterval(1))
        #expect(cambios == 1)

        // Y los ticks siguientes de tiempo extra no repiten el aviso.
        engine.tickRest(now: fin.addingTimeInterval(5))
        engine.tickRest(now: fin.addingTimeInterval(15))
        #expect(cambios == 1, "El cruce a tiempo extra avisa una sola vez")
    }

    @Test("I-06 · ⚠️ Con descanso de 0 s, el iPhone nunca se entera del tiempo extra")
    func zeroSecondRestNeverNotifiesOvertime() throws {
        // ⚠️ **Documenta el bug 3, que hoy NO es alcanzable.**
        //
        // `tickRest` decide si avisar con `enteringOvertime = restRemaining > 0`. Con un
        // descanso de 0 s, `restRemaining` ya arranca en 0, así que la condición nunca
        // se cumple y **`onStateChanged` no se emite jamás**: el iPhone y la Live
        // Activity no pintan el rojo del tiempo extra.
        //
        // Hoy no muerde: las plantillas usan 30–120 s, `adjustRest` clampea el total a
        // un mínimo de 15, y ninguna vista escribe `restSeconds = 0`. O sea que es un
        // agujero de la lógica del engine, no un bug que el usuario pueda ver.
        //
        // El test existe como guardia: el día que alguien agregue una plantilla sin
        // descanso (un superserie, por ejemplo), esto se convierte en un bug real y
        // este test es el que lo explica.
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        makeExercise("Superserie", on: day, order: 0, restSeconds: 0,
                     sets: [(nil, nil), (nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.completeCurrent()
        #expect(engine.phase == .resting)

        var cambios = 0
        engine.onStateChanged = { cambios += 1 }
        let fin = try #require(engine.restEndDate)

        engine.tickRest(now: fin.addingTimeInterval(10))

        #expect(engine.isRestOvertime, "Sí entra en tiempo extra…")
        #expect(cambios == 0, "…pero no avisa. Comportamiento actual, no el deseado")
    }
}
