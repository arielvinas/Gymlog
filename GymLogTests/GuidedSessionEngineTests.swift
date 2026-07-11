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
}
