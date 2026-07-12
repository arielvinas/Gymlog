//
//  WeekAssignerTests.swift
//  GymLogTests
//
//  A qué semana pertenece un día nuevo. Es lo que corre cuando agregás o movés un día a mano
//  desde el editor: decide si cae en una semana que ya existe o si inaugura una.
//
//  Backlog: TESTING.md · U-41
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Asignación de semana")
struct WeekAssignerTests {

    /// El título que `WeekAssigner` genera para una semana nueva, calculado con el mismo
    /// formateador que usa la app. No se compara contra un literal: las abreviaturas de mes
    /// cambian entre versiones de Xcode (lección de U-11).
    private func tituloEsperado(lunes: Date) -> String {
        "Semana del \(lunes.dayMonth)"
    }

    // MARK: - U-41 · Hereda la semana existente

    @Test("U-41 · Un día que cae en una semana ya existente hereda su título, etiqueta y orden")
    func aDayInAnExistingWeekInheritsIt() {
        let db = TestDB()

        // Lunes 15/6. El día nuevo es el miércoles 17.
        let dias = [
            makeDay(
                date(2026, 6, 15), weekTitle: "Semana 3", weekTag: "Pico de volumen", weekOrder: 3,
                in: db.context
            )
        ]

        let info = WeekAssigner.weekInfo(for: date(2026, 6, 17), among: dias)

        #expect(info.title == "Semana 3")
        #expect(info.tag == "Pico de volumen")
        #expect(info.order == 3)
    }

    @Test("U-41 · La semana empieza el lunes: el domingo todavía pertenece a la semana anterior")
    func theWeekStartsOnMonday() {
        let db = TestDB()

        // `PlanConstants.calendar` fija `firstWeekday = 2`, así que la semana del lunes 15 va
        // hasta el domingo 21.
        let dias = [makeDay(date(2026, 6, 15), weekTitle: "Semana 3", weekOrder: 3, in: db.context)]

        // Domingo 21: misma semana, hereda.
        #expect(WeekAssigner.weekInfo(for: date(2026, 6, 21), among: dias).title == "Semana 3")
        // Lunes 22: semana nueva.
        #expect(WeekAssigner.weekInfo(for: date(2026, 6, 22), among: dias).title != "Semana 3")
    }

    @Test("U-41 · Hereda del primer día que encuentra en el array, no del más antiguo")
    func itInheritsFromTheFirstMatchInTheArray() {
        let db = TestDB()

        // Dos días de la **misma** semana calendario con títulos distintos. No debería pasar, pero
        // pasa: es exactamente el escenario del bug 2 (la semana se identifica por un String).
        let dias = [
            makeDay(date(2026, 6, 17), weekTitle: "Semana 3", weekOrder: 3, in: db.context),
            makeDay(date(2026, 6, 15), weekTitle: "Semana 4", weekOrder: 4, in: db.context)
        ]

        let info = WeekAssigner.weekInfo(for: date(2026, 6, 19), among: dias)

        // `first(where:)` agarra el primero del array —el miércoles—, no el lunes ni el de menor
        // orden. Con la semana ya partida en dos títulos, a cuál se suma el día nuevo depende del
        // orden en que vengan los días, que es arbitrario.
        #expect(info.title == "Semana 3")
    }

    // MARK: - U-41 · Crea una semana nueva

    @Test("U-41 · Una semana nueva se titula con el lunes que la empieza")
    func aNewWeekIsTitledAfterItsMonday() {
        let db = TestDB()

        let dias = [makeDay(date(2026, 6, 1), weekTitle: "Semana 1", weekOrder: 1, in: db.context)]

        // Miércoles 17/6 → su semana arranca el lunes 15.
        let info = WeekAssigner.weekInfo(for: date(2026, 6, 17), among: dias)

        #expect(info.title == tituloEsperado(lunes: date(2026, 6, 15)))
        #expect(info.tag == nil, "La semana nueva no hereda ninguna etiqueta")
    }

    @Test("U-41 · El orden de la semana nueva es el máximo + 1")
    func theNewWeekOrderIsMaxPlusOne() {
        let db = TestDB()

        let dias = [
            makeDay(date(2026, 6, 1), weekTitle: "Semana 1", weekOrder: 1, in: db.context),
            makeDay(date(2026, 6, 8), weekTitle: "Semana 2", weekOrder: 7, in: db.context)
        ]

        // Toma el máximo (7), no la cantidad de semanas.
        #expect(WeekAssigner.weekInfo(for: date(2026, 6, 17), among: dias).order == 8)
    }

    @Test("U-41 · Sin días, la primera semana arranca con orden 1")
    func withNoDaysTheFirstWeekIsOrderOne() {
        let info = WeekAssigner.weekInfo(for: date(2026, 6, 17), among: [])

        #expect(info.order == 1, "max de una lista vacía → 0, más 1")
        #expect(info.title == tituloEsperado(lunes: date(2026, 6, 15)))
        #expect(info.tag == nil)
    }

    /// ⚠️ **Consecuencia del `max + 1`:** una semana **anterior** a todas las existentes igual se
    /// lleva el orden **más alto**. Si agregás un día en una semana ya pasada, esa semana queda
    /// "última" según `weekOrder`.
    ///
    /// **Hoy no se nota, porque nadie ordena por `weekOrder`.** `PlanView` y `PlanExportView`
    /// agrupan por `weekTitle` y ordenan las secciones por la **fecha** del primer día del grupo;
    /// no hay un solo `SortDescriptor(\.weekOrder)` en el proyecto. El campo se escribe (en el
    /// sembrado, en el editor) y no se lee: está **vestigial**.
    ///
    /// Vale dejarlo dicho porque el día que alguien decida ordenar por `weekOrder` —que es el
    /// nombre que sugiere hacerlo— va a heredar este comportamiento sin entender de dónde sale.
    @Test("U-41 · ⚠️ Una semana anterior a todas igual se lleva el orden más alto")
    func anEarlierWeekStillGetsTheHighestOrder() {
        let db = TestDB()

        let dias = [
            makeDay(date(2026, 6, 15), weekTitle: "Semana 3", weekOrder: 3, in: db.context)
        ]

        // Un día en mayo: cronológicamente **antes** que todo lo que hay.
        let info = WeekAssigner.weekInfo(for: date(2026, 5, 6), among: dias)

        #expect(info.order == 4, "Anterior en el tiempo, pero última en el orden")
        #expect(info.title == tituloEsperado(lunes: date(2026, 5, 4)))
    }

    @Test("U-41 · La semana cruza el fin de año sin confundirse con la del año anterior")
    func weeksDoNotCollideAcrossYears() {
        let db = TestDB()

        // Misma semana del año (la 1ª), años distintos. `isDate(equalTo:toGranularity: .weekOfYear)`
        // compara también el año, así que no las mezcla.
        let dias = [
            makeDay(date(2026, 1, 1), weekTitle: "Semana 1", weekOrder: 1, in: db.context)
        ]

        let info = WeekAssigner.weekInfo(for: date(2027, 1, 1), among: dias)

        #expect(info.title != "Semana 1", "Un año después es otra semana, no la misma")
        #expect(info.order == 2)
    }
}
