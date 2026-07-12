//
//  StreakCalculatorTests.swift
//  GymLogTests
//
//  Las rachas: semanas consecutivas entrenando, días consecutivos sin saltearse
//  nada. Es el número que motiva —o desmotiva— y el usuario no tiene forma de
//  auditarlo: si dice 5 y son 3, le cree.
//
//  Backlog: TESTING.md · U-30..U-33
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Rachas")
struct StreakCalculatorTests {

    /// Arma una semana del plan con un título propio y dice si tuvo un día completado.
    /// El título importa: `currentWeekStreak` agrupa por `weekTitle`, no por calendario
    /// (ver U-32).
    @MainActor
    private func semana(
        _ titulo: String,
        empezando lunes: Date,
        completada: Bool,
        in context: ModelContext
    ) {
        // Un día de fuerza y un rodaje, como una semana real del plan.
        makeDay(lunes, type: .fuerza, title: "Fuerza A", weekTitle: titulo,
                isCompleted: completada, in: context)
        makeDay(lunes.addingTimeInterval(2 * 86_400), type: .rodaje, title: "Rodaje 8 km",
                weekTitle: titulo, isCompleted: false, in: context)
    }

    // MARK: - U-30

    // La racha cuenta **semanas consecutivas con al menos un entrenamiento completado**. Se
    // eligió la semana (y no el día) porque el plan tiene días de descanso: contar días
    // obligaría a decidir si un descanso corta la racha, y cualquier respuesta sería
    // arbitraria. Con la semana, alcanza con haber entrenado una vez.

    @Test("U-30 · Tres semanas seguidas entrenando son una racha de 3")
    func threeConsecutiveWeeksMakeAStreakOfThree() throws {
        let db = TestDB()

        semana("Semana 1", empezando: date(2026, 6, 1), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 8), completada: true, in: db.context)
        semana("Semana 3", empezando: date(2026, 6, 15), completada: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 3)
    }

    @Test("U-30 · Alcanza con un día completado por semana")
    func oneCompletedDayPerWeekIsEnough() throws {
        let db = TestDB()

        // Cada semana tiene dos días y solo uno hecho. La racha igual cuenta la semana: el
        // criterio es `contains { $0.isCompleted }`, no "todos los días".
        semana("Semana 1", empezando: date(2026, 6, 8), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 15), completada: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(dias.filter(\.isCompleted).count == 2, "Solo 2 días hechos de 4")
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 2)
    }

    @Test("U-30 · Una semana en blanco corta la racha")
    func anEmptyWeekBreaksTheStreak() throws {
        let db = TestDB()

        // Entrenó, faltó una semana entera, volvió. La racha arranca de nuevo: cuenta 1, no 3.
        semana("Semana 1", empezando: date(2026, 6, 1), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 8), completada: false, in: db.context)
        semana("Semana 3", empezando: date(2026, 6, 15), completada: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 1)
    }

    @Test("U-30 · Sin nada completado, la racha es cero")
    func noCompletedDaysMeansZero() throws {
        let db = TestDB()

        semana("Semana 1", empezando: date(2026, 6, 8), completada: false, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 15), completada: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // El `guard let lastActive` sale por acá. Y con la base vacía, también.
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 0)
        #expect(StreakCalculator.currentWeekStreak(days: [], today: date(2026, 6, 17)) == 0)
    }

    @Test("U-30 · Las semanas futuras del plan no cuentan")
    func futureWeeksAreIgnored() throws {
        let db = TestDB()

        // El plan siembra los días **por adelantado**, así que la base siempre tiene semanas
        // futuras. El `filter { start <= todayStart }` las descarta.
        semana("Semana 1", empezando: date(2026, 6, 15), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 22), completada: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Parado en el miércoles 17, la semana que viene ni existe para el cálculo.
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 1)
    }
}
