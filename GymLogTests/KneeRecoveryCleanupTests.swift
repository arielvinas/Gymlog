//
//  KneeRecoveryCleanupTests.swift
//  GymLogTests
//
//  La limpieza de la etapa de recuperación de rodilla (24/6 → 5/7/2026): borra los días de ese
//  tramo que quedaron vacíos y conserva los que sí entrenaste, incluida la carrera del 5/7.
//
//  Corre una sola vez, en el iPhone, y **borra sin preguntar**. A diferencia de `deduplicateDays`
//  —que al menos necesita un duplicado para hacer daño— esta función borra el día directamente si
//  lo considera vacío. Y para decidir si está vacío usa **el mismo `richness()` del bug 7**.
//
//  Backlog: TESTING.md · I-27
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Limpieza de la etapa de rodilla", .serialized)
struct KneeRecoveryCleanupTests {

    @MainActor
    private func conFlags(_ store: InMemorySeedFlagStore, _ body: () throws -> Void) rethrows {
        let previo = AppData.seedFlags
        AppData.seedFlags = store
        defer { AppData.seedFlags = previo }
        try body()
    }

    @MainActor
    private func fechas(in db: TestDB) -> Set<Date> {
        let dias = (try? db.context.fetch(FetchDescriptor<WorkoutDay>())) ?? []
        return Set(dias.map { PlanConstants.calendar.startOfDay(for: $0.date) })
    }

    private func inicioDe(_ fecha: Date) -> Date {
        PlanConstants.calendar.startOfDay(for: fecha)
    }

    // MARK: - I-27 · Lo que borra y lo que preserva

