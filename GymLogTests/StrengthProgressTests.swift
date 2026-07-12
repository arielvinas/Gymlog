//
//  StrengthProgressTests.swift
//  GymLogTests
//
//  La evolución de fuerza: compara la mejor serie de la última sesión de cada
//  ejercicio contra la anterior. Es lo que le dice al usuario "subiste 5% en press
//  banca" — y como sale de comparar dos números que él mismo cargó, un error acá
//  no se ve: se cree.
//
//  Backlog: TESTING.md · U-34..U-36
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Progreso de fuerza")
struct StrengthProgressTests {

    /// Registra una sesión de un ejercicio en una fecha, con sus series.
    @MainActor
    @discardableResult
    private func sesion(
        _ nombre: String,
        _ fecha: Date,
        sets: [(weight: Double?, reps: Int?)],
        in context: ModelContext
    ) -> Exercise {
        let dia = makeDay(fecha, type: .fuerza, title: "Fuerza A", in: context)
        return makeExercise(nombre, on: dia, order: 0, sets: sets, in: context)
    }

    // MARK: - U-34

    @Test("U-34 · Detecta una subida de peso entre las dos últimas sesiones")
    func detectsAWeightIncrease() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(80, 8), (80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 17), sets: [(85, 6), (85, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        let press = try #require(mejoras.first { $0.name == "Press banca" })
        #expect(press.last.weight == 85)
        #expect(press.previous.weight == 80)

        // De 80 a 85 son 6,25%. Se compara contra el peso **anterior**, no contra el nuevo:
        // subir de 80 a 85 es +6,25%, no +5,88%.
        #expect(abs(press.percentChange - 6.25) < 0.001)
    }

    @Test("U-34 · La 'mejor serie' es la de mayor peso, no la última")
    func theTopSetIsTheHeaviestOne() throws {
        let db = TestDB()

        // Una sesión en pirámide que termina con una serie liviana de descarga. La comparación
        // tiene que agarrar los 90, no los 60 del final.
        sesion("Sentadilla", date(2026, 6, 10), sets: [(70, 10)], in: db.context)
        sesion("Sentadilla", date(2026, 6, 17), sets: [(80, 8), (90, 5), (60, 12)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        let sentadilla = try #require(mejoras.first { $0.name == "Sentadilla" })
        #expect(sentadilla.last.weight == 90)
        #expect(sentadilla.last.reps == 5, "Y se lleva las reps de esa serie, no de otra")
    }

    @Test("U-34 · Con el mismo peso, la mejor serie es la de más reps")
    func repsBreakTheTie() throws {
        let db = TestDB()

        sesion("Remo", date(2026, 6, 10), sets: [(60, 8)], in: db.context)
        // Mismo peso en las tres, distintas reps: gana la de 12.
        sesion("Remo", date(2026, 6, 17), sets: [(60, 8), (60, 12), (60, 10)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let remo = try #require(
            StrengthProgress.recentImprovements(exercises: ejercicios).first { $0.name == "Remo" }
        )

        #expect(remo.last.reps == 12)

        // ⚠️ Pero el porcentaje **solo mira el peso**: mismo peso, 0% de cambio, aunque hayas
        // hecho 4 reps más. La tarjeta va a decir "0%" sobre una sesión que fue claramente
        // mejor. No es un bug —el contrato es "variación del peso"— pero el nombre
        // `ExerciseImprovement` promete más de lo que mide.
        #expect(remo.percentChange == 0)
    }

    @Test("U-34 · Un ejercicio con una sola sesión no aparece")
    func exercisesWithASingleSessionAreIgnored() throws {
        let db = TestDB()

        // Solo una sesión: no hay contra qué comparar.
        sesion("Press banca", date(2026, 6, 17), sets: [(80, 8)], in: db.context)
        // Dos, pero una sin ningún peso cargado: `topSet` la descarta y queda una sola útil.
        sesion("Dominadas", date(2026, 6, 10), sets: [(nil, 8)], in: db.context)
        sesion("Dominadas", date(2026, 6, 17), sets: [(10, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        // El `guard conDatos.count >= 2` los saca a los dos. Está bien: mostrar "+100%" porque
        // antes no había dato sería mentir.
        #expect(mejoras.isEmpty)
    }

    @Test("U-34 · Compara las dos últimas sesiones, no la primera con la última")
    func itComparesTheTwoMostRecentSessions() throws {
        let db = TestDB()

        // Tres sesiones: 60 → 80 → 85. La tarjeta muestra el último salto (80 → 85), no el
        // acumulado desde el principio.
        sesion("Press banca", date(2026, 6, 3), sets: [(60, 10)], in: db.context)
        sesion("Press banca", date(2026, 6, 10), sets: [(80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 17), sets: [(85, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let press = try #require(
            StrengthProgress.recentImprovements(exercises: ejercicios).first
        )

        #expect(press.previous.weight == 80, "La anterior, no la primera de todas")
        #expect(press.last.weight == 85)
    }

    @Test("U-34 · Las mejoras salen ordenadas por fecha, la más reciente primero")
    func improvementsAreSortedByDate() throws {
        let db = TestDB()

        // Dos ejercicios con progreso en semanas distintas.
        sesion("Press banca", date(2026, 6, 3), sets: [(80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 10), sets: [(85, 8)], in: db.context)

        sesion("Sentadilla", date(2026, 6, 10), sets: [(100, 5)], in: db.context)
        sesion("Sentadilla", date(2026, 6, 17), sets: [(110, 5)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        // La sentadilla mejoró el 17, el press el 10. Primero la más fresca.
        //
        // El orden importa porque `prefix(limit)` corta después de ordenar: con muchos
        // ejercicios, los que se muestran son los **más recientes**, no los que más subieron.
        #expect(mejoras.map(\.name) == ["Sentadilla", "Press banca"])
    }
}
