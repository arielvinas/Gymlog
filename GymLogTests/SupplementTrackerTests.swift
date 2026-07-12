//
//  SupplementTrackerTests.swift
//  GymLogTests
//
//  Adherencia y racha de suplementos. Son los dos números que la app te muestra para que sigas
//  tomándolos, así que tienen que ser honestos: una racha inflada no motiva, miente.
//
//  Backlog: TESTING.md · U-38, U-39
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Suplementos · adherencia y racha")
struct SupplementTrackerTests {

    /// Un registro de toma. `SupplementTracker` no consulta la base: recibe los logs ya cargados,
    /// así que alcanza con construirlos.
    private func log(_ kind: SupplementKind, _ fecha: Date) -> SupplementLog {
        SupplementLog(date: fecha, kind: kind)
    }

    // MARK: - U-38 · Adherencia

    @Test("U-38 · La adherencia es la fracción de días tomados en la ventana")
    func adherenceIsTheFractionOfDaysTaken() {
        let hoy = date(2026, 6, 17)
        // Tomada hoy, ayer y hace cuatro días: 3 de los últimos 7.
        let logs = [
            log(.creatina, hoy),
            log(.creatina, date(2026, 6, 16)),
            log(.creatina, date(2026, 6, 13))
        ]

        let adherencia = SupplementTracker.adherence(.creatina, lastDays: 7, logs: logs, today: hoy)

        #expect(abs(adherencia - 3.0 / 7.0) < 0.0001)
    }

