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
}
