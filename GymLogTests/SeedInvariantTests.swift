//
//  SeedInvariantTests.swift
//  GymLogTests
//
//  El invariante que sostiene todo: después de un `AppData.seed()` completo, **no hay dos días
//  con la misma fecha**.
//
//  Es la unicidad que CloudKit **no puede** garantizar —no admite constraints `.unique`— y que
//  hoy sostiene el código a mano, encadenando cinco pasos: sembrar → actualizar el plan → cargar
//  la rutina → deduplicar → limpiar. Si el invariante se rompe, la app muestra el mismo día dos
//  veces y las métricas cuentan doble.
//
//  Backlog: TESTING.md · I-32
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Invariante del sembrado", .serialized)
struct SeedInvariantTests {

    @MainActor
    private func conFlags(_ store: InMemorySeedFlagStore, _ body: () throws -> Void) rethrows {
        let previo = AppData.seedFlags
        AppData.seedFlags = store
        defer { AppData.seedFlags = previo }
        try body()
    }

    @MainActor
    private func dias(in db: TestDB) -> [WorkoutDay] {
        (try? db.context.fetch(FetchDescriptor<WorkoutDay>())) ?? []
    }

    /// Las fechas que aparecen más de una vez. Vacío = el invariante se cumple.
    @MainActor
    private func fechasDuplicadas(in db: TestDB) -> [Date] {
        let cal = PlanConstants.calendar
        let porFecha = Dictionary(grouping: dias(in: db)) { cal.startOfDay(for: $0.date) }
        return porFecha.filter { $0.value.count > 1 }.keys.sorted()
    }

    // MARK: - I-32 · El invariante

    @Test("I-32 · Un sembrado limpio no deja fechas duplicadas")
    func aCleanSeedLeavesNoDuplicates() throws {
        let db = TestDB()

        try conFlags(InMemorySeedFlagStore()) {
            AppData.seed(context: db.context)

            #expect(!dias(in: db).isEmpty, "Sembró algo")
            #expect(fechasDuplicadas(in: db).isEmpty)
        }
    }

    @Test("I-32 · Sembrar dos veces seguidas tampoco los deja")
    func seedingTwiceLeavesNoDuplicates() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            AppData.seed(context: db.context)
            let primeraVez = dias(in: db).count

            // El segundo arranque de la app, con los flags ya marcados.
            AppData.seed(context: db.context)