    @Test("U-38 · La ventana incluye hoy y va hacia atrás")
    func theWindowIncludesToday() {
        let hoy = date(2026, 6, 17)

        // Ventana de 1 día = solo hoy.
        #expect(
            SupplementTracker.adherence(
                .creatina, lastDays: 1, logs: [log(.creatina, hoy)], today: hoy
            ) == 1.0
        )
        #expect(
            SupplementTracker.adherence(
                .creatina, lastDays: 1, logs: [log(.creatina, date(2026, 6, 16))], today: hoy
            ) == 0.0
        )
    }

    @Test("U-38 · El día que queda justo afuera de la ventana no cuenta")
    func theDayJustOutsideTheWindowDoesNotCount() {
        let hoy = date(2026, 6, 17)

        // Con `lastDays: 7`, la ventana son los offsets 0..6: del 11 al 17. El 10 queda afuera.
        let dentro = SupplementTracker.adherence(
            .creatina, lastDays: 7, logs: [log(.creatina, date(2026, 6, 11))], today: hoy
        )
        let afuera = SupplementTracker.adherence(
            .creatina, lastDays: 7, logs: [log(.creatina, date(2026, 6, 10))], today: hoy
        )

        #expect(abs(dentro - 1.0 / 7.0) < 0.0001)
        #expect(afuera == 0.0)
    }

    @Test("U-38 · Una ventana de 0 días o negativa devuelve 0, no divide por cero")
    func aNonPositiveWindowReturnsZero() {
        let hoy = date(2026, 6, 17)
        let logs = [log(.creatina, hoy)]

        // El `guard days > 0` está: sin él, `Double(1) / Double(0)` daría infinito y la barra de
        // progreso se rompería. El único call site que podría pasar algo raro
        // (`ProgressReportBuilder`, con `planDays`) ya lo protege aparte con un `max(1, ...)`.
        #expect(SupplementTracker.adherence(.creatina, lastDays: 0, logs: logs, today: hoy) == 0)
        #expect(SupplementTracker.adherence(.creatina, lastDays: -5, logs: logs, today: hoy) == 0)
    }

    @Test("U-38 · Dos registros el mismo día cuentan una sola vez")
    func duplicateLogsOnTheSameDayCountOnce() {
        let hoy = date(2026, 6, 17)
        // Un duplicado no debería existir (`toggle` borra en vez de agregar), pero la sincronización
        // con iCloud ya nos regaló días duplicados antes: conviene que el cálculo aguante.
        let logs = [log(.creatina, hoy), log(.creatina, hoy)]

        let adherencia = SupplementTracker.adherence(.creatina, lastDays: 7, logs: logs, today: hoy)

        // `isTaken` pregunta "¿hay alguno?", no "¿cuántos hay?". Así que 1/7, no 2/7 —que sería
        // una adherencia inventada—.
        #expect(abs(adherencia - 1.0 / 7.0) < 0.0001)
    }

    @Test("U-38 · Un registro futuro no cuenta")
    func futureLogsDoNotCount() {
        let hoy = date(2026, 6, 17)
        let logs = [log(.creatina, date(2026, 6, 18))]

        // La ventana se construye hacia atrás desde hoy, así que mañana nunca entra. Bien: la
        // adherencia mide lo que hiciste, no lo que pensás hacer.
        #expect(SupplementTracker.adherence(.creatina, lastDays: 7, logs: logs, today: hoy) == 0)
    }

    @Test("U-38 · Cada suplemento cuenta por separado")
    func eachSupplementIsCountedSeparately() {
        let hoy = date(2026, 6, 17)
        let logs = [log(.creatina, hoy), log(.proteina, date(2026, 6, 16))]

        #expect(
            abs(
                SupplementTracker.adherence(.creatina, lastDays: 7, logs: logs, today: hoy)
                    - 1.0 / 7.0
            ) < 0.0001
        )
        #expect(
            abs(
                SupplementTracker.adherence(.proteina, lastDays: 7, logs: logs, today: hoy)
                    - 1.0 / 7.0
            ) < 0.0001
        )
    }

    // MARK: - U-39 · Racha

    @Test("U-39 · Tomada hoy y los dos días anteriores: racha de 3")
    func threeConsecutiveDays() {
        let hoy = date(2026, 6, 17)
        let logs = [
            log(.creatina, hoy),
            log(.creatina, date(2026, 6, 16)),
            log(.creatina, date(2026, 6, 15))
        ]

        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 3)
    }

    @Test("U-39 · El día en curso no corta la racha: si hoy todavía no la tomaste, cuenta hasta ayer")
    func todayDoesNotBreakTheStreakYet() {
        let hoy = date(2026, 6, 17)
        // Ayer y anteayer sí; hoy todavía no (son las 10 de la mañana, la tomás a la tarde).
        let logs = [log(.creatina, date(2026, 6, 16)), log(.creatina, date(2026, 6, 15))]

        // Sin esta gracia, la racha se vería en 0 toda la mañana y volvería a 3 al mediodía. La
        // decisión de arrancar en ayer cuando hoy está vacío es lo que la hace usable.
        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 2)
    }

    @Test("U-39 · Con un solo día, la racha es 1 — lo hayas tomado hoy o ayer")
    func aSingleDayIsAStreakOfOne() {
        let hoy = date(2026, 6, 17)

        #expect(
            SupplementTracker.currentStreak(.creatina, logs: [log(.creatina, hoy)], today: hoy) == 1
        )
        #expect(
            SupplementTracker.currentStreak(
                .creatina, logs: [log(.creatina, date(2026, 6, 16))], today: hoy
            ) == 1
        )
    }

    @Test("U-39 · Un hueco corta la racha")
    func aGapBreaksTheStreak() {
        let hoy = date(2026, 6, 17)
        // Hoy sí, ayer no, y antes una racha larga que ya no cuenta.
        let logs = [
            log(.creatina, hoy),
            log(.creatina, date(2026, 6, 15)),
            log(.creatina, date(2026, 6, 14)),
            log(.creatina, date(2026, 6, 13))
        ]

        // La racha es "hasta hoy", no "la más larga que tuviste".
        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 1)
    }

    @Test("U-39 · Sin hoy ni ayer, la racha es 0 aunque venga de una buena semana")
    func twoMissedDaysResetTheStreak() {
        let hoy = date(2026, 6, 17)
        // Última toma: anteayer. Ya pasaron dos días en blanco.
        let logs = [log(.creatina, date(2026, 6, 15)), log(.creatina, date(2026, 6, 14))]

        // El arranque en ayer es una sola gracia, no un colchón de dos días.
        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 0)
    }

    @Test("U-39 · Sin registros, la racha es 0")
    func noLogsMeansNoStreak() {
        #expect(SupplementTracker.currentStreak(.creatina, logs: [], today: date(2026, 6, 17)) == 0)
    }

    @Test("U-39 · Los duplicados no inflan la racha")
    func duplicateLogsDoNotInflateTheStreak() {
        let hoy = date(2026, 6, 17)
        let logs = [
            log(.creatina, hoy), log(.creatina, hoy),
            log(.creatina, date(2026, 6, 16)), log(.creatina, date(2026, 6, 16))
        ]

        // Igual que en la adherencia: el bucle avanza por días, no por registros.
        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 2)
    }

    @Test("U-39 · Un registro futuro no adelanta la racha")
    func aFutureLogDoesNotExtendTheStreak() {
        let hoy = date(2026, 6, 17)
        let logs = [log(.creatina, date(2026, 6, 18)), log(.creatina, hoy)]

        // El bucle solo mira hacia atrás desde hoy. Mañana no suma —todavía no pasó—.
        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 1)
    }

    @Test("U-39 · La racha cruza el fin de mes")
    func theStreakCrossesAMonthBoundary() {
        let hoy = date(2026, 7, 2)
        let logs = [
            log(.creatina, hoy),
            log(.creatina, date(2026, 7, 1)),
            log(.creatina, date(2026, 6, 30)),
            log(.creatina, date(2026, 6, 29))
        ]

        // Suma días con el calendario, no con aritmética de fechas a mano: el salto de junio a
        // julio no la corta.
        #expect(SupplementTracker.currentStreak(.creatina, logs: logs, today: hoy) == 4)
    }
}
