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

    /// Un día con tres ejercicios de 2 series cada uno. Con dos no alcanza para probar
    /// el reordenado: hace falta un tercero para que "traer al siguiente" tenga a dónde
    /// mover algo.
    @MainActor
    private func dayWithThreeExercises(in context: ModelContext) -> WorkoutDay {
        let day = makeDay(date(2026, 7, 1), type: .fuerza, title: "Fuerza A", in: context)
        for (i, nombre) in ["Press banca", "Remo", "Sentadilla"].enumerated() {
            makeExercise(
                nombre, on: day, order: i,
                targetReps: "8", restSeconds: 60,
                sets: [(nil, nil), (nil, nil)],
                in: context
            )
        }
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

    // MARK: - I-07

    @Test("I-07 · En tiempo extra, el aviso se repite cada 10 s")
    func overtimeAlertRepeatsEveryTenSeconds() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        var avisos = 0
        engine.onRestAlert = { avisos += 1 }

        // La UI llama a `tickRest` unas 5-10 veces por segundo (0,1 s en iPhone,
        // 0,2 s en el reloj). Simulamos ese goteo: 40 s de tiempo extra.
        for decima in 0...400 {
            engine.tickRest(now: fin.addingTimeInterval(TimeInterval(decima) / 10))
        }

        // Avisos en 0, 10, 20, 30 y 40 s: cinco vibraciones, bien espaciadas.
        #expect(avisos == 5)
    }

    @Test("I-07 · ⚠️ Al volver de background, el aviso se dispara en ráfaga")
    func returningFromBackgroundFiresABurstOfAlerts() throws {
        // ⚠️ **Documenta el bug 4. Este SÍ es alcanzable** — basta con que la app se
        // suspenda durante un descanso, que es cosa de todos los días (bajás la muñeca,
        // el reloj apaga la pantalla y deja de tickear).
        //
        // `tickRest` avisa cuando `restOvertime >= nextOvertimeAlert` y después hace
        // `nextOvertimeAlert += 10`. El `+=` asume que los ticks vienen seguidos: da un
        // paso de 10 por vez. Si la app estuvo suspendida y vuelve con 35 s de tiempo
        // extra encima, el contador arranca en 0 y tiene que **remontar** — y como cada
        // tick solo lo sube 10, hacen falta varios ticks para alcanzarlo. Cada uno de
        // esos ticks dispara su propia vibración.
        //
        // Resultado: cuatro vibraciones en menos de un segundo, en vez de una.
        //
        // El arreglo natural es saltar `nextOvertimeAlert` directo al próximo múltiplo
        // de 10 por encima del `restOvertime` actual, en vez de incrementarlo de a 10.
        // No lo aplico acá: el fix va en un commit aparte.
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        var avisos = 0
        engine.onRestAlert = { avisos += 1 }

        // La app estuvo suspendida: ni un tick durante el descanso ni los primeros 35 s
        // de tiempo extra. Vuelve, y el timer retoma su goteo normal.
        for decima in 350...360 {
            engine.tickRest(now: fin.addingTimeInterval(TimeInterval(decima) / 10))
        }

        #expect(
            avisos == 4,
            "Comportamiento actual: ráfaga de 4 vibraciones al volver. Lo correcto sería 1"
        )
    }

    // MARK: - I-08

    // `adjustRest` usa `Date()` internamente, así que el remanente no es exacto al
    // segundo en un test. Lo que sí es determinístico —y lo que importa— es
    // `restTotal` y lo que queda persistido en el ejercicio.

    @Test("I-08 · Sumar 15 s alarga el descanso en curso")
    func adjustRestAddsTime() throws {
        let db = TestDB()
        let (engine, _) = try engineResting(in: db)
        #expect(engine.restTotal == 90)

        engine.adjustRest(by: 15)

        #expect(engine.restTotal == 105)
        #expect((104...105).contains(engine.restRemaining))

        let nuevoFin = try #require(engine.restEndDate)
        #expect(nuevoFin.timeIntervalSinceNow > 100, "El fin del descanso se corrió hacia adelante")
    }

    @Test("I-08 · Ajustar el descanso queda recordado en el ejercicio")
    func adjustRestPersistsThePreference() throws {
        let db = TestDB()
        let (engine, _) = try engineResting(in: db)
        let press = try #require(engine.currentStep?.exercise)

        engine.adjustRest(by: 15)

        // No es solo para este descanso: el ejercicio se lleva la preferencia, así que
        // la próxima serie del press ya arranca con 105 s. Es deliberado ("lo aprende"),
        // pero conviene saberlo: no hay forma de alargar un descanso "solo por esta vez".
        #expect(press.restSeconds == 105)

        engine.skipRest()
        engine.completeCurrent()
        #expect(engine.restTotal == 105, "La serie siguiente ya usa el descanso ajustado")
    }

    @Test("I-08 · Restar más de lo que queda no deja el descanso en negativo")
    func adjustRestNeverGoesNegative() throws {
        let db = TestDB()
        let (engine, _) = try engineResting(in: db)

        engine.adjustRest(by: -120)   // más de los 90 s que había

        // Dos clamps distintos, a propósito: el remanente baja a 1 s (el descanso se
        // corta ya) pero el total recordado no baja de 15 (para no dejar al ejercicio
        // con un descanso inservible).
        #expect(engine.restRemaining == 1)
        #expect(engine.restTotal == 15)
        #expect(engine.phase == .resting)

        // Efecto colateral de tener dos pisos: el anillo de la UI queda casi vacío.
        #expect(abs(engine.restFraction - 1.0 / 15.0) < 0.001)
    }

    @Test("I-08 · Ajustar el descanso reinicia el tiempo extra")
    func adjustRestResetsOvertime() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        engine.tickRest(now: fin.addingTimeInterval(20))
        #expect(engine.isRestOvertime)

        // "+15" desde el tiempo extra es lo que hacés cuando querés estirar un toque más.
        engine.adjustRest(by: 15)

        #expect(engine.restOvertime == 0)
        #expect(!engine.isRestOvertime)
        #expect(engine.restRemaining >= 1)
    }

    @Test("I-08 · Fuera del descanso, adjustRest no hace nada")
    func adjustRestIsANoOpOutsideResting() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        #expect(engine.phase == .logging)

        let press = day.orderedExercises[0]
        engine.adjustRest(by: 15)

        #expect(engine.restTotal == 0, "Sin descanso en curso no hay nada que ajustar")
        #expect(press.restSeconds == 90, "Y no debería tocar la preferencia del ejercicio")
    }

    // MARK: - I-09

    @Test("I-09 · Volver atrás des-marca la serie para poder recargarla")
    func goingBackUnmarksTheSet() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)
        let press = day.orderedExercises[0]

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        engine.completeCurrent()
        engine.skipRest()
        #expect(engine.index == 1)
        #expect(press.orderedSets[0].isDone)

        engine.goBackFromLogging()

        #expect(engine.index == 0)
        #expect(engine.phase == .logging)

        // Clave: la serie vuelve a estar "sin hacer". Si siguiera marcada, al retomar
        // la sesión más tarde el engine la saltearía y perderías la corrección.
        #expect(!press.orderedSets[0].isDone)
    }

    @Test("I-09 · En la primera serie no hay a dónde volver")
    func goingBackAtTheFirstStepDoesNothing() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        var cambios = 0
        engine.onStateChanged = { cambios += 1 }

        engine.goBackFromLogging()

        #expect(engine.index == 0)

        // ⚠️ Y **no emite `onStateChanged`**: el iPhone no recibe eco de que apretó un
        // botón que no hizo nada. No es un bug —el estado no cambió, así que no hay
        // nada que difundir— pero significa que la Live Activity no puede distinguir
        // "no llegó el comando" de "llegó y era no-op". Queda escrito.
        #expect(cambios == 0)
    }

    @Test("I-09 · Volver atrás cruza el límite entre ejercicios")
    func goingBackCrossesExerciseBoundary() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Avanza hasta la primera serie del remo (índice 3).
        for _ in 0..<3 {
            engine.completeCurrent()
            engine.skipRest()
        }
        #expect(engine.currentStep?.exercise.name == "Remo")

        engine.goBackFromLogging()

        // Vuelve a la última serie del press, no a la primera del remo.
        #expect(engine.currentStep?.exercise.name == "Press banca")
        #expect(engine.currentStep?.setNumber == 3)
        #expect(!day.orderedExercises[0].orderedSets[2].isDone)
    }

    // MARK: - I-10

    // Volver atrás **desde el descanso** es otra cosa que volver atrás desde la carga:
    // acá la serie que se quiere corregir es la que se acaba de cargar, o sea la actual.
    // Por eso `goBackFromResting` **no mueve el índice** — solo corta el descanso y
    // devuelve la fase a `.logging`.

    @Test("I-10 · Volver desde el descanso corta el descanso y no mueve el índice")
    func goingBackFromRestKeepsTheIndex() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var descansosTerminados = 0
        var cambios = 0
        engine.onRestEnded = { descansosTerminados += 1 }
        engine.start(day: day, context: db.context)
        engine.onStateChanged = { cambios += 1 }

        engine.completeCurrent()
        #expect(engine.phase == .resting)
        cambios = 0  // el eco de `completeCurrent` ya se contó

        engine.goBackFromResting()

        #expect(engine.phase == .logging)
        #expect(engine.index == 0, "La serie a corregir es la actual, no la anterior")
        #expect(engine.currentStep?.setNumber == 1)

        // El descanso se corta de verdad: sin esto, `tickRest` seguiría corriendo contra
        // una fecha vieja y la notificación local del reloj sonaría en el medio de la
        // corrección.
        #expect(engine.restEndDate == nil)
        #expect(descansosTerminados == 1)
        #expect(cambios == 1)
    }

    @Test("I-10 · La serie corregida sigue marcada como hecha")
    func goingBackFromRestLeavesTheSetDone() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.completeCurrent()
        engine.goBackFromResting()

        // Asimetría deliberada con `goBackFromLogging`, que sí des-marca (ver I-09).
        // Y está bien: la serie **se hizo**, lo que se corrige son sus números, que la
        // UI edita por binding sobre la misma `ExerciseSet`. Si se des-marcara y el
        // usuario abandonara la sesión ahí, al retomar tendría que volver a "hacer" una
        // serie que ya hizo.
        let primera = day.orderedExercises[0].orderedSets[0]
        #expect(primera.isDone)
    }

    @Test("I-10 · Los contadores del descanso quedan con basura del descanso anterior")
    func goingBackFromRestLeavesStaleCounters() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        // 35 s de tiempo extra sobre un descanso de 90 s.
        engine.tickRest(now: fin.addingTimeInterval(35))
        #expect(engine.restOvertime == 35)

        engine.goBackFromResting()

        // ⚠️ Comportamiento actual: `goBackFromResting` limpia `restEndDate` y la fase,
        // pero **no** los tres contadores. Quedan congelados en el último valor del
        // descanso que se acaba de abandonar.
        #expect(engine.phase == .logging)
        #expect(engine.restTotal == 90)
        #expect(engine.restRemaining == 0)
        #expect(engine.restOvertime == 35, "Basura: ya no hay descanso, pero el contador sigue")
    }

    @Test("I-10 · La basura no se filtra al snapshot")
    func staleCountersDoNotLeakIntoTheSnapshot() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)
        engine.tickRest(now: fin.addingTimeInterval(35))

        engine.goBackFromResting()
        let snapshot = engine.makeSnapshot()

        // Esto es lo que hace que la basura de arriba sea inofensiva **hoy**: los dos
        // campos que la Live Activity mira para decidir si dibuja el descanso están en
        // su valor de reposo, porque `makeSnapshot` los deriva de la fase, no de los
        // contadores.
        #expect(snapshot.phase == .logging)
        #expect(snapshot.restEndDate == nil)
        #expect(!snapshot.isOvertime)

        // El único que viaja crudo es `restTotal`. No molesta mientras el consumidor lo
        // use solo junto con `restEndDate` — que es lo que hace hoy. Si mañana alguien lo
        // usa suelto (para dibujar un anillo, por ejemplo), va a leer los 90 s de un
        // descanso que ya no existe. Por eso el contrato correcto es limpiarlos acá.
        #expect(snapshot.restTotal == 90)
    }

    @Test("I-10 · El próximo descanso arranca limpio, sin arrastrar el tiempo extra")
    func theNextRestStartsClean() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        // Se va a tiempo extra, vuelve atrás a corregir la serie...
        engine.tickRest(now: fin.addingTimeInterval(35))
        engine.goBackFromResting()

        var avisos = 0
        engine.onRestAlert = { avisos += 1 }

        // ...y vuelve a confirmarla: arranca un descanso nuevo.
        engine.completeCurrent()
        #expect(engine.phase == .resting)

        // `startRest` reinicia los tres contadores, así que la basura de I-10 es
        // transitoria: no sobrevive al próximo descanso.
        #expect(engine.restTotal == 90)
        #expect(engine.restRemaining == 90)
        #expect(engine.restOvertime == 0)

        // Y el umbral del aviso también se reinicia. Si `nextOvertimeAlert` hubiera
        // quedado en 40 (el que dejó el tiempo extra anterior), este primer aviso a los
        // 5 s de excedido **no sonaría**: el usuario se quedaría esperando una vibración
        // que llegaría 35 s tarde.
        let nuevoFin = try #require(engine.restEndDate)
        engine.tickRest(now: nuevoFin.addingTimeInterval(5))
        #expect(avisos == 1)
    }

    @Test("I-10 · Llamarlo fuera del descanso no rompe nada")
    func goingBackFromRestOutsideRestIsHarmless() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var descansosTerminados = 0
        engine.onRestEnded = { descansosTerminados += 1 }
        engine.start(day: day, context: db.context)

        // A diferencia de `skipRest` (ver I-11), `goBackFromResting` **no valida la fase**
        // pero tampoco la necesita: en `.logging` no avanza el índice ni des-marca nada,
        // así que lo peor que hace es emitir un `onRestEnded` de más — que cancela una
        // notificación que no existe. `apply(.goBack)` igual lo protege con un `if`.
        engine.goBackFromResting()

        #expect(engine.phase == .logging)
        #expect(engine.index == 0)
        #expect(descansosTerminados == 1, "Emite el efecto igual, aunque no había descanso")
    }

    // MARK: - I-11

    // ⚠️ **Bug 5.** `skipRest()` **no valida la fase**: es literalmente `onRestEnded` +
    // `advance()`. Llamado fuera del descanso, `advance()` mueve el índice igual — y como
    // saltearse el descanso y saltearse la serie son la misma operación, en `.logging` te
    // comés una serie entera sin registrarla.
    //
    // **No es alcanzable hoy** (ver el último test de la sección): las tres UIs solo
    // muestran el botón dentro de la vista de descanso, y `apply(_:)` lo protege con un
    // `if`. Pero el método es `public` y el agujero está a un call site de distancia, así
    // que los tests quedan de guardia.

    @Test("I-11 · ⚠️ skipRest en fase de carga saltea la serie sin registrarla")
    func skipRestWhileLoggingSkipsTheSet() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        #expect(engine.phase == .logging)

        engine.skipRest()

        // Avanzó igual, sin descanso de por medio y sin pasar por `completeCurrent`.
        #expect(engine.index == 1)
        #expect(engine.currentStep?.setNumber == 2)

        // Y la serie 1 quedó sin marcar: al retomar la sesión `firstIncompleteIndex` va a
        // mandar al usuario de vuelta a ella. La serie no se "perdió" en el sentido de
        // borrarse — se perdió en el sentido de que la sesión siguió de largo sin ella.
        #expect(!day.orderedExercises[0].orderedSets[0].isDone)

        // ⚠️ Hallazgo aparte: `loggedSetsCount` **no** sirve para detectar esto, porque
        // no cuenta series confirmadas sino series "con datos" (`reps != nil || weight
        // != nil`) — y el prellenado ya les puso las reps objetivo. Acá da 2 (la serie
        // salteada y la actual) sin que el usuario haya confirmado ninguna. Es el número
        // que la Live Activity muestra como "series cargadas". Ver I-20.
        #expect(engine.loggedSetsCount == 2, "Cuenta las prellenadas, no las confirmadas")
    }

    @Test("I-11 · ⚠️ skipRest en la última serie deja la sesión en un callejón sin salida")
    func skipRestOnTheLastSetStrandsTheSession() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Llega a la última serie (índice 4 de 5) por el camino normal.
        for _ in 0..<4 {
            engine.completeCurrent()
            engine.skipRest()
        }
        #expect(engine.index == 4)
        #expect(engine.isLastStep)
        #expect(engine.phase == .logging)

        engine.skipRest()

        // Este es el peor caso del bug 5, y es peor que saltearse una serie: el índice se
        // va **fuera del arreglo**. `advance()` no valida el borde y `finish()` nunca se
        // llama, así que la sesión queda ni cargando ni terminada.
        #expect(engine.index == 5)
        #expect(engine.currentStep == nil)
        #expect(engine.phase == .logging, "No terminó: `finish()` solo se llama desde `completeCurrent`")
        #expect(day.isCompleted == false)

        // Y no hay forma de salir hacia adelante: `completeCurrent` arranca con un
        // `guard let step = currentStep` y se va sin hacer nada. La sesión queda
        // colgada — la única salida es volver atrás.
        engine.completeCurrent()
        #expect(engine.index == 5)
        #expect(engine.phase == .logging)

        engine.goBackFromLogging()
        #expect(engine.index == 4)
        #expect(engine.currentStep != nil, "Volver atrás es la única salida del callejón")
    }

    @Test("I-11 · ⚠️ skipRest después de terminar revive la sesión")
    func skipRestAfterFinishingResurrectsTheSession() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        for _ in 0..<4 {
            engine.completeCurrent()
            engine.skipRest()
        }
        engine.completeCurrent()
        #expect(engine.phase == .done)
        #expect(day.isCompleted)

        engine.skipRest()

        // La misma falta de validación, del otro lado: `advance()` pisa la fase `.done`
        // con `.logging`. La pantalla de "sesión terminada" se iría, y quedaría el mismo
        // callejón sin salida del test anterior (el día sí queda completado, eso no se
        // revierte).
        #expect(engine.phase == .logging, "⚠️ Deshizo el `.done`")
        #expect(engine.currentStep == nil)
        #expect(day.isCompleted, "Al menos el día sigue completado")
    }

    @Test("I-11 · El comando remoto sí valida la fase: por eso el bug no es alcanzable")
    func theRemoteCommandGuardsThePhase() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()
        #expect(engine.phase == .logging)

        // Este es el camino por el que un `skipRest` podría llegar en un momento
        // inesperado: el botón de la Live Activity dibuja un snapshot que puede estar
        // viejo, así que el iPhone puede mandar "saltear descanso" cuando el reloj ya
        // salió del descanso. `apply(_:)` lo filtra al recibirlo.
        engine.apply(LiveSessionCommand(sessionID: engine.sessionID, action: .skipRest))

        #expect(engine.index == 0, "El comando se descartó: la fase no era `.resting`")
        #expect(!day.orderedExercises[0].orderedSets[0].isDone)

        // Esa guarda es lo único que separa al bug 5 de ser un bug de verdad. Si alguien
        // agrega un call site nuevo fuera de la vista de descanso, los tests de arriba
        // dicen exactamente qué se rompe.
    }

    // MARK: - I-12

    // "Traer al siguiente" resuelve un problema del gimnasio, no del software: la máquina
    // del ejercicio que venía está ocupada, así que se intercala otro del plan. Es la única
    // operación que **reordena el modelo en caliente**, en el medio de una sesión con datos
    // ya cargados — de ahí que lo importante no sea el orden nuevo sino lo que NO se toca.

    @Test("I-12 · Traer un ejercicio al siguiente lo mueve justo después del actual")
    func bringingAnExerciseNextReordersTheDay() {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var cambios = 0
        engine.start(day: day, context: db.context)
        engine.onStateChanged = { cambios += 1 }

        let sentadilla = day.orderedExercises[2]
        engine.bringExerciseNext(sentadilla)

        // La sentadilla salta del último lugar al segundo: queda justo detrás del press,
        // que es el que se está haciendo.
        #expect(day.orderedExercises.map(\.name) == ["Press banca", "Sentadilla", "Remo"])
        #expect(cambios == 1)
    }

    @Test("I-12 · El orden nuevo queda persistido en el modelo, no solo en los pasos")
    func theNewOrderIsPersisted() {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.bringExerciseNext(day.orderedExercises[2])

        // `orderedExercises` ordena por el campo `order`, así que si el engine solo
        // reacomodara su arreglo de pasos, el cambio se perdería al cerrar la sesión —
        // y peor, el día quedaría con `order` duplicados. Se reasignan los tres, 0..2.
        let porNombre = Dictionary(uniqueKeysWithValues: day.orderedExercises.map { ($0.name, $0.order) })
        #expect(porNombre["Press banca"] == 0)
        #expect(porNombre["Sentadilla"] == 1)
        #expect(porNombre["Remo"] == 2)

        // Y sobrevive a rearmar la sesión desde cero (lee del modelo, no de memoria).
        let retomado = GuidedSessionEngine()
        retomado.start(day: day, context: db.context)
        #expect(retomado.steps.map(\.exercise.name) == [
            "Press banca", "Press banca", "Sentadilla", "Sentadilla", "Remo", "Remo",
        ])
    }

    @Test("I-12 · Reordenar no pierde lo ya registrado ni mueve al usuario de su serie")
    func reorderingPreservesLoggedDataAndPosition() throws {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Carga la primera serie del press con datos reales y la confirma.
        let press = day.orderedExercises[0]
        press.orderedSets[0].weight = 60
        press.orderedSets[0].reps = 8
        engine.completeCurrent()
        engine.skipRest()

        // Ahora está en la serie 2 del press. Acá es donde el usuario ve que la máquina
        // del remo está ocupada y trae la sentadilla.
        #expect(engine.currentStep?.exercise.name == "Press banca")
        #expect(engine.currentStep?.setNumber == 2)
        let serieActual = try #require(engine.currentStep?.set)

        engine.bringExerciseNext(day.orderedExercises[2])

        // Esto es lo que hace que la operación sea segura: `buildSteps` rearma los pasos
        // desde cero, así que el engine tiene que **reencontrar** al usuario. Lo hace
        // buscando la misma `ExerciseSet` por identidad, no por índice — si buscara por
        // índice, el usuario aparecería en otra serie después de reordenar.
        #expect(engine.currentStep?.exercise.name == "Press banca")
        #expect(engine.currentStep?.setNumber == 2)
        #expect(engine.currentStep?.set === serieActual)
        #expect(engine.phase == .logging)

        // Y lo registrado sigue ahí: el reordenado toca `order`, nunca los datos.
        #expect(press.orderedSets[0].isDone)
        #expect(press.orderedSets[0].weight == 60)
        #expect(press.orderedSets[0].reps == 8)

        // El que cambia es lo que sigue: al terminar el press ahora viene la sentadilla.
        engine.completeCurrent()
        engine.skipRest()
        #expect(engine.currentStep?.exercise.name == "Sentadilla")
    }

    @Test("I-12 · Traer un ejercicio que ya estaba justo detrás no cambia nada")
    func bringingTheAlreadyNextExerciseIsANoOp() {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // El remo ya es el que sigue. Traerlo "al siguiente" es pedir lo que ya pasa.
        engine.bringExerciseNext(day.orderedExercises[1])

        #expect(day.orderedExercises.map(\.name) == ["Press banca", "Remo", "Sentadilla"])
        #expect(engine.index == 0)
    }

    // MARK: - I-13

    // El momento real de uso es **durante el descanso**: terminaste una serie, estás
    // esperando, ves que la máquina del que sigue está ocupada y elegís otro. Por eso lo
    // que importa acá es que reordenar **no toque el cronómetro**: si cortara el descanso,
    // elegir el próximo ejercicio te costaría el descanso que estabas haciendo.

    @Test("I-13 · Reordenar durante el descanso no corta el descanso")
    func reorderingDuringRestDoesNotStopTheRest() throws {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var descansosTerminados = 0
        var descansosArrancados = 0
        engine.onRestEnded = { descansosTerminados += 1 }
        engine.onRestStarted = { _ in descansosArrancados += 1 }
        engine.start(day: day, context: db.context)

        engine.completeCurrent()
        #expect(engine.phase == .resting)
        let finDelDescanso = try #require(engine.restEndDate)
        descansosArrancados = 0

        engine.bringExerciseNext(day.orderedExercises[2])

        // La fase y el cronómetro quedan intactos: misma fecha de fin, mismos segundos.
        // Ni se corta ni se reinicia.
        #expect(engine.phase == .resting)
        #expect(engine.restEndDate == finDelDescanso)
        #expect(engine.restTotal == 60)
        #expect(descansosTerminados == 0, "Cortar el descanso acá sería el peor efecto posible")
        #expect(descansosArrancados == 0, "Y reiniciarlo, el segundo peor")

        // El reordenado sí pasó.
        #expect(day.orderedExercises.map(\.name) == ["Press banca", "Sentadilla", "Remo"])
    }

    @Test("I-13 · Reordenar durante el descanso reubica el índice sin mover al usuario")
    func reorderingDuringRestRelocatesTheIndex() throws {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Va hasta la **última** serie del press y la completa: recién ahí el "Sigue" es
        // otro ejercicio, que es el caso donde traer uno nuevo tiene sentido.
        engine.completeCurrent()
        engine.skipRest()
        let ultimaSerieDelPress = try #require(engine.currentStep?.set)
        engine.completeCurrent()

        #expect(engine.phase == .resting)
        #expect(engine.index == 1)
        #expect(engine.nextStep?.exercise.name == "Remo")

        engine.bringExerciseNext(day.orderedExercises[2])

        // El índice se recalcula sobre los pasos nuevos, pero apunta a la misma serie
        // (la que se acaba de completar). El usuario no se movió.
        #expect(engine.index == 1)
        #expect(engine.currentStep?.set === ultimaSerieDelPress)
        #expect(engine.currentStep?.set?.isDone == true)

        // Lo único que cambió es lo que viene: la sentadilla, no el remo. Es exactamente
        // lo que el usuario pidió, y es lo que la UI muestra como "Sigue".
        #expect(engine.nextStep?.exercise.name == "Sentadilla")

        // Y al cortar el descanso cae en el ejercicio nuevo.
        engine.skipRest()
        #expect(engine.currentStep?.exercise.name == "Sentadilla")
        #expect(engine.phase == .logging)
    }

    @Test("I-13 · Traer el ejercicio actual es un no-op silencioso")
    func bringingTheCurrentExerciseIsANoOp() {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        var cambios = 0
        engine.onStateChanged = { cambios += 1 }

        let press = day.orderedExercises[0]
        engine.bringExerciseNext(press)

        // Sale por el `guard exercise !== currentExercise`. Importa que salga **antes** de
        // reasignar los `order`: moverse a sí mismo "justo después de sí mismo" es un
        // pedido incoherente, y el algoritmo (sacar de la lista, insertar tras el actual)
        // no está definido para ese caso.
        #expect(day.orderedExercises.map(\.name) == ["Press banca", "Remo", "Sentadilla"])
        #expect(engine.index == 0)
        #expect(cambios == 0)
    }

    @Test("I-13 · La UI no ofrece el actual ni los ejercicios ya terminados")
    func switchableExercisesExcludesCurrentAndFinished() {
        let db = TestDB()
        let day = dayWithThreeExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // `switchableExercises` es la lista que la UI muestra en "Cambiar ejercicio": es
        // la que impide que el no-op de arriba sea siquiera alcanzable desde un botón.
        #expect(engine.switchableExercises.map(\.name) == ["Remo", "Sentadilla"])

        // Un ejercicio con todas sus series hechas deja de ser candidato: traerlo al
        // frente no haría nada útil (no tiene series pendientes que hacer).
        let remo = day.orderedExercises[1]
        for serie in remo.orderedSets { serie.isDone = true }

        #expect(engine.switchableExercises.map(\.name) == ["Sentadilla"])
    }

    // MARK: - I-14

    // ⚠️ **Bug 6.** `bringExerciseNext` no valida que el ejercicio **pertenezca al día**.
    // El algoritmo es: sacarlo de la lista del día, insertarlo detrás del actual, y
    // reasignar los `order` de la lista resultante. Con un ejercicio ajeno, el "sacarlo"
    // no hace nada (no estaba) pero el "insertarlo" sí — y la reasignación de `order`
    // **le escribe encima al ejercicio de otro día**.
    //
    // El daño no se ve en la sesión en curso: `buildSteps` lee de `day.exercises`, así que
    // el intruso no aparece en los pasos. El daño queda **en el otro día**, esperando.
    //
    // **No es alcanzable hoy**: los dos call sites (reloj e iPhone) recorren
    // `switchableExercises`, que solo devuelve ejercicios del día actual. El bug vive
    // enteramente en la falta de un `guard`.

    @Test("I-14 · ⚠️ Un ejercicio de otro día le pisa el orden a ese otro día")
    func bringingAForeignExerciseCorruptsTheOtherDay() {
        let db = TestDB()
        let lunes = dayWithThreeExercises(in: db.context)

        // Otro día del plan, con su propio orden sano: 0, 1, 2.
        let miercoles = makeDay(date(2026, 7, 3), type: .fuerza, title: "Fuerza B", in: db.context)
        for (i, nombre) in ["Dominadas", "Curl", "Peso muerto"].enumerated() {
            makeExercise(nombre, on: miercoles, order: i, sets: [(nil, nil)], in: db.context)
        }
        #expect(miercoles.orderedExercises.map(\.order) == [0, 1, 2])

        let engine = GuidedSessionEngine()
        engine.start(day: lunes, context: db.context)

        // Se trae el peso muerto (del miércoles) a la sesión del lunes.
        let pesoMuerto = miercoles.orderedExercises[2]
        engine.bringExerciseNext(pesoMuerto)

        // La sesión del lunes ni se entera: `buildSteps` lee de `lunes.exercises`, y el
        // peso muerto no está ahí. El usuario no ve nada raro.
        #expect(engine.steps.allSatisfy { $0.exercise.name != "Peso muerto" })
        #expect(engine.currentStep?.exercise.name == "Press banca")

        // Pero al peso muerto le reescribieron el `order`: pasó de 2 a 1, el lugar que le
        // tocaba "detrás del press" en la lista del lunes. Y ahora **choca con el curl**,
        // que también tiene order 1.
        #expect(pesoMuerto.order == 1)
        let ordenesDelMiercoles = miercoles.orderedExercises.map(\.order)
        #expect(ordenesDelMiercoles == [0, 1, 1], "⚠️ El miércoles quedó con dos ejercicios en el mismo orden")

        // Esto es lo que lo hace un bug de verdad y no un detalle cosmético:
        // `orderedExercises` ordena por `order`, y `sorted` **no garantiza estabilidad** en
        // Swift. Con dos ejercicios empatados, el orden del miércoles queda indefinido: la
        // próxima vez que se abra ese día, curl y peso muerto pueden salir en cualquier
        // orden — y la sesión guiada los va a proponer en ese orden.
        let nombres = Set(miercoles.orderedExercises.map(\.name))
        #expect(nombres == ["Dominadas", "Curl", "Peso muerto"], "No se pierde ninguno, solo se desordenan")
    }

    @Test("I-14 · ⚠️ Y de paso le abre huecos al orden del día actual")
    func bringingAForeignExerciseLeavesGapsInTheCurrentDay() {
        let db = TestDB()
        let lunes = dayWithThreeExercises(in: db.context)

        let otroDia = makeDay(date(2026, 7, 3), type: .fuerza, title: "Fuerza B", in: db.context)
        let ajeno = makeExercise("Dominadas", on: otroDia, order: 0, sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: lunes, context: db.context)
        engine.bringExerciseNext(ajeno)

        // El intruso ocupó el índice 1 al reasignar, así que los del lunes se corrieron:
        // quedan 0, 2, 3 en vez de 0, 1, 2. No rompe nada (el orden relativo se mantiene y
        // `orderedExercises` solo compara), pero es basura persistida.
        #expect(lunes.orderedExercises.map(\.name) == ["Press banca", "Remo", "Sentadilla"])
        #expect(lunes.orderedExercises.map(\.order) == [0, 2, 3], "⚠️ Huecos en el orden")
    }

    @Test("I-14 · Lo que contiene el bug: la UI solo ofrece ejercicios del día")
    func theUIOnlyOffersExercisesFromTheCurrentDay() {
        let db = TestDB()
        let lunes = dayWithThreeExercises(in: db.context)

        let otroDia = makeDay(date(2026, 7, 3), type: .fuerza, title: "Fuerza B", in: db.context)
        makeExercise("Dominadas", on: otroDia, order: 0, sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: lunes, context: db.context)

        // Los dos call sites de `bringExerciseNext` (reloj e iPhone) hacen `ForEach` sobre
        // esta lista, y sale de `day.orderedExercises`. Por eso el bug 6 no es alcanzable:
        // no hay forma de elegir un ejercicio ajeno desde la app.
        #expect(engine.switchableExercises.map(\.name) == ["Remo", "Sentadilla"])
        #expect(!engine.switchableExercises.contains { $0.name == "Dominadas" })

        // El `guard` que falta sería `day.orderedExercises.contains { $0 === exercise }`.
        // Hoy lo suple la UI, que es una garantía por convención, no por tipo.
    }

    // MARK: - I-15

    // Retomar es el caso normal: la sesión de gimnasio se interrumpe (te llaman, se cierra
    // la app, se queda sin batería el reloj) y al volver hay que caer en la serie donde se
    // dejó. `firstIncompleteIndex` es quien decide dónde.

    @Test("I-15 · Retomar cae en la primera serie incompleta, no en la última hecha")
    func resumingLandsOnTheFirstIncompleteSet() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        // Se hicieron las dos primeras series del press. Queda la tercera.
        let press = day.orderedExercises[0]
        press.orderedSets[0].isDone = true
        press.orderedSets[1].isDone = true

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.index == 2)
        #expect(engine.currentStep?.exercise.name == "Press banca")
        #expect(engine.currentStep?.setNumber == 3)
        #expect(engine.phase == .logging)
    }

    @Test("I-15 · Con un hueco en el medio, retomar vuelve al hueco")
    func resumingGoesBackToTheGap() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        // Escenario raro pero posible (se volvió atrás y se abandonó ahí): la serie 1 y la
        // 3 están hechas, la 2 no.
        let press = day.orderedExercises[0]
        press.orderedSets[0].isDone = true
        press.orderedSets[2].isDone = true

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Es `firstIndex`, no `lastIndex`: manda al hueco. Correcto — la serie 2 es la que
        // falta, y saltarla dejaría la sesión incompleta para siempre.
        #expect(engine.index == 1)
        #expect(engine.currentStep?.setNumber == 2)
    }

    @Test("I-15 · ⚠️ Con todas las series hechas, reabrir la sesión la reinicia desde cero")
    func reopeningAFinishedSessionRestartsIt() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        // Un día ya terminado: todas las series hechas, con sus datos.
        for ejercicio in day.orderedExercises {
            for serie in ejercicio.orderedSets {
                serie.weight = 60
                serie.reps = 8
                serie.isDone = true
            }
        }
        day.isCompleted = true

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // ⚠️ `firstIncompleteIndex` hace `firstIndex { ... } ?? 0`: cuando **no encuentra**
        // ninguna serie pendiente devuelve 0, que es indistinguible de "la primera está
        // pendiente". Así que la sesión arranca en la serie 1, en fase de carga, sobre un
        // día que ya está completo.
        #expect(engine.index == 0)
        #expect(engine.phase == .logging, "⚠️ Debería arrancar en `.done`")
        #expect(engine.currentStep?.setNumber == 1)

        // Y esto **es alcanzable**: el botón "Empezar sesión guiada" de `GymSessionView` no
        // está condicionado por `isCompleted`. Reabrir un día terminado te pone de nuevo en
        // la serie 1, con el botón de completar listo, como si no hubieras entrenado.
        #expect(engine.currentStep?.set?.isDone == true, "La serie que muestra ya estaba hecha")

        // Los datos no se pierden (el prellenado nunca pisa lo cargado)...
        #expect(engine.currentStep?.set?.weight == 60)
        #expect(engine.currentStep?.set?.reps == 8)

        // ...pero si el usuario sigue el flujo que la app le propone, arranca un descanso y
        // rehace la sesión entera. El día ya estaba completo: no hay nada que hacer acá.
        engine.completeCurrent()
        #expect(engine.phase == .resting, "⚠️ Descanso de 90 s sobre una serie hecha hace rato")
    }

    @Test("I-15 · La sesión completada desde adentro sí termina en done")
    func aSessionCompletedInPlaceEndsInDone() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // El contraste que muestra dónde está el problema: recorrida de punta a punta, la
        // sesión termina bien en `.done`. `phase = .done` lo pone `finish()`, y `finish()`
        // solo se llama desde `completeCurrent`. Nadie lo deriva del estado del día al
        // arrancar — por eso reabrir no lo recupera.
        for _ in 0..<4 {
            engine.completeCurrent()
            engine.skipRest()
        }
        engine.completeCurrent()

        #expect(engine.phase == .done)
        #expect(day.isCompleted)

        // Pero un engine nuevo sobre el mismo día (o sea: cerrar y volver a entrar) ya no
        // lo sabe. La fase `.done` vive solo en memoria.
        let reabierto = GuidedSessionEngine()
        reabierto.start(day: day, context: db.context)
        #expect(reabierto.phase == .logging, "⚠️ El `.done` no sobrevive a cerrar la sesión")
        #expect(reabierto.index == 0)
    }

    // MARK: - I-16

    // El otro lado del mismo `?? 0` del bug 12: un día **sin ejercicios**. Acá el engine no
    // se equivoca de serie — directamente no tiene ninguna, y el resultado es una sesión
    // que **no puede terminar**.
    //
    // **No es alcanzable**: las dos plataformas lo gatean antes de entrar (`GymSessionView`
    // muestra su `emptyState`, el reloj muestra "Sin ejercicios cargados"). Los tests fijan
    // el borde por si algún día se entra por otro lado.

    @Test("I-16 · ⚠️ Un día sin ejercicios arma una sesión que no puede terminar")
    func anEmptyDayCannotFinish() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, title: "Fuerza A", in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.steps.isEmpty)
        #expect(engine.currentStep == nil)
        #expect(engine.progressFraction == 0)

        // ⚠️ `isLastStep` es `index >= steps.count - 1` → `0 >= -1` → **true**. O sea: el
        // engine cree estar parado en el último paso de una lista vacía. Es coherente con la
        // aritmética y absurdo con la realidad.
        #expect(engine.isLastStep, "⚠️ 0 >= -1: el último paso de una lista vacía")

        // Pero `completeCurrent` arranca con `guard let step = currentStep`, así que ese
        // "último paso" no se puede completar: `finish()` nunca corre.
        engine.completeCurrent()

        #expect(engine.phase == .logging, "⚠️ La sesión no llega nunca a `.done`")
        #expect(!day.isCompleted, "⚠️ Y el día no se marca como hecho")

        // La sesión queda en un limbo: sin nada que mostrar y sin forma de cerrarse desde
        // adentro. La única salida es el botón de cerrar de la vista.
    }

    @Test("I-16 · Un día con solo un ejercicio de core sí termina")
    func aDayWithOnlyACoreExerciseFinishes() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, title: "Fuerza A", in: db.context)

        // El contraste que aísla el problema. Un ejercicio sin series (plancha, core) **sí**
        // ocupa un paso —ver I-01—, así que `steps` no queda vacío y `completeCurrent`
        // encuentra algo. La diferencia no es "tener series", es "tener pasos".
        makeExercise("Plancha", on: day, order: 0, targetReps: "30 s", in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(engine.steps.count == 1)
        #expect(engine.isLastStep)

        engine.completeCurrent()

        #expect(engine.phase == .done)
        #expect(day.isCompleted)
    }

    @Test("I-16 · Lo que contiene el bug: ninguna de las dos apps deja entrar")
    func bothPlatformsGateTheEmptyDay() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, title: "Fuerza A", in: db.context)

        // `GymSessionView` (iPhone) muestra su `emptyState` en vez del botón, y
        // `WatchWorkoutView` (reloj) muestra "Sin ejercicios cargados". Las dos preguntan lo
        // mismo: `day.orderedExercises.isEmpty`. Este test fija esa condición, que es la que
        // sostiene la guarda de las dos UIs.
        #expect(day.orderedExercises.isEmpty)

        // Con un ejercicio, las dos abren la sesión.
        makeExercise("Press banca", on: day, order: 0, sets: [(nil, nil)], in: db.context)
        #expect(!day.orderedExercises.isEmpty)
    }

    // MARK: - I-17

    // El prellenado es lo que hace que registrar una serie sea **un solo tap**: al llegar a
    // una serie, las reps ya están en el objetivo del plan y el peso en el último que usaste.
    // Solo tocás la rueda si no llegaste al objetivo o si subiste el peso.
    //
    // Su regla no negociable: **nunca pisa lo que el usuario cargó**. Un prellenado que
    // sobrescribe no ahorra un tap, borra un dato.

    @Test(
        "I-17 · Las reps se prellenan con el objetivo del plan",
        arguments: [
            // Un rango se prellena con el **máximo**: es la meta a alcanzar, y la rueda solo
            // se toca para bajar si no se llegó. Prellenar con el mínimo obligaría a subirla
            // siempre que el entrenamiento salga bien.
            ("6-8", 8),
            ("10-12", 12),
            // Un número solo.
            ("10", 10),
            // Objetivo en tiempo (plancha, isométricos): el campo cuenta segundos.
            ("30 s", 30),
        ]
    )
    func repsArePrefilledWithThePlanTarget(target: String, expected: Int) throws {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        makeExercise("Press banca", on: day, order: 0, targetReps: target,
                     sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        #expect(try #require(engine.currentStep?.set).reps == expected)
    }

    @Test("I-17 · Sin objetivo en el plan, las reps quedan vacías")
    func noTargetLeavesRepsEmpty() throws {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        // Un ejercicio cargado a mano, sin `targetReps`.
        makeExercise("Press banca", on: day, order: 0, sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // No se inventa un número: la rueda arranca vacía y la carga el usuario.
        #expect(try #require(engine.currentStep?.set).reps == nil)
    }

    @Test("I-17 · El prellenado nunca pisa lo que el usuario ya cargó")
    func prefillNeverOverwritesUserData() throws {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        // La serie ya tiene datos: es lo que pasa al volver atrás a corregir (I-09/I-10), o
        // al retomar una sesión donde se cargó algo y no se confirmó.
        makeExercise("Press banca", on: day, order: 0, targetReps: "6-8",
                     sets: [(72.5, 5)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Las 5 reps son el dato real (no se llegó a las 8) y los 72,5 kg también. Si el
        // prellenado los pisara con 8 y con el peso de la sesión pasada, el usuario perdería
        // lo que registró sin darse cuenta.
        let serie = try #require(engine.currentStep?.set)
        #expect(serie.reps == 5)
        #expect(serie.weight == 72.5)
    }

    @Test("I-17 · Los ejercicios de peso corporal no reciben peso")
    func bodyweightExercisesGetNoWeight() throws {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        // Este nombre está en el plan como `weighted: false`, así que `tracksWeight` es
        // `false`. Poner un peso acá no significaría nada.
        makeExercise("Abdominales bisagra a dos piernas", on: day, order: 0,
                     targetReps: "12", sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        let serie = try #require(engine.currentStep?.set)
        #expect(serie.reps == 12, "Las reps sí se prellenan")
        #expect(serie.weight == nil, "El peso no")
    }

    @Test("I-17 · Al avanzar, la serie siguiente se prellena con el peso de la anterior")
    func advancingPrefillsTheNextSetWithThePreviousWeight() throws {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Serie 1: el usuario carga 80 kg y confirma.
        let primera = try #require(engine.currentStep?.set)
        primera.weight = 80
        engine.completeCurrent()
        engine.skipRest()

        // Serie 2: llega con los 80 kg puestos y las reps en el objetivo (8, de "6-8"). Este
        // es el caso que hace que la sesión sea un tap por serie — y el motivo por el que el
        // prellenado corre en `advance()`, no solo al arrancar.
        let segunda = try #require(engine.currentStep?.set)
        #expect(segunda.weight == 80)
        #expect(segunda.reps == 8)

        // Y si sube el peso, la tercera lo hereda: el prellenado sigue al último cargado, no
        // al primero.
        segunda.weight = 85
        engine.completeCurrent()
        engine.skipRest()
        #expect(try #require(engine.currentStep?.set).weight == 85)
    }

    @Test("I-17 · El peso no cruza de un ejercicio a otro")
    func weightDoesNotLeakBetweenExercises() throws {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Hace las 3 series del press con 80 kg.
        for _ in 0..<3 {
            engine.currentStep?.set?.weight = 80
            engine.completeCurrent()
            engine.skipRest()
        }

        // Llega al remo: `suggestedWeight` solo mira las series **del mismo ejercicio**, así
        // que no arrastra los 80 kg del press. Sin historial previo del remo, el peso queda
        // vacío. Lo contrario sería peor que no prellenar: un número plausible y equivocado.
        #expect(engine.currentStep?.exercise.name == "Remo")
        let serieDelRemo = try #require(engine.currentStep?.set)
        #expect(serieDelRemo.weight == nil)
        #expect(serieDelRemo.reps == 10, "Las reps sí: salen del objetivo del remo")
    }

    // MARK: - I-18

    // De dónde sale el peso sugerido. Hay dos fuentes y **el orden importa**: primero la
    // serie previa **de esta sesión** (lo que estás levantando hoy), y recién si no hay,
    // el historial (lo que levantaste la última vez que hiciste el ejercicio).
    //
    // Está bien así: si hoy subiste de 70 a 80, la serie que viene tiene que arrancar en 80.
    // El historial sabe menos que la sesión en curso.

    /// Deja registrado en la base que este ejercicio ya se hizo en una fecha anterior, con
    /// los pesos dados. Es el "historial" que mira `ExerciseHistory.lastWeight`.
    @MainActor
    private func historial(
        _ nombre: String, on fecha: Date, weights: [Double?], in context: ModelContext
    ) {
        let dia = makeDay(fecha, type: .fuerza, title: "Fuerza A", in: context)
        makeExercise(nombre, on: dia, order: 0,
                     sets: weights.map { (weight: $0, reps: 8) }, in: context)
    }

    @Test("I-18 · La serie previa de esta sesión le gana al historial")
    func thisSessionBeatsTheHistory() throws {
        let db = TestDB()
        // La última vez el press se hizo con 70 kg.
        historial("Press banca", on: date(2026, 6, 24), weights: [70], in: db.context)

        let hoy = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)

        // La serie 1 llega con los 70 kg del historial: es lo mejor que se sabe al arrancar.
        #expect(engine.currentStep?.set?.weight == 70)

        // Pero hoy el usuario se siente bien y sube a 80.
        engine.currentStep?.set?.weight = 80
        engine.completeCurrent()
        engine.skipRest()

        // La serie 2 tiene que arrancar en 80, no volver a 70. Si el historial le ganara a
        // la sesión en curso, cada serie te haría bajar el peso que acabás de subir.
        #expect(try #require(engine.currentStep?.set).weight == 80)
    }

    @Test("I-18 · Sin nada cargado hoy, el peso sale del historial")
    func theHistoryIsUsedWhenTodayIsEmpty() throws {
        let db = TestDB()
        historial("Press banca", on: date(2026, 6, 24), weights: [72.5], in: db.context)

        let hoy = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)

        #expect(try #require(engine.currentStep?.set).weight == 72.5)
    }

    @Test("I-18 · El historial mira hacia atrás, nunca hacia adelante")
    func theHistoryOnlyLooksBackwards() throws {
        let db = TestDB()
        let hoy = dayWithTwoExercises(in: db.context)

        // Una sesión **futura** ya sembrada por el plan (los días vienen creados de
        // antemano). Si `lastWeight` no filtrara por fecha, un peso cargado ahí —o un día
        // futuro con datos de prueba— se colaría como sugerencia de hoy.
        historial("Press banca", on: date(2026, 7, 8), weights: [100], in: db.context)
        // Y una pasada, que es la que corresponde.
        historial("Press banca", on: date(2026, 6, 24), weights: [70], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)

        #expect(try #require(engine.currentStep?.set).weight == 70, "El futuro no cuenta")
    }

    @Test("I-18 · Del historial toma el peso más alto de esa sesión, no el último")
    func theHistoryTakesTheMaxOfTheSession() throws {
        let db = TestDB()
        // Una sesión en pirámide: subió a 80 y bajó a 65 en la última serie (fatiga).
        historial("Press banca", on: date(2026, 6, 24), weights: [70, 80, 65], in: db.context)

        let hoy = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)

        // Sugiere 80, no 65. Es una decisión de producto, no un descuido: el máximo es tu
        // tope real en ese ejercicio; el último peso puede ser una serie de descarga. Vale
        // dejarlo escrito porque el efecto es que la sugerencia **no baja** cuando aflojás
        // el final de la sesión.
        #expect(try #require(engine.currentStep?.set).weight == 80)
    }

    @Test("I-18 · Saltea las sesiones donde no se anotó peso")
    func sessionsWithoutWeightAreSkipped() throws {
        let db = TestDB()
        // La sesión más reciente existe pero quedó sin pesos (se tildaron las series y
        // listo). La anterior sí tiene.
        historial("Press banca", on: date(2026, 6, 24), weights: [nil, nil], in: db.context)
        historial("Press banca", on: date(2026, 6, 17), weights: [65], in: db.context)

        let hoy = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)

        // Sigue buscando hacia atrás en vez de rendirse en la primera sesión sin datos.
        #expect(try #require(engine.currentStep?.set).weight == 65)
    }

    @Test("I-18 · ⚠️ Solo mira 10 sesiones para atrás")
    func theHistoryOnlyLooksBackTenSessions() throws {
        let db = TestDB()

        // 10 sesiones seguidas sin peso anotado...
        for semana in 0..<10 {
            historial("Press banca", on: date(2026, 6, 24).addingTimeInterval(-Double(semana) * 86_400),
                      weights: [nil], in: db.context)
        }
        // ...y la 11ª, la única con un peso.
        historial("Press banca", on: date(2026, 6, 1), weights: [65], in: db.context)

        let hoy = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)

        // ⚠️ `lastWeight` tiene `fetchLimit = 10`: si las 10 sesiones más recientes del
        // ejercicio no tienen peso, no mira más atrás y devuelve `nil`. En la práctica no
        // molesta (nadie hace 10 sesiones seguidas sin anotar el peso), pero es un límite
        // real y silencioso: la sugerencia desaparece sin explicación.
        #expect(engine.currentStep?.set?.weight == nil, "El peso de la 11ª sesión no se alcanza")
    }

    @Test("I-18 · Si la serie ya tiene peso, no se sugiere nada")
    func noSuggestionWhenTheSetAlreadyHasWeight() throws {
        let db = TestDB()
        historial("Press banca", on: date(2026, 6, 24), weights: [70], in: db.context)

        let hoy = dayWithTwoExercises(in: db.context)
        let engine = GuidedSessionEngine()
        engine.start(day: hoy, context: db.context)
        let paso = try #require(engine.currentStep)

        // `suggestedWeight` sale por `guard set.weight == nil`. Es la otra mitad de la regla
        // de I-17 ("nunca pisa lo cargado"), y es lo que la UI usa para decidir si muestra
        // la sugerencia como un valor tentativo.
        #expect(engine.suggestedWeight(for: paso) == nil, "Ya tiene los 70 del prellenado")
    }

    // MARK: - I-19

    // `apply(_:)` es la **superficie remota** del engine: por acá entran los botones del
    // espejo del iPhone y de la Live Activity. Es la única entrada que no controla la vista
    // del reloj, y por eso es la única que tiene que defenderse sola.
    //
    // De qué se defiende: el que manda el comando dibuja un **snapshot que puede estar
    // viejo**. Entre que el iPhone pinta el botón y que el reloj recibe el toque hay un
    // viaje de WatchConnectivity — cientos de milisegundos en los que el reloj puede haber
    // cambiado de fase solo.

    @Test("I-19 · Un comando de otra sesión se ignora")
    func commandsFromAnotherSessionAreIgnored() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()

        // Pasa de verdad: la Live Activity de una sesión de ayer que quedó sin cerrar, o el
        // espejo abierto en otro día. Sin este filtro, un botón viejo movería la sesión de
        // hoy.
        engine.apply(LiveSessionCommand(sessionID: UUID(), action: .completeCurrent))

        #expect(engine.index == 0)
        #expect(engine.phase == .logging)
        #expect(!day.orderedExercises[0].orderedSets[0].isDone)
    }

    @Test("I-19 · Los comandos hacen lo mismo que los métodos directos")
    func remoteCommandsMatchTheDirectMethods() throws {
        let db = TestDB()

        // Espejo: el mismo día, dos engines. Uno se maneja con los métodos (como el reloj),
        // el otro solo con comandos remotos (como si todo viniera del iPhone). Tienen que
        // terminar en el mismo estado.
        let directoDay = dayWithTwoExercises(in: db.context)
        let directo = GuidedSessionEngine()
        directo.start(day: directoDay, context: db.context)

        let remotoDay = dayWithTwoExercises(in: db.context)
        let remoto = GuidedSessionEngine()
        remoto.start(day: remotoDay, context: db.context)
        remoto.beginLiveSession()
        let id = remoto.sessionID

        // Completar la serie.
        directo.completeCurrent()
        remoto.apply(LiveSessionCommand(sessionID: id, action: .completeCurrent))
        #expect(remoto.phase == directo.phase)
        #expect(remoto.index == directo.index)

        // Ajustar el descanso.
        directo.adjustRest(by: 15)
        remoto.apply(LiveSessionCommand(sessionID: id, action: .adjustRest(15)))
        #expect(remoto.restTotal == directo.restTotal)
        #expect(remoto.restTotal == 105)

        // Volver atrás (desde el descanso: no mueve el índice, ver I-10).
        directo.goBackFromResting()
        remoto.apply(LiveSessionCommand(sessionID: id, action: .goBack))
        #expect(remoto.phase == directo.phase)
        #expect(remoto.phase == .logging)
        #expect(remoto.index == directo.index)

        // Saltear el descanso.
        directo.completeCurrent()
        remoto.apply(LiveSessionCommand(sessionID: id, action: .completeCurrent))
        directo.skipRest()
        remoto.apply(LiveSessionCommand(sessionID: id, action: .skipRest))
        #expect(remoto.phase == directo.phase)
        #expect(remoto.index == directo.index)
        #expect(remoto.index == 1)
    }

    @Test("I-19 · Completar y saltear sí se protegen de un snapshot viejo")
    func completeAndSkipAreGuardedAgainstStaleSnapshots() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()
        let id = engine.sessionID

        // El reloj está descansando. El iPhone todavía dibuja la pantalla de carga y el
        // usuario aprieta "Hecho": el comando llega tarde.
        engine.completeCurrent()
        #expect(engine.phase == .resting)

        engine.apply(LiveSessionCommand(sessionID: id, action: .completeCurrent))
        #expect(engine.index == 0, "Se descartó: ya no estaba cargando")

        // Y al revés: el reloj ya salió del descanso, llega un "saltear" tardío. Sin la
        // guarda, esto sería el bug 5 (saltear una serie entera). Ver I-11.
        engine.skipRest()
        #expect(engine.phase == .logging)
        engine.apply(LiveSessionCommand(sessionID: id, action: .skipRest))
        #expect(engine.index == 1, "Se descartó: ya no estaba descansando")
    }

    @Test("I-19 · ⚠️ Un 'Anterior' que llega tarde resucita una sesión terminada")
    func aLateGoBackResurrectsAFinishedSession() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()
        let id = engine.sessionID

        // La sesión se completa entera en el reloj.
        for _ in 0..<4 {
            engine.completeCurrent()
            engine.skipRest()
        }
        engine.completeCurrent()
        #expect(engine.phase == .done)
        #expect(day.isCompleted)

        // La carrera: el espejo del iPhone todavía mostraba la última serie con el botón
        // "Anterior" (`LiveSessionMirrorView` lo dibuja en la fase de carga). El usuario lo
        // aprieta justo cuando el reloj está confirmando la última serie. El comando llega
        // con la sesión ya en `.done`.
        engine.apply(LiveSessionCommand(sessionID: id, action: .goBack))

        // ⚠️ `apply(.goBack)` es el **único** comando sin guarda de fase: su `else if index
        // > 0` se cumple igual en `.done`, así que llama a `goBackFromLogging()`.
        #expect(engine.phase == .logging, "⚠️ La sesión terminada volvió a estar en curso")

        // Y el índice **retrocede**: `goBackFromLogging` está pensado para volver desde la
        // serie que estás cargando, pero en `.done` no estabas cargando ninguna. Resultado:
        // te lleva a la **anteúltima** serie y des-marca esa.
        #expect(engine.index == 3)

        let remo = day.orderedExercises[1]
        #expect(!remo.orderedSets[0].isDone, "⚠️ Des-marcó la anteúltima serie…")
        #expect(remo.orderedSets[1].isDone, "⚠️ …y dejó marcada la última")

        // O sea que el día queda con un **hueco en el medio** —serie 2 hecha, serie 1 no— y
        // encima sigue marcado como completo. Nadie lo devuelve a `.done`: la fase la pone
        // solo `finish()`, y `finish()` solo corre desde `completeCurrent` en el último paso
        // (ver I-15). Al retomar, `firstIncompleteIndex` manda al hueco.
        #expect(day.isCompleted, "⚠️ El día sigue completo, con una serie sin hacer")

        // A diferencia de los bugs 3, 5 y 6, esto **no lo tapa la UI**: la guarda que falta
        // es justamente contra la ventana en la que la UI está desactualizada. Lo que lo
        // hace poco probable es el tamaño de la ventana (el viaje de WatchConnectivity), no
        // una validación.
    }

    @Test("I-19 · Terminar a distancia cierra la sesión sin marcar el día")
    func endingRemotelyClosesTheSessionWithoutCompletingTheDay() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var descansosTerminados = 0
        engine.onRestEnded = { descansosTerminados += 1 }
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()
        let id = engine.sessionID

        // Abandona en el medio del descanso de la primera serie.
        engine.completeCurrent()
        #expect(engine.phase == .resting)
        descansosTerminados = 0

        engine.apply(LiveSessionCommand(sessionID: id, action: .end))

        #expect(engine.phase == .done)
        #expect(engine.restEndDate == nil)
        #expect(descansosTerminados == 1, "Cancela la notificación de descanso pendiente")

        // Clave: cerrar **no** es completar. El día queda sin marcar y las series sin hacer
        // siguen sin hacer, así que al volver se retoma donde se dejó (ver I-15).
        #expect(!day.isCompleted)
        #expect(!day.orderedExercises[0].orderedSets[1].isDone)
    }

    @Test("I-19 · Terminar dos veces es inofensivo")
    func endingTwiceIsHarmless() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        var cambios = 0
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()
        engine.onStateChanged = { cambios += 1 }
        let id = engine.sessionID

        engine.apply(LiveSessionCommand(sessionID: id, action: .end))
        #expect(cambios == 1)

        // `endSession` arranca con `guard phase != .done`. Importa porque el botón de cerrar
        // puede tocarse dos veces, o llegar duplicado por el canal.
        engine.apply(LiveSessionCommand(sessionID: id, action: .end))
        #expect(engine.phase == .done)
        #expect(cambios == 1, "El segundo cierre no vuelve a difundir")
    }

    // MARK: - I-20

    // `makeSnapshot` es lo que el reloj le manda al iPhone. Cierra el lazo: el engine produce
    // el snapshot, `LiveSessionWire` lo serializa (ver U-12..U-17), y del otro lado se dibuja
    // el espejo y la Live Activity. Si un campo miente, miente en la pantalla de bloqueo.

    @Test("I-20 · El snapshot refleja dónde estás parado")
    func theSnapshotReflectsTheCurrentStep() throws {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)
        engine.beginLiveSession()

        let s = engine.makeSnapshot(heartRate: 132)

        #expect(s.sessionID == engine.sessionID)
        #expect(s.dayDate == day.date)
        #expect(s.phase == .logging)
        #expect(s.exerciseName == "Press banca")
        #expect(s.exerciseIndex == 0)
        #expect(s.exerciseCount == 2)
        #expect(s.setNumber == 1)
        #expect(s.setCount == 3)
        #expect(s.targetReps == "6-8")
        #expect(!s.isBodyweight)
        #expect(!s.isTimeBased)
        #expect(s.reps == 8, "El prellenado ya viaja en el snapshot")

        // El pulso lo inyecta la plataforma: el engine no conoce HealthKit.
        #expect(s.heartRate == 132)
    }

    @Test("I-20 · El descanso solo viaja mientras se está descansando")
    func theRestOnlyTravelsWhileResting() throws {
        let db = TestDB()
        let (engine, fin) = try engineResting(in: db)

        var s = engine.makeSnapshot()
        #expect(s.phase == .resting)
        #expect(s.restEndDate == fin, "La cuenta la dibuja el iPhone solo, con esta fecha")
        #expect(s.restTotal == 90)
        #expect(!s.isOvertime)

        // En tiempo extra el flag se enciende: es lo que pinta el descanso en rojo del otro
        // lado.
        engine.tickRest(now: fin.addingTimeInterval(5))
        s = engine.makeSnapshot()
        #expect(s.isOvertime)

        // Y al salir del descanso la fecha desaparece. Si sobreviviera, el iPhone seguiría
        // dibujando una cuenta regresiva sobre una serie que ya no descansa.
        engine.skipRest()
        s = engine.makeSnapshot()
        #expect(s.phase == .logging)
        #expect(s.restEndDate == nil)
        #expect(!s.isOvertime)
    }

    @Test("I-20 · El progreso avanza con la sesión y llega a 1 al terminar")
    func theProgressAdvancesWithTheSession() {
        let db = TestDB()
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Cargando la serie 1 de 5: todavía no hiciste nada.
        #expect(engine.makeSnapshot().progressFraction == 0)

        // Descansando después de la serie 1: contás la serie que acabás de hacer. Por eso
        // `.resting` usa `index + 1` y `.logging` usa `index`.
        engine.completeCurrent()
        #expect(engine.makeSnapshot().progressFraction == 0.2)

        engine.skipRest()
        #expect(engine.makeSnapshot().progressFraction == 0.2, "Cargando la 2: sigue 1 de 5 hecha")

        for _ in 0..<3 {
            engine.completeCurrent()
            engine.skipRest()
        }
        engine.completeCurrent()
        #expect(engine.phase == .done)
        #expect(engine.makeSnapshot().progressFraction == 1)
    }

    @Test("I-20 · ⚠️ El contador de series cuenta la que todavía no confirmaste")
    func theLoggedSetsCounterCountsThePrefilledSet() throws {
        let db = TestDB()
        // Con historial, para que el prellenado también ponga peso.
        historial("Press banca", on: date(2026, 6, 24), weights: [70], in: db.context)
        let day = dayWithTwoExercises(in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // ⚠️ Recién abierta la sesión, sin haber confirmado nada, el snapshot ya dice
        // **1 serie**. `loggedSetsCount` cuenta series "con datos" (`reps != nil || weight
        // != nil`), y el prellenado (I-17) ya le puso reps y peso a la serie actual.
        //
        // Se ve: `LiveSessionMirrorView` muestra "\(s.loggedSetsCount) series" en vivo. O sea
        // que el espejo del iPhone dice "1 series" antes de que hagas la primera.
        let s = engine.makeSnapshot()
        #expect(s.loggedSetsCount == 1, "⚠️ Cuenta la prellenada, no la confirmada")

        // El volumen arrastra el mismo error: 70 kg × 8 reps de una serie que no hiciste.
        #expect(s.totalVolume == 560, "⚠️ Volumen de una serie sin confirmar")

        // La contracara: **en el resumen final los dos números son correctos**, porque ahí
        // todas las series están confirmadas y no queda ninguna prellenada de más. Y el
        // resumen del reloj (`Series` / `Volumen`) es el lugar donde el usuario los mira de
        // verdad. Por eso esto es un defecto del **espejo en vivo**, no del registro.
        for _ in 0..<4 {
            engine.currentStep?.set?.weight = 70
            engine.completeCurrent()
            engine.skipRest()
        }
        engine.currentStep?.set?.weight = 70
        engine.completeCurrent()

        let final = engine.makeSnapshot()
        #expect(final.phase == .done)
        #expect(final.loggedSetsCount == 5, "Las 5 series del día, todas hechas")
    }

    @Test("I-20 · Un ejercicio de peso corporal o de tiempo se anuncia como tal")
    func bodyweightAndTimeBasedTravelInTheSnapshot() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), type: .fuerza, in: db.context)
        makeExercise("Abdominales bisagra a dos piernas", on: day, order: 0,
                     targetReps: "30 s", sets: [(nil, nil)], in: db.context)

        let engine = GuidedSessionEngine()
        engine.start(day: day, context: db.context)

        // Estos dos flags deciden qué ruedas dibuja el otro lado: sin peso, y contando
        // segundos en vez de reps. Si viajaran mal, el iPhone te pediría kilos de una plancha.
        let s = engine.makeSnapshot()
        #expect(s.isBodyweight)
        #expect(s.isTimeBased)
        #expect(s.weight == nil)
        #expect(s.reps == 30)
    }

    @Test("I-20 · El snapshot sobrevive el viaje por el canal")
    func theSnapshotSurvivesTheWire() throws {
        let db = TestDB()
        let (engine, _) = try engineResting(in: db)

        // El lazo completo: engine → snapshot → payload → snapshot. Es exactamente lo que
        // pasa entre el reloj y el iPhone. Los tests de serialización (U-12..U-17) prueban el
        // round-trip con snapshots armados a mano; este lo prueba con uno **real**, salido de
        // una sesión en curso.
        let original = engine.makeSnapshot(heartRate: 145)
        let payload = try #require(LiveSessionWire.payload(for: original))
        let recibido = try #require(LiveSessionWire.snapshot(from: payload))

        #expect(recibido == original)
    }
}
