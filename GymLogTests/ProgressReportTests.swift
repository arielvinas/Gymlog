//
//  ProgressReportTests.swift
//  GymLogTests
//
//  El reporte que se exporta a PDF y se le manda al profesor. A diferencia de las tarjetas del
//  dashboard —que se corrigen solas la próxima vez que abrís la app— esto sale del teléfono y
//  queda. Un número mal acá se discute en persona.
//
//  Backlog: TESTING.md · U-42, U-43, U-44
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Reporte de progreso")
struct ProgressReportTests {

    /// Arma el reporte con lo mínimo: días y, si hace falta, ejercicios y logs.
    @MainActor
    private func reporte(
        days: [WorkoutDay],
        exercises: [Exercise] = [],
        logs: [SupplementLog] = [],
        today: Date
    ) -> ProgressReport {
        ProgressReportBuilder.build(
            days: days,
            exercises: exercises,
            logs: logs,
            health: HealthSnapshot(),
            today: today
        )
    }

    // MARK: - U-42 · El período

    @Test("U-42 · Sin días, el reporte sale vacío pero coherente")
    func anEmptyPlanProducesAnEmptyReport() {
        let hoy = date(2026, 6, 17)

        let r = reporte(days: [], today: hoy)

        // `periodStart` cae de vuelta en hoy: un período de un día, no una fecha inventada.
        #expect(r.periodStart == hoy)
        #expect(r.periodEnd == hoy)
        #expect(r.trainingDaysCount == 0)
        #expect(r.completedTrainingDays == 0)
        #expect(r.runCount == 0)
        #expect(r.totalActualKm == 0)
        #expect(r.avgPaceSecPerKm == nil, "Sin corridas no hay ritmo, y no es 0: es nada")
        #expect(r.longestRunKm == nil)
        #expect(r.typeCounts.isEmpty, "No se listan tipos con 0 días planificados")
        #expect(r.improvements.isEmpty)
    }

