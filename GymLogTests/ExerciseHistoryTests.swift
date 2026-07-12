//
//  ExerciseHistoryTests.swift
//  GymLogTests
//
//  El "última vez" del ejercicio: qué peso te sugiere la app cuando arrancás una serie
//  (`lastWeight`, que el motor guiado usa para **prellenar** el campo) y qué texto te muestra
//  arriba del ejercicio (`lastSession`). Son dos funciones parecidas que responden preguntas
//  distintas y —como se ve en U-37— no siempre coinciden.
//
//  Backlog: TESTING.md · U-36, U-37
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Histórico del ejercicio")
struct ExerciseHistoryTests {

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

    // MARK: - U-36 · lastWeight

    @Test("U-36 · Sugiere el mayor peso de la última sesión previa")
    func suggestsTheHeaviestWeightOfTheLastSession() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(60, 10), (70, 8), (65, 8)], in: db.context)

        let sugerido = ExerciseHistory.lastWeight(
            name: "Press banca",
            before: date(2026, 6, 17),
            context: db.context
        )

        // El mayor, no el último ni el promedio: las series de trabajo suelen ser las pesadas,
        // y la última puede ser una descarga.
        #expect(sugerido == 70)
    }

    @Test("U-36 · Mira la sesión más reciente, no la más pesada de la historia")
    func itLooksAtTheMostRecentSessionOnly() throws {
        let db = TestDB()

        // Un pico viejo de 100 y una sesión reciente más liviana (volviste de una lesión).
        sesion("Sentadilla", date(2026, 5, 6), sets: [(100, 5)], in: db.context)
        sesion("Sentadilla", date(2026, 6, 10), sets: [(70, 8)], in: db.context)

        let sugerido = ExerciseHistory.lastWeight(
            name: "Sentadilla",
            before: date(2026, 6, 17),
            context: db.context
        )

        // Sugerir los 100 sería empujarte a un peso que hoy no movés. Sugiere lo último real.
        #expect(sugerido == 70)
    }

    @Test("U-36 · El día en curso no cuenta: la comparación es estrictamente anterior")
    func theCurrentDayIsExcluded() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(70, 8)], in: db.context)
        // La sesión de hoy, ya con un peso cargado a mano.
        sesion("Press banca", date(2026, 6, 17), sets: [(200, 1)], in: db.context)

        let sugerido = ExerciseHistory.lastWeight(
            name: "Press banca",
            before: date(2026, 6, 17),
            context: db.context
        )

        // `dayDate < currentDate` es estricto, así que el día que estás entrenando no se sugiere
        // a sí mismo. Si no, la sugerencia se retroalimentaría con lo que acabás de escribir.
        #expect(sugerido == 70)
    }

    @Test("U-36 · Sin histórico devuelve nil, y un nombre vacío también")
    func noHistoryReturnsNil() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(70, 8)], in: db.context)

        // Ejercicio que nunca se hizo.
        #expect(
            ExerciseHistory.lastWeight(
                name: "Peso muerto", before: date(2026, 6, 17), context: db.context
            ) == nil
        )
        // Nombre en blanco: corta antes de consultar la base.
        #expect(
            ExerciseHistory.lastWeight(
                name: "   ", before: date(2026, 6, 17), context: db.context
            ) == nil
        )
    }

    @Test("U-36 · El nombre se busca sin espacios de sobra")
    func theNameIsTrimmedBeforeSearching() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(70, 8)], in: db.context)

        // Un nombre con espacios al costado (copiado, tipeado de más) igual encuentra el registro.
        #expect(
            ExerciseHistory.lastWeight(
                name: "  Press banca\n", before: date(2026, 6, 17), context: db.context
            ) == 70
        )
    }

    @Test("U-36 · Las series sin peso no arrastran la sugerencia hacia abajo")
    func setsWithoutWeightAreIgnored() throws {
        let db = TestDB()

        // Dos series cargadas y una que quedó sin peso (te olvidaste de anotarla).
        sesion("Remo", date(2026, 6, 10), sets: [(60, 10), (nil, 10), (65, 8)], in: db.context)

        #expect(
            ExerciseHistory.lastWeight(
                name: "Remo", before: date(2026, 6, 17), context: db.context
            ) == 65
        )
    }

    // MARK: - U-36 · lastSession

    @Test("U-36 · lastSession arma el resumen de la sesión previa")
    func lastSessionBuildsASummary() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(70, 8), (70, 6)], in: db.context)

        let resumen = ExerciseHistory.lastSession(
            name: "Press banca",
            before: date(2026, 6, 17),
            context: db.context
        )

        #expect(resumen == "70kg × 8, 70kg × 6")
    }

    @Test("U-36 · lastSession saltea las series vacías, pero muestra las mitades")
    func lastSessionSkipsEmptySets() throws {
        let db = TestDB()

        // Tres series: una completa, una a medias (reps sin peso) y una intacta.
        sesion("Remo", date(2026, 6, 10), sets: [(60, 10), (nil, 8), (nil, nil)], in: db.context)

        let resumen = ExerciseHistory.lastSession(
            name: "Remo",
            before: date(2026, 6, 17),
            context: db.context
        )

        // La vacía (sin reps ni peso) desaparece; la que tiene solo reps entra con un guión en el
        // lugar del peso. Es honesto: no inventa un número que no cargaste.
        #expect(resumen == "60kg × 10, — × 8")
    }

    // MARK: - U-37 · Las dos funciones no siempre coinciden

    /// ⚠️ **Asimetría CONFIRMADA.** Las dos funciones recorren el mismo histórico pero se
    /// detienen en momentos distintos:
    ///
    ///   - `lastSession` frena en la primera sesión con **cualquier** dato (`hasLoggedData`, que
    ///     acepta reps *o* peso).
    ///   - `lastWeight` sigue buscando hacia atrás hasta encontrar una con **peso**.
    ///
    /// Cuando la última sesión tiene reps pero no peso, la pantalla dice una cosa y el campo se
    /// prellena con otra.
    @Test("U-37 · ⚠️ La pantalla dice una sesión y el motor prellena con otra")
    func theSummaryAndTheSuggestedWeightCanDisagree() throws {
        let db = TestDB()

        // Hace tres semanas cargaste 70 kg. La semana pasada anotaste solo las reps.
        sesion("Press banca", date(2026, 6, 3), sets: [(70, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 10), sets: [(nil, 10)], in: db.context)

        let resumen = ExerciseHistory.lastSession(
            name: "Press banca", before: date(2026, 6, 17), context: db.context
        )
        let sugerido = ExerciseHistory.lastWeight(
            name: "Press banca", before: date(2026, 6, 17), context: db.context
        )

        // La etiqueta "Última vez" muestra la sesión del 10, sin peso…
        #expect(resumen == "— × 10")
        // …pero el campo de peso se prellena con los 70 kg del 3.
        #expect(sugerido == 70)

        // No es un bug: cada una responde bien su pregunta ("qué hiciste la última vez" vs "con
        // cuánto peso venías"). Pero al usuario le llega como una contradicción: lee "— × 10" y
        // ve un 70 en el campo, sin nada que le explique de dónde salió.
    }

    /// ⚠️ **Límite CONFIRMADO y alcanzable.** Las dos funciones traen `fetchLimit = 10` sesiones
    /// previas. Si las últimas 10 no tienen datos, el histórico **se pierde**: no hay una
    /// undécima consulta.
    ///
    /// Y sesiones sin datos las hay de sobra: el plan **siembra los días por adelantado**, así que
    /// cada día que no entrenás deja un `Exercise` vacío en la base. Diez faltazos seguidos del
    /// mismo ejercicio —unas cinco semanas con dos días de fuerza— y la app se olvida de con
    /// cuánto peso venías, aunque el registro siga ahí.
    @Test("U-37 · ⚠️ Con 10 sesiones vacías por delante, el histórico se pierde")
    func theHistoryIsLostBehindTenEmptySessions() throws {
        let db = TestDB()

        // La sesión real, la más vieja de todas.
        sesion("Press banca", date(2026, 3, 2), sets: [(70, 8)], in: db.context)

        // Diez días sembrados que nunca se completaron, todos posteriores.
        for i in 0..<10 {
            sesion("Press banca", date(2026, 4, 6 + i), sets: [(nil, nil)], in: db.context)
        }

        let sugerido = ExerciseHistory.lastWeight(
            name: "Press banca", before: date(2026, 6, 17), context: db.context
        )

        // El fetch trae solo las 10 más recientes —las diez vacías— y el bucle termina sin
        // encontrar un peso. Los 70 kg del 2/3 existen en la base, pero quedaron fuera del corte.
        #expect(sugerido == nil, "El peso está en la base, pero el fetchLimit no llega hasta él")

        // Con una vacía menos, el corte alcanza a la sesión buena y la sugerencia reaparece.
        let db2 = TestDB()
        sesion("Press banca", date(2026, 3, 2), sets: [(70, 8)], in: db2.context)
        for i in 0..<9 {
            sesion("Press banca", date(2026, 4, 6 + i), sets: [(nil, nil)], in: db2.context)
        }
        #expect(
            ExerciseHistory.lastWeight(
                name: "Press banca", before: date(2026, 6, 17), context: db2.context
            ) == 70
        )
    }
}