            #expect(dias(in: db).count == primeraVez)
            #expect(fechasDuplicadas(in: db).isEmpty)
        }
    }

    /// El escenario real que trajo los duplicados: el iPhone y el reloj sembraron **cada uno en su
    /// store local** antes de que CloudKit sincronizara el flag "ya sembrado". Cuando la nube
    /// mergea, la base queda con **dos copias de cada día**.
    ///
    /// No se puede reproducir sembrando dos veces sobre el mismo contexto —el
    /// `guard count == 0` de `seedIfNeeded` lo impide—, así que se simula el resultado del merge:
    /// el plan insertado dos veces.
    @Test("I-32 · Tras el merge de dos dispositivos, el seed deja una sola copia de cada día")
    func theSeedCleansUpAfterACloudMerge() throws {
        let db = TestDB()

        try conFlags(InMemorySeedFlagStore()) {
            // Lo que CloudKit dejó: el plan del iPhone y el del reloj, mezclados.
            for day in WorkoutSeed.allWorkoutDays() { db.context.insert(day) }
            for day in WorkoutSeed.allWorkoutDays() { db.context.insert(day) }
            try db.context.save()

            let fechasÚnicas = Set(
                dias(in: db).map { PlanConstants.calendar.startOfDay(for: $0.date) }
            )
            #expect(dias(in: db).count == fechasÚnicas.count * 2, "Arrancamos con todo duplicado")

            AppData.seed(context: db.context)

            #expect(fechasDuplicadas(in: db).isEmpty, "El invariante se restauró")
        }
    }

    @Test("I-32 · Al deduplicar tras el merge, gana la copia con los datos del usuario")
    func theUsersCopySurvivesTheMerge() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        try conFlags(InMemorySeedFlagStore()) {
            // La copia del reloj: sembrada, nunca tocada.
            makeDay(fecha, type: .fondo, title: "Fondo largo 12 km", in: db.context)
            // La del iPhone: la corrida que registraste.
            makeDay(
                fecha, type: .fondo, title: "Fondo largo 12 km",
                isCompleted: true, actualKm: 12.4, durationMinutes: 68, in: db.context
            )
            try db.context.save()

            AppData.seed(context: db.context)

            let delQuince = dias(in: db).filter {
                PlanConstants.calendar.isDate($0.date, inSameDayAs: fecha)
            }
            #expect(delQuince.count == 1)
            #expect(delQuince.first?.actualKm == 12.4, "Sobrevivió la que tenía tus datos")
        }
    }

    /// ⚠️ El invariante se cumple **incluso en el estado del bug 10** (flag en 0 + días en la
    /// base): `seedIfNeeded` y `applyPlanUpdates` se cruzan de brazos, pero `deduplicateDays`
    /// corre igual, porque no mira ningún flag.
    ///
    /// O sea: el bug 10 congela el **plan**, no rompe la **unicidad**. Son dos problemas
    /// separados, y conviene no confundirlos al arreglar el primero.
    @Test("I-32 · El invariante sobrevive al estado del bug 10")
    func theInvariantHoldsEvenInTheBug10State() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()   // flag en 0

        try conFlags(flags) {
            // Días duplicados ya en la base, y el flag sin marcar: el estado absorbente de I-21.
            makeDay(date(2026, 6, 15), type: .fondo, in: db.context)
            makeDay(date(2026, 6, 15), type: .fondo, isCompleted: true, in: db.context)
            try db.context.save()

            AppData.seed(context: db.context)

            // El plan quedó congelado (bug 10)…
            #expect(flags.integer(forKey: "seededPlanVersion") == 0)
            // …pero los duplicados se limpiaron igual.
            #expect(fechasDuplicadas(in: db).isEmpty)
        }
    }

    // MARK: - I-32 · El orden de los pasos

    /// El orden importa y no es casual: `populateIfNeeded` corre **antes** que `deduplicateDays`.
    /// Eso significa que la rutina de fuerza se carga en **las dos copias** de un día duplicado, y
    /// recién después se borra la perdedora (que se lleva sus ejercicios en cascada, ver I-26).
    ///
    /// Es trabajo desperdiciado, no un bug: el resultado final es correcto. Pero explica por qué
    /// un primer arranque con duplicados hace más escrituras de las que uno esperaría.
    @Test("I-32 · La rutina se carga en las dos copias y después se limpia: el resultado es correcto")
    func theRoutineIsLoadedIntoBothCopiesAndThenCleaned() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 16)

        try conFlags(InMemorySeedFlagStore()) {
            makeDay(fecha, type: .fuerza, title: "Fuerza A", in: db.context)
            makeDay(fecha, type: .fuerza, title: "Fuerza A", in: db.context)
            try db.context.save()

            AppData.seed(context: db.context)

            let quedan = dias(in: db).filter {
                PlanConstants.calendar.isDate($0.date, inSameDayAs: fecha)
            }
            #expect(quedan.count == 1)

            // El día que sobrevive tiene su rutina completa, y no quedaron ejercicios huérfanos
            // de la copia borrada.
            let sobreviviente = try #require(quedan.first)
            #expect(!sobreviviente.orderedExercises.isEmpty)
            #expect(
                (try? db.context.fetchCount(FetchDescriptor<Exercise>()))
                    == sobreviviente.orderedExercises.count,
                "No sobraron ejercicios de la copia que se borró"
            )
        }
    }
}
