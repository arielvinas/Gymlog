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

    // MARK: - U-32

    // ⚠️ **Bug 2.** `currentWeekStreak` agrupa con `Dictionary(grouping: days, by: { $0.weekTitle })`:
    // **por el título de la semana, que es un String**, no por semana calendario.
    //
    // O sea que la app no pregunta "¿en qué semana cayó este día?" sino "¿qué texto tiene
    // escrito?". Dos días de semanas distintas con el mismo texto son, para la racha, la misma
    // semana.

    @Test("U-32 · ⚠️ Dos semanas con el mismo título se fusionan en una")
    func weeksWithTheSameTitleAreMerged() throws {
        let db = TestDB()

        // Dos semanas calendario distintas y consecutivas, las dos entrenadas. Pero alguien
        // les puso el mismo título.
        semana("Semana 1", empezando: date(2026, 6, 8), completada: true, in: db.context)
        semana("Semana 1", empezando: date(2026, 6, 15), completada: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // ⚠️ La racha dice **1**, no 2: el `Dictionary(grouping:)` las colapsó en una sola
        // entrada. El usuario entrenó dos semanas seguidas y la app le reconoce una.
        #expect(
            StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 1,
            "Comportamiento actual: dos semanas con el mismo texto cuentan como una"
        )
    }

    @Test("U-32 · ⚠️ Una semana partida en dos títulos cuenta doble")
    func oneWeekSplitInTwoTitlesCountsTwice() throws {
        let db = TestDB()

        // Una **sola** semana calendario (lunes 15 a domingo 21), con dos días entrenados… y
        // dos títulos distintos.
        makeDay(date(2026, 6, 15), type: .fuerza, title: "Fuerza A",
                weekTitle: "Semana 3", isCompleted: true, in: db.context)
        makeDay(date(2026, 6, 17), type: .rodaje, title: "Rodaje 8 km",
                weekTitle: "Semana 3 (bis)", isCompleted: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // ⚠️ La racha dice **2**: los dos títulos son dos "semanas" para el cálculo. El usuario
        // entrenó una semana y la app le reconoce dos. El error va para los dos lados.
        #expect(
            StreakCalculator.currentWeekStreak(days: dias, today: date(2026, 6, 17)) == 2,
            "Comportamiento actual: dos títulos en la misma semana cuentan doble"
        )
    }

    @Test("U-32 · Por dónde llega la colisión: los títulos no son identidades")
    func theTitlesAreNotIdentities() {
        // Hay dos fuentes de `weekTitle`, y ninguna garantiza unicidad en el tiempo.
        //
        // **1. `WeekAssigner`**, que titula los días que agrega el usuario. Arma "Semana del
        // <día> <mes>" — **sin el año**.
        let info = WeekAssigner.weekInfo(for: date(2026, 6, 17), among: [])
        #expect(info.title == "Semana del 15 jun")
        #expect(!info.title.contains("2026"), "⚠️ El año no está en el título")

        // Esa colisión existe pero es remota: hace falta que el mismo día del mes vuelva a
        // caer lunes, y para el 15 de junio eso recién pasa en **2037**. Real para una app de
        // entrenamiento continuo, pero no es el camino corto.
        let en2037 = WeekAssigner.weekInfo(for: date(2037, 6, 17), among: [])
        #expect(en2037.title == info.title, "⚠️ A once años, el mismo texto")

        // **2. El plan sembrado**, que usa títulos **fijos**: "Semana 1" … "Semana 5". Y este
        // sí es el camino corto: GymLog es entrenamiento continuo, así que tarde o temprano va
        // a haber un bloque nuevo. Si ese bloque vuelve a numerar desde "Semana 1" —lo natural—
        // su primera semana se fusiona con la primera del bloque viejo.
        //
        // El problema de fondo no es el formato del título: es que **un texto para mostrar se
        // está usando como identidad**. Cualquier formato que se elija va a chocar alguna vez.
    }

    @Test("U-32 · La agrupación correcta sería por semana calendario")
    func groupingByCalendarWeekWouldFixIt() throws {
        let db = TestDB()

        // El mismo escenario del primer test: dos semanas calendario, mismo título.
        semana("Semana 1", empezando: date(2026, 6, 8), completada: true, in: db.context)
        semana("Semana 1", empezando: date(2026, 6, 15), completada: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Agrupando por el **inicio de la semana calendario** —que es lo que el resto de la app
        // ya hace, ver `WeeklyVolume`— salen dos grupos, no uno. La racha real es 2.
        let cal = PlanConstants.calendar
        let porSemanaReal = Dictionary(grouping: dias) {
            cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        #expect(porSemanaReal.count == 2, "Dos semanas calendario, dos grupos")

        // El fix es cambiar la clave del `Dictionary(grouping:)`: de `$0.weekTitle` al inicio
        // de la semana. `weekTitle` es texto para mostrar, no una identidad — y el resto de la
        // app ya usa el calendario para lo mismo (U-28, U-29).
    }

    // MARK: - U-33

    // `currentDayStreak` es la otra racha: **días consecutivos sin saltearse un entrenamiento**.
    // Camina hacia atrás desde hoy y para en el primer día que debía entrenarse y no se hizo.
    //
    // Sus dos reglas raras son las que la hacen usable con un plan que tiene descansos:
    // el descanso **no cuenta ni corta** (se saltea), y **hoy sin hacer todavía no corta**
    // (igual que la semana en curso de U-31).
    //
    // Hoy no se muestra en ninguna pantalla —el comentario dice "disponible para futuros
    // badges"— así que estos tests fijan el contrato **antes** de que algo dependa de él.

    @Test("U-33 · Días consecutivos completados suman")
    func consecutiveCompletedDaysCount() throws {
        let db = TestDB()

        makeDay(date(2026, 6, 15), type: .fuerza, isCompleted: true, in: db.context)
        makeDay(date(2026, 6, 16), type: .rodaje, isCompleted: true, in: db.context)
        makeDay(date(2026, 6, 17), type: .fuerza, isCompleted: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())
        #expect(StreakCalculator.currentDayStreak(days: dias, today: date(2026, 6, 17)) == 3)
    }

    @Test("U-33 · El descanso no cuenta ni corta: se saltea")
    func restDaysAreSkipped() throws {
        let db = TestDB()

        // Entrenó lunes y miércoles, con descanso el martes. El descanso no está "hecho" —
        // nadie completa un descanso— pero tampoco debería romper la racha.
        makeDay(date(2026, 6, 15), type: .fuerza, isCompleted: true, in: db.context)
        makeDay(date(2026, 6, 16), type: .descanso, title: "Descanso",
                isCompleted: false, in: db.context)
        makeDay(date(2026, 6, 17), type: .fuerza, isCompleted: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // La racha es **2**, no 3: el descanso se saltea con el `continue`, así que ni suma ni
        // corta. Es la regla que hace que el número signifique "entrenamientos que no me
        // saltée", y no "días seguidos yendo al gimnasio".
        #expect(StreakCalculator.currentDayStreak(days: dias, today: date(2026, 6, 17)) == 2)
    }

    @Test("U-33 · Hoy todavía pendiente no corta la racha")
    func todayStillPendingDoesNotBreakIt() throws {
        let db = TestDB()

        makeDay(date(2026, 6, 15), type: .fuerza, isCompleted: true, in: db.context)
        makeDay(date(2026, 6, 16), type: .rodaje, isCompleted: true, in: db.context)
        // Hoy: el entrenamiento está cargado pero todavía no lo hizo. Son las 9 de la mañana.
        makeDay(date(2026, 6, 17), type: .fuerza, isCompleted: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Sigue en 2. Misma lógica de producto que U-31: la app no te castiga por no haber
        // entrenado *todavía*. Hoy no suma, pero tampoco rompe.
        #expect(StreakCalculator.currentDayStreak(days: dias, today: date(2026, 6, 17)) == 2)
    }

    @Test("U-33 · Un entrenamiento salteado sí corta")
    func amissedWorkoutBreaksTheStreak() throws {
        let db = TestDB()

        makeDay(date(2026, 6, 15), type: .fuerza, isCompleted: true, in: db.context)
        // El martes tenía rodaje y no lo hizo. **Ayer**, no hoy: ya no hay excusa.
        makeDay(date(2026, 6, 16), type: .rodaje, isCompleted: false, in: db.context)
        makeDay(date(2026, 6, 17), type: .fuerza, isCompleted: true, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // La racha es 1: cuenta el miércoles y se corta en el martes salteado. El `break`
        // detiene el recorrido — lo anterior al hueco no se cuenta, aunque estuviera hecho.
        #expect(StreakCalculator.currentDayStreak(days: dias, today: date(2026, 6, 17)) == 1)
    }

    @Test("U-33 · Los días futuros del plan no cuentan")
    func futureDaysAreIgnored() throws {
        let db = TestDB()

        makeDay(date(2026, 6, 17), type: .fuerza, isCompleted: true, in: db.context)
        // El plan ya sembró mañana y pasado, sin hacer (obvio: todavía no llegaron).
        makeDay(date(2026, 6, 18), type: .rodaje, isCompleted: false, in: db.context)
        makeDay(date(2026, 6, 19), type: .fuerza, isCompleted: false, in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Sin el `filter { $0.date <= todayStart }`, el recorrido arrancaría por el viernes
        // sin hacer y la racha daría **0** siempre. El filtro es lo que hace que el número
        // exista.
        #expect(StreakCalculator.currentDayStreak(days: dias, today: date(2026, 6, 17)) == 1)
    }

    @Test("U-33 · Una racha de puros descansos es cero")
    func onlyRestDaysGiveZero() throws {
        let db = TestDB()

        makeDay(date(2026, 6, 16), type: .descanso, title: "Descanso", in: db.context)
        makeDay(date(2026, 6, 17), type: .descanso, title: "Descanso", in: db.context)

        let dias = try db.context.fetch(FetchDescriptor<WorkoutDay>())

        // Los descansos se saltean todos y no queda nada que contar. Cero, no una racha
        // infinita de "días sin faltar". Correcto: no entrenaste.
        #expect(StreakCalculator.currentDayStreak(days: dias, today: date(2026, 6, 17)) == 0)
        #expect(StreakCalculator.currentDayStreak(days: [], today: date(2026, 6, 17)) == 0)
    }
}
