//
//  GuidedSessionClockTests.swift
//  GymLogTests
//
//  El reloj inyectable del engine (P0-6). Hasta ahora, los tests del descanso tenían que calcular
//  los tiempos **relativos a `restEndDate`** —"engine.restEndDate menos 30 segundos"— porque
//  `startRest` leía `Date()` por su cuenta y no había forma de saber de dónde había arrancado.
//  Funcionaba, pero se leía al revés: en vez de decir "pasaron 30 segundos", decía "faltan 60".
//
//  Con `engine.clock` inyectado, el test dice lo que quiere decir.
//
//  Backlog: TESTING.md · P0-6
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Sesión guiada · el reloj")
@MainActor
struct GuidedSessionClockTests {

    /// Un día con un ejercicio de 3 series y 90 s de descanso.
    private func dia(in context: ModelContext) -> WorkoutDay {
        let day = makeDay(date(2026, 6, 16), type: .fuerza, title: "Fuerza A", in: context)
        makeExercise(
            "Press banca", on: day, order: 0, targetReps: "8", restSeconds: 90,
            sets: [(nil, nil), (nil, nil), (nil, nil)], in: context
        )
        return day
    }

    /// Un engine con el reloj clavado en `t0`, ya descansando.
    private func engineDescansando(in db: TestDB, desde t0: Date) -> GuidedSessionEngine {
        let engine = GuidedSessionEngine()
        engine.clock = { t0 }
        engine.start(day: dia(in: db.context), context: db.context)
        engine.completeCurrent()      // marca la serie 1 y entra en descanso
        return engine
    }

    // MARK: - P0-6

    @Test("P0-6 · El descanso arranca en el instante que dice el reloj")
    func restStartsAtTheInjectedNow() throws {
        let db = TestDB()
        let t0 = date(2026, 6, 16)

        let engine = engineDescansando(in: db, desde: t0)

        #expect(engine.phase == .resting)
        // 90 s exactos desde t0. Sin el reloj inyectado esto no se podía afirmar: `restEndDate`
        // salía de un `Date()` interno y el test solo podía compararlo consigo mismo.
        #expect(try #require(engine.restEndDate) == t0.addingTimeInterval(90))
        #expect(engine.restRemaining == 90)
    }

    @Test("P0-6 · A los 30 segundos faltan 60")
    func thirtySecondsInSixtyToGo() {
        let db = TestDB()
        let t0 = date(2026, 6, 16)
        let engine = engineDescansando(in: db, desde: t0)

        engine.tickRest(now: t0.addingTimeInterval(30))

        #expect(engine.restRemaining == 60)
        #expect(engine.restOvertime == 0)
        #expect(!engine.isRestOvertime)
    }

    @Test("P0-6 · Al cumplirse el descanso avisa una vez y entra en tiempo extra")
    func atZeroItAlertsOnceAndGoesOvertime() {
        let db = TestDB()
        let t0 = date(2026, 6, 16)
        let engine = engineDescansando(in: db, desde: t0)

        var avisos = 0
        engine.onRestAlert = { avisos += 1 }

        engine.tickRest(now: t0.addingTimeInterval(90))

        #expect(avisos == 1)
        #expect(engine.restRemaining == 0)
        #expect(engine.isRestOvertime)
        // Y no avanza solo: sigue en descanso hasta que el usuario confirme (I-05).
        #expect(engine.phase == .resting)
    }

    @Test("P0-6 · El tiempo extra cuenta hacia arriba y repite el aviso cada 10 s")
    func overtimeCountsUpAndRepeatsTheAlert() {
        let db = TestDB()
        let t0 = date(2026, 6, 16)
        let engine = engineDescansando(in: db, desde: t0)

        var avisos = 0
        engine.onRestAlert = { avisos += 1 }

        engine.tickRest(now: t0.addingTimeInterval(90))   // 0 s de extra → avisa
        engine.tickRest(now: t0.addingTimeInterval(95))   // 5 s  → todavía no
        #expect(avisos == 1)
        #expect(engine.restOvertime == 5)

        engine.tickRest(now: t0.addingTimeInterval(100))  // 10 s → avisa de nuevo
        #expect(avisos == 2)
        #expect(engine.restOvertime == 10)
    }

    @Test("P0-6 · Sumar 15 s al descanso se cuenta desde ahora, no desde el arranque")
    func adjustRestIsRelativeToNow() throws {
        let db = TestDB()
        let t0 = date(2026, 6, 16)
        let engine = engineDescansando(in: db, desde: t0)

        // Pasaron 30 s: faltan 60. Movemos el reloj y pedimos 15 más.
        let ahora = t0.addingTimeInterval(30)
        engine.clock = { ahora }
        engine.tickRest(now: ahora)
        engine.adjustRest(by: 15)

        // Faltaban 60, ahora faltan 75 **desde este momento** (no 105 desde el arranque).
        #expect(engine.restRemaining == 75)
        #expect(try #require(engine.restEndDate) == ahora.addingTimeInterval(75))

        // Y el descanso recomendado del ejercicio queda recordado para la próxima serie.
        #expect(engine.restTotal == 105)
    }

    @Test("P0-6 · El snapshot se sella con la hora del reloj")
    func theSnapshotIsStampedWithTheClock() throws {
        let db = TestDB()
        let t0 = date(2026, 6, 16)
        let engine = engineDescansando(in: db, desde: t0)

        let snap = try #require(engine.makeSnapshot())

        // `updatedAt` es lo que usa la regla de descarte del canal (I-33) para decidir si un
        // snapshot es más nuevo que el que el iPhone ya tiene. Que salga del reloj inyectable
        // permite testear esa regla con fechas de verdad, en vez de con `Date()` reales que
        // cambian en cada corrida.
        #expect(snap.updatedAt == t0)
    }
}