    @Test("U-42 · El período arranca en el primer día del plan y termina hoy")
    func thePeriodSpansFromTheFirstDayToToday() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            makeDay(date(2026, 6, 10), type: .fondo, in: db.context),
            makeDay(date(2026, 6, 1), type: .rodaje, in: db.context)
        ]

        let r = reporte(days: dias, today: hoy)

        // Ordena por fecha antes de tomar el primero: el orden del array no manda.
        #expect(r.periodStart == date(2026, 6, 1))
        #expect(r.periodEnd == hoy)
    }

    @Test("U-42 · Los días futuros no entran en el reporte")
    func futureDaysAreExcluded() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            makeDay(date(2026, 6, 15), type: .fondo, isCompleted: true, in: db.context),
            makeDay(date(2026, 6, 17), type: .rodaje, in: db.context),        // hoy: sí entra
            makeDay(date(2026, 6, 20), type: .fondo, in: db.context)          // futuro: no
        ]

        let r = reporte(days: dias, today: hoy)

        // El plan siembra los días por adelantado; si contaran, la adherencia arrancaría en 33%
        // y subiría sola con el tiempo. Se cuentan solo los transcurridos, hoy incluido.
        #expect(r.trainingDaysCount == 2)
        #expect(r.completedTrainingDays == 1)
        #expect(abs(r.completionRate - 0.5) < 0.0001)
    }

    // MARK: - U-44 · completionRate

    @Test("U-44 · Sin días de entrenamiento, la adherencia es 0 y no divide por cero")
    func completionRateWithNoTrainingDays() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        // Solo descansos: `trainingDays` queda vacío.
        let dias = [
            makeDay(date(2026, 6, 15), type: .descanso, in: db.context),
            makeDay(date(2026, 6, 16), type: .descanso, in: db.context)
        ]

        let r = reporte(days: dias, today: hoy)

        #expect(r.trainingDaysCount == 0)
        #expect(r.completionRate == 0, "0/0 sería NaN; el guard lo devuelve como 0")
    }

    @Test("U-44 · Los días de descanso no cuentan como entrenamiento, ni siquiera completados")
    func restDaysNeverCountAsTraining() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            makeDay(date(2026, 6, 15), type: .fondo, isCompleted: true, in: db.context),
            // Un descanso marcado como completado (ver U-40: el flag se guarda igual).
            makeDay(date(2026, 6, 16), type: .descanso, isCompleted: true, in: db.context)
        ]

        let r = reporte(days: dias, today: hoy)

        // Acá está el filtro que salva la situación de U-40: `type != .descanso`. Si el reporte
        // contara por `isCompleted` a secas, el descanso marcado inflaría la adherencia.
        #expect(r.trainingDaysCount == 1)
        #expect(r.completedTrainingDays == 1)
        #expect(r.completionRate == 1.0)
    }

    // MARK: - U-43 · Corridas, km y ritmo

    @Test("U-43 · Una corrida con km pero sin duración suma al total y no al ritmo")
    func aRunWithoutDurationCountsInKmButNotInPace() throws {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            // 10 km en 60 min → 360 s/km.
            makeDay(
                date(2026, 6, 10), type: .fondo, isCompleted: true,
                actualKm: 10, durationMinutes: 60, in: db.context
            ),
            // 5 km, te olvidaste de anotar el tiempo.
            makeDay(
                date(2026, 6, 12), type: .rodaje, isCompleted: true,
                actualKm: 5, durationMinutes: nil, in: db.context
            )
        ]

        let r = reporte(days: dias, today: hoy)

        // Los 15 km están: la distancia la corriste.
        #expect(r.totalActualKm == 15)
        #expect(r.runCount == 2)

        // Pero el ritmo promedio solo pondera las corridas **con duración**: 360 s/km, no el
        // promedio contaminado que saldría de dividir 3600 s por 15 km (240 s/km, un ritmo que
        // nunca corriste). Es la decisión correcta, y no es obvia leyendo el código.
        let ritmo = try #require(r.avgPaceSecPerKm)
        #expect(abs(ritmo - 360) < 0.001)
    }

    @Test("U-43 · El ritmo promedio se pondera por distancia, no es el promedio de los ritmos")
    func theAveragePaceIsWeightedByDistance() throws {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            // 20 km a 300 s/km (100 min).
            makeDay(
                date(2026, 6, 10), type: .fondo, isCompleted: true,
                actualKm: 20, durationMinutes: 100, in: db.context
            ),
            // 4 km a 450 s/km (30 min).
            makeDay(
                date(2026, 6, 12), type: .rodaje, isCompleted: true,
                actualKm: 4, durationMinutes: 30, in: db.context
            )
        ]

        let r = reporte(days: dias, today: hoy)

        // Total: 130 min = 7800 s sobre 24 km → 325 s/km.
        // El promedio ingenuo de los dos ritmos daría 375 s/km, castigando el fondo largo por
        // pesar lo mismo que un rodaje corto.
        let ritmo = try #require(r.avgPaceSecPerKm)
        #expect(abs(ritmo - 325) < 0.001)
    }

    @Test("U-43 · Una corrida sin completar, o sin km, no es una corrida")
    func incompleteOrDistancelessRunsAreNotCounted() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            // Completada pero sin km cargados: no se puede reportar una distancia que no está.
            makeDay(
                date(2026, 6, 10), type: .fondo, isCompleted: true, actualKm: nil, in: db.context
            ),
            // Con km pero sin marcar como hecha.
            makeDay(
                date(2026, 6, 12), type: .rodaje, isCompleted: false, actualKm: 8, in: db.context
            ),
            // Un día de fuerza, que no es corrida aunque tenga km por error.
            makeDay(
                date(2026, 6, 13), type: .fuerza, isCompleted: true, actualKm: 3, in: db.context
            )
        ]

        let r = reporte(days: dias, today: hoy)

        #expect(r.runCount == 0)
        #expect(r.totalActualKm == 0)
        #expect(r.strengthSessions == 1)
    }

    @Test("U-43 · La corrida más larga sale con su fecha")
    func theLongestRunComesWithItsDate() throws {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            makeDay(date(2026, 6, 10), type: .fondo, isCompleted: true, actualKm: 12, in: db.context),
            makeDay(date(2026, 6, 12), type: .rodaje, isCompleted: true, actualKm: 6, in: db.context),
            makeDay(date(2026, 6, 14), type: .fondo, isCompleted: true, actualKm: 18, in: db.context)
        ]

        let r = reporte(days: dias, today: hoy)

        #expect(r.longestRunKm == 18)
        #expect(try #require(r.longestRunDate) == date(2026, 6, 14))
    }

    @Test("U-43 · Las corridas recientes salen de la más nueva a la más vieja, tope de 10")
    func recentRunsAreCappedAtTen() {
        let db = TestDB()
        let hoy = date(2026, 6, 30)

        // Doce corridas, una por día.
        let dias = (0..<12).map { i in
            makeDay(
                date(2026, 6, 1 + i), type: .rodaje, isCompleted: true,
                actualKm: Double(i + 1), in: db.context
            )
        }

        let r = reporte(days: dias, today: hoy)

        #expect(r.runCount == 12, "El conteo total no se recorta…")
        #expect(r.recentRuns.count == 10, "…pero la tabla del PDF muestra 10")
        // Las 10 más recientes: del 12/6 al 3/6. La primera de la tabla es la última que corriste.
        #expect(r.recentRuns.first?.date == date(2026, 6, 12))
        #expect(r.recentRuns.last?.date == date(2026, 6, 3))
    }

    // MARK: - U-43 · Asimetrías del reporte

    /// ⚠️ **Asimetría CONFIRMADA:** todo el reporte se calcula sobre `periodDays` (los días
    /// transcurridos), **menos `improvements`**, que recibe la lista de `exercises` entera y no la
    /// filtra por fecha.
    ///
    /// Hoy no hace daño —los ejercicios de días futuros están vacíos, y `recentImprovements`
    /// descarta las sesiones sin datos—, pero significa que el reporte de un período puede citar
    /// una mejora de **fuera de ese período**. Si mañana se agrega un selector de fechas
    /// ("reporte de mayo"), la sección de fuerza va a seguir mostrando lo último que hiciste,
    /// no lo de mayo.
    @Test("U-43 · ⚠️ Las mejoras de fuerza no se filtran por el período del reporte")
    func strengthImprovementsAreNotFilteredByPeriod() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        // Un plan que arranca el 10/6…
        let dias = [makeDay(date(2026, 6, 10), type: .fuerza, isCompleted: true, in: db.context)]

        // …pero ejercicios de marzo, muy anteriores al período.
        let marzo1 = makeDay(date(2026, 3, 2), type: .fuerza, in: db.context)
        let marzo2 = makeDay(date(2026, 3, 9), type: .fuerza, in: db.context)
        let ejercicios = [
            makeExercise("Press banca", on: marzo1, sets: [(80, 8)], in: db.context),
            makeExercise("Press banca", on: marzo2, sets: [(85, 8)], in: db.context)
        ]

        let r = reporte(days: dias, exercises: ejercicios, today: hoy)

        // El período empieza el 10/6, pero la mejora reportada es de marzo.
        #expect(r.periodStart == date(2026, 6, 10))
        #expect(r.improvements.count == 1)
        #expect(r.improvements.first?.name == "Press banca")
    }

    @Test("U-43 · El km planificado suma todos los días; el real, solo los que corriste")
    func plannedKmCountsEveryDayAndActualOnlyTheCompletedOnes() {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            makeDay(
                date(2026, 6, 10), type: .fondo, title: "Fondo largo 12 km",
                isCompleted: true, actualKm: 12, in: db.context
            ),
            // Planificada, no corrida.
            makeDay(date(2026, 6, 12), type: .rodaje, title: "Rodaje 6 km", in: db.context)
        ]

        let r = reporte(days: dias, today: hoy)

        // La asimetría es deliberada (ya documentada en U-22..U-29): lo planificado es el objetivo
        // —existe lo hayas hecho o no— y lo real es el hecho. El PDF los muestra juntos, y es
        // justamente el contraste lo que el profesor quiere ver.
        #expect(r.totalPlannedKm == 18)
        #expect(r.totalActualKm == 12)
    }

    @Test("U-43 · El conteo por tipo omite los tipos que no aparecen en el plan")
    func typeCountsSkipTypesWithNoPlannedDays() throws {
        let db = TestDB()
        let hoy = date(2026, 6, 17)

        let dias = [
            makeDay(date(2026, 6, 10), type: .fondo, isCompleted: true, in: db.context),
            makeDay(date(2026, 6, 12), type: .fondo, in: db.context),
            makeDay(date(2026, 6, 13), type: .fuerza, isCompleted: true, in: db.context)
        ]

        let r = reporte(days: dias, today: hoy)

        // Solo fondo y fuerza: las filas con 0 planificados se filtran para no llenar el PDF de
        // ceros. Y el orden es el del plan (rodaje, calidad, fondo, fuerza, carrera), no el
        // alfabético ni el de aparición.
        #expect(r.typeCounts.map(\.type) == [.fondo, .fuerza])

        let fondo = try #require(r.typeCounts.first { $0.type == .fondo })
        #expect(fondo.planned == 2)
        #expect(fondo.completed == 1)
    }
}
