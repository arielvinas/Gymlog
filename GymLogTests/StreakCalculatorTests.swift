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

    // MARK: - U-31

    // La decisión más delicada del cálculo, y es de producto: **la semana en curso, todavía sin
    // entrenar, no corta la racha**. La racha se cuenta hacia atrás desde la **última semana con
    // actividad**, no desde hoy.
    //
    // Si no fuera así, el lunes a la mañana la app te diría que perdiste una racha de cinco
    // semanas por no haber entrenado todavía. Y una racha que se pierde por no haber hecho nada
    // aún no motiva: hace que dejes de abrir la app.

    @Test("U-31 · El lunes a la mañana la racha sigue intacta")
    func theStreakSurvivesMondayMorning() throws {
        let db = TestDB()

        semana("Semana 1", empezando: date(2026, 6, 1), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 8), completada: true, in: db.context)
        // La semana en curso: los días existen (el plan los sembró) pero no entrenó todavía.
        semana("Semana 3", empezando: date(2026, 6, 15), completada: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Parado el lunes 15, recién arrancada la semana: la racha de 2 se mantiene. El
        // `lastIndex(where: { $0.completed })` cae en la Semana 2 y cuenta desde ahí.
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 15)) == 2)
    }

    @Test("U-31 · Y sigue intacta el jueves, aunque la semana siga en blanco")
    func theStreakSurvivesMidweek() throws {
        let db = TestDB()

        semana("Semana 1", empezando: date(2026, 6, 8), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 15), completada: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // ⚠️ Acá está la contracara, y conviene tenerla escrita: la semana en curso **nunca**
        // corta, no importa cuán avanzada esté. El jueves sin entrenar, la racha sigue en 1.
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 18)) == 1)

        // O sea que la racha solo "se pierde" cuando la semana **termina** sin actividad y
        // arranca la siguiente. Es indulgente por diseño: te da la semana entera para
        // salvarla. El precio es que el número no distingue "vengo entrenando" de "entrené la
        // semana pasada y esta no hice nada todavía".
    }

    @Test("U-31 · Entrenar en la semana en curso la suma a la racha")
    func trainingThisWeekExtendsTheStreak() throws {
        let db = TestDB()

        semana("Semana 1", empezando: date(2026, 6, 8), completada: true, in: db.context)
        semana("Semana 2", empezando: date(2026, 6, 15), completada: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 1)

        // Entrena el miércoles: la semana en curso pasa a estar activa y se suma.
        let miercoles = try #require(dias.first { $0.date == date(2026, 6, 17) })
        miercoles.isCompleted = true

        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 2)
    }

    @Test("U-31 · Dos semanas en blanco sí cortan")
    func twoBlankWeeksDoBreakIt() throws {
        let db = TestDB()

        semana("Semana 1", empezando: date(2026, 6, 1), completada: true, in: db.context)
        // Faltó una semana entera…
        semana("Semana 2", empezando: date(2026, 6, 8), completada: false, in: db.context)
        // …y la actual también va en blanco.
        semana("Semana 3", empezando: date(2026, 6, 15), completada: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // La indulgencia de U-31 cubre **solo** la semana en curso. La Semana 2 ya cerró sin
        // actividad, así que la racha cuenta desde la Semana 1 y se queda en 1 — no en 3.
        #expect(StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 1)
    }
}