    @Test("I-27 · Borra los días vacíos del tramo y conserva los que entrenaste")
    func itDeletesTheEmptyDaysAndKeepsTheRest() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            // Vacíos: sembrados y nunca tocados.
            makeDay(date(2026, 6, 24), type: .descanso, in: db.context)
            makeDay(date(2026, 6, 28), type: .rodaje, in: db.context)
            // Con datos: una sesión completada y una corrida registrada.
            makeDay(date(2026, 6, 26), type: .fuerza, isCompleted: true, in: db.context)
            makeDay(date(2026, 7, 2), type: .rodaje, actualKm: 5, in: db.context)
            // La carrera del 5/7: el día que justifica todo el plan.
            makeDay(
                date(2026, 7, 5), type: .carrera, title: "Carrera 21 km",
                isCompleted: true, actualKm: 21.1, durationMinutes: 125, in: db.context
            )
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            let quedan = fechas(in: db)
            #expect(!quedan.contains(inicioDe(date(2026, 6, 24))), "Vacío: se fue")
            #expect(!quedan.contains(inicioDe(date(2026, 6, 28))), "Vacío: se fue")
            #expect(quedan.contains(inicioDe(date(2026, 6, 26))), "Completado: se queda")
            #expect(quedan.contains(inicioDe(date(2026, 7, 2))), "Con km: se queda")
            #expect(quedan.contains(inicioDe(date(2026, 7, 5))), "La carrera no se toca")
        }
    }

    @Test("I-27 · No toca nada fuera del tramo, ni siquiera si está vacío")
    func daysOutsideTheRangeAreUntouched() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            // Los bordes: el día antes y el día después del tramo.
            makeDay(date(2026, 6, 23), type: .rodaje, in: db.context)
            makeDay(date(2026, 7, 6), type: .rodaje, in: db.context)
            // Y uno adentro, para confirmar que la función efectivamente corrió.
            makeDay(date(2026, 6, 24), type: .rodaje, in: db.context)
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            let quedan = fechas(in: db)
            #expect(quedan.contains(inicioDe(date(2026, 6, 23))), "El 23 está afuera del tramo")
            #expect(quedan.contains(inicioDe(date(2026, 7, 6))), "El 6/7 también")
            #expect(!quedan.contains(inicioDe(date(2026, 6, 24))), "El 24 sí estaba adentro")
        }
    }

    @Test("I-27 · El tramo está clavado a 2026: un 24 de junio de otro año no le importa")
    func theRangeIsPinnedTo2026() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            makeDay(date(2027, 6, 24), type: .rodaje, in: db.context)
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            // Las fechas se construyen con `year: 2026` fijo. Es una migración de un solo uso,
            // así que está bien que sea así — pero conviene saberlo antes de reusar la función.
            #expect(fechas(in: db).contains(inicioDe(date(2027, 6, 24))))
        }
    }

    // MARK: - I-27 · Corre una sola vez

    @Test("I-27 · Marca el flag y no vuelve a correr")
    func itRunsOnlyOnce() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            makeDay(date(2026, 6, 24), type: .rodaje, in: db.context)
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            #expect(flags.bool(forKey: "cleanedKneeRecoveryV1"))
            #expect(fechas(in: db).isEmpty)

            // Un día nuevo en el tramo, agregado a mano después de la limpieza.
            makeDay(date(2026, 6, 25), type: .rodaje, in: db.context)
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            // El flag ya está: la limpieza no vuelve a correr. Si lo agregaste vos, es tuyo.
            #expect(fechas(in: db).contains(inicioDe(date(2026, 6, 25))))
        }
    }

    @Test("I-27 · Con el flag ya marcado, no borra nada")
    func withTheFlagSetItDoesNothing() throws {
        let db = TestDB()
        // Una instalación donde la limpieza ya corrió (o que la recibió por iCloud).
        let flags = InMemorySeedFlagStore(["cleanedKneeRecoveryV1": 1])

        try conFlags(flags) {
            makeDay(date(2026, 6, 24), type: .rodaje, in: db.context)
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            #expect(fechas(in: db).contains(inicioDe(date(2026, 6, 24))))
        }
    }

    // MARK: - I-27 · Bug 7, otra vez, y acá es peor

    /// ⚠️ **El bug 7 se cuela acá, y hace más daño.** La limpieza decide qué borrar con el mismo
    /// `richness(day) == 0` de la deduplicación, que **no mira `perceivedEffort`,
    /// `activeCalories` ni `ExerciseSet.isDone`** (ver I-28).
    ///
    /// En `deduplicateDays` el bug necesita un duplicado para hacer daño: elige mal entre dos
    /// copias. Acá **no necesita nada**: si el día del tramo tiene solo esos campos, `richness`
    /// da 0, y el día **se borra directamente**. Un solo `seed()` y no vuelve.
    ///
    /// Concretamente, se pierden los días de la recuperación donde:
    ///   - hiciste la rutina **tildando las series** sin anotar los kilos, o
    ///   - anotaste solo el **esfuerzo percibido** (que es *justamente* lo que uno registra
    ///     mientras se recupera de una lesión, cuando no hay carga ni distancia que anotar).
    @Test("I-27 · ⚠️ Un día del tramo con solo esfuerzo percibido se borra")
    func aDayWithOnlyPerceivedEffortIsDeleted() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            // Rehabilitación: no hay km ni peso que anotar, pero sí cómo te sentiste.
            let rehab = makeDay(date(2026, 6, 27), type: .rodaje, in: db.context)
            rehab.perceivedEffort = 4
            rehab.activeCalories = 180
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            #expect(
                !fechas(in: db).contains(inicioDe(date(2026, 6, 27))),
                "Registraste el esfuerzo y las calorías, y el día se borró igual"
            )
        }
    }

    @Test("I-27 · ⚠️ Un día del tramo con las series tildadas también se borra")
    func aDayWithOnlyTickedSetsIsDeleted() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            let dia = makeDay(date(2026, 6, 29), type: .fuerza, in: db.context)
            let ejercicio = makeExercise(
                "Extensión de rodillas", on: dia, order: 0,
                sets: [(nil, nil), (nil, nil), (nil, nil)], in: db.context
            )
            for set in ejercicio.orderedSets { set.isDone = true }
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            #expect(!fechas(in: db).contains(inicioDe(date(2026, 6, 29))))
            // Y se llevó los ejercicios con él, en cascada.
            #expect((try? db.context.fetchCount(FetchDescriptor<Exercise>())) == 0)
        }
    }

    @Test("I-27 · Con una sola serie con peso, el mismo día se salva")
    func oneSetWithWeightIsEnoughToSaveTheDay() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            let dia = makeDay(date(2026, 6, 29), type: .fuerza, in: db.context)
            // La diferencia con el test anterior: **un** peso anotado.
            makeExercise(
                "Extensión de rodillas", on: dia, order: 0,
                sets: [(20, 12), (nil, nil), (nil, nil)], in: db.context
            )
            try db.context.save()

            WorkoutSeed.cleanupKneeRecoveryIfNeeded(context: db.context)

            // Deja claro dónde está exactamente el límite: el día se salva por el peso, no por
            // haber entrenado. Tildar las tres series no alcanza; anotar un número, sí.
            #expect(fechas(in: db).contains(inicioDe(date(2026, 6, 29))))
        }
    }
}
