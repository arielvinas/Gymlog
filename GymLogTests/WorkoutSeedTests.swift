//
//  WorkoutSeedTests.swift
//  GymLogTests
//
//  El sembrado del plan: qué se inserta en el primer arranque y qué pasa cuando sube la versión.
//  Es el código que corre en cada `init()` de la app, en los tres dispositivos, sobre una base que
//  CloudKit puede haber llenado a medias. No hay forma de mirarlo "en producción": o se testea, o
//  se confía.
//
//  ⚠️ La suite es **serializada** a propósito: `AppData.seedFlags` es un global, y Swift Testing
//  corre los tests en paralelo. Sin `.serialized`, dos tests se pisarían el store.
//
//  Backlog: TESTING.md · I-21, I-22, I-23
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Sembrado del plan", .serialized)
struct WorkoutSeedTests {

    /// Corre el cuerpo con un store de flags en memoria y después devuelve el real.
    @MainActor
    private func conFlags(
        _ store: InMemorySeedFlagStore,
        _ body: () throws -> Void
    ) rethrows {
        let previo = AppData.seedFlags
        AppData.seedFlags = store
        defer { AppData.seedFlags = previo }
        try body()
    }

    @MainActor
    private func dias(in db: TestDB) -> [WorkoutDay] {
        (try? db.context.fetch(FetchDescriptor<WorkoutDay>())) ?? []
    }

    // MARK: - I-22 · El camino feliz

    @Test("I-22 · En una base vacía siembra el plan y marca la versión")
    func itSeedsAnEmptyDatabase() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            #expect(dias(in: db).isEmpty)

            WorkoutSeed.seedIfNeeded(context: db.context)

            #expect(dias(in: db).count == WorkoutSeed.allWorkoutDays().count)
            #expect(
                flags.integer(forKey: "seededPlanVersion") == WorkoutSeed.planVersion,
                "Marca la versión: es lo que evita re-sembrar en el próximo arranque"
            )
        }
    }

    @Test("I-22 · Sembrar dos veces no duplica nada")
    func seedingTwiceIsIdempotent() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()

        try conFlags(flags) {
            WorkoutSeed.seedIfNeeded(context: db.context)
            let despuésDelPrimero = dias(in: db).count

            // El segundo arranque de la app.
            WorkoutSeed.seedIfNeeded(context: db.context)

            #expect(dias(in: db).count == despuésDelPrimero)
        }
    }

    @Test("I-22 · Con la versión ya sembrada, no vuelve a tocar la base")
    func itDoesNothingWhenAlreadySeeded() throws {
        let db = TestDB()
        // Una instalación que ya sembró, pero cuya base todavía no bajó de CloudKit.
        let flags = InMemorySeedFlagStore(["seededPlanVersion": WorkoutSeed.planVersion])

        try conFlags(flags) {
            WorkoutSeed.seedIfNeeded(context: db.context)

            // El guard de la versión corta primero: no siembra aunque la base esté vacía. Es lo
            // correcto —si sembrara, duplicaría todo cuando CloudKit termine de bajar los días—.
            #expect(dias(in: db).isEmpty)
        }
    }

    // MARK: - I-21 · Bug 10, el estado absorbente

    /// ⚠️ **Bug 10 CONFIRMADO y alcanzable.** `seedIfNeeded` tiene dos guardas:
    ///
    /// ```swift
    /// guard storedVersion == 0 else { return }   // no sembrado todavía
    /// guard count == 0 else { return }           // …y sin días locales
    /// ```
    ///
    /// La segunda sale **sin marcar la versión**. Y `applyPlanUpdates` arranca con
    /// `guard stored >= 1 else { return }`. O sea: con el flag en 0 **y** días ya en la base, las
    /// dos funciones se cruzan de brazos, y el flag **nunca sube de 0**. El plan no se actualiza
    /// nunca más: es un estado absorbente, no se sale solo.
    ///
    /// Y llegar ahí es fácil: instalás la app en un dispositivo nuevo, CloudKit baja los días
    /// antes de que sincronice el flag (son dos stores distintos, sin orden garantizado entre
    /// ellos), y el primer `seed()` encuentra exactamente esa combinación.
    @Test("I-21 · ⚠️ Con días en la base y el flag en 0, el plan queda congelado para siempre")
    func theSeedGetsStuckWithDaysAndNoFlag() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore()   // flag en 0: "nunca sembré"

        try conFlags(flags) {
            // CloudKit ya bajó un día, pero el flag todavía no llegó.
            makeDay(date(2026, 6, 1), type: .descanso, in: db.context)

            WorkoutSeed.seedIfNeeded(context: db.context)

            // No siembra (bien: duplicaría). Pero tampoco marca la versión.
            #expect(dias(in: db).count == 1)
            #expect(flags.integer(forKey: "seededPlanVersion") == 0, "Salió sin marcar nada")

            // Y `applyPlanUpdates` exige `stored >= 1`, así que también se va sin hacer nada.
            WorkoutSeed.applyPlanUpdates(context: db.context)

            #expect(dias(in: db).count == 1, "El plan no se completó")
            #expect(flags.integer(forKey: "seededPlanVersion") == 0)

            // Es absorbente: por más veces que arranque la app, el estado no se mueve.
            for _ in 0..<5 {
                WorkoutSeed.seedIfNeeded(context: db.context)
                WorkoutSeed.applyPlanUpdates(context: db.context)
            }
            #expect(dias(in: db).count == 1, "Cinco arranques después, sigue igual de roto")
            #expect(flags.integer(forKey: "seededPlanVersion") == 0)
        }
    }

    // MARK: - I-23 · La contradicción del comentario

    /// ⚠️ **Contradicción CONFIRMADA entre el código y su comentario.** `applyPlanUpdates` dice:
    ///
    /// > *"Los días que el usuario borre no se vuelven a insertar."*
    ///
    /// Pero compara **por fecha** contra el plan canónico e inserta lo que falte. Un día borrado
    /// es, por definición, una fecha que falta. Así que al subir `planVersion`, **reaparece**.
    ///
    /// El comentario describe lo que la función hace *dentro de una misma versión* (donde el
    /// `guard stored < planVersion` la hace no correr). Entre versiones, no.
    ///
    /// **No lo arreglo**: hay que decidir cuál gana. Para respetar el borrado hace falta recordar
    /// qué fechas borró el usuario (una lista de tombstones), y eso es una decisión de producto,
    /// no un bug con un fix obvio.
    @Test("I-23 · ⚠️ Al subir la versión del plan, el día que borraste reaparece")
    func aDeletedDayComesBackOnAVersionBump() throws {
        let db = TestDB()
        // Sembrado con la versión 1; la actual es 2.
        let flags = InMemorySeedFlagStore(["seededPlanVersion": 1])

        try conFlags(flags) {
            // Simula la base después del sembrado v1: todo el plan menos un día que el usuario
            // borró a propósito (no quería entrenar el 2/6).
            let planCompleto = WorkoutSeed.allWorkoutDays()
            let cal = PlanConstants.calendar
            let borrado = cal.startOfDay(for: date(2026, 6, 2))

            for day in planCompleto where cal.startOfDay(for: day.date) != borrado {
                db.context.insert(day)
            }
            try db.context.save()

            let antes = dias(in: db).count
            #expect(antes == planCompleto.count - 1)
            #expect(!dias(in: db).contains { cal.startOfDay(for: $0.date) == borrado })

            WorkoutSeed.applyPlanUpdates(context: db.context)

            // El día borrado volvió: la función no distingue "nunca existió" de "lo borraste".
            #expect(
                dias(in: db).contains { cal.startOfDay(for: $0.date) == borrado },
                "El 2/6 reapareció, contra lo que promete el comentario"
            )
            #expect(flags.integer(forKey: "seededPlanVersion") == WorkoutSeed.planVersion)
        }
    }

    @Test("I-23 · Dentro de la misma versión, no reinserta nada")
    func withinTheSameVersionNothingIsReinserted() throws {
        let db = TestDB()
        // Ya sembrado con la versión actual.
        let flags = InMemorySeedFlagStore(["seededPlanVersion": WorkoutSeed.planVersion])

        try conFlags(flags) {
            let cal = PlanConstants.calendar
            let borrado = cal.startOfDay(for: date(2026, 6, 2))
            for day in WorkoutSeed.allWorkoutDays() where cal.startOfDay(for: day.date) != borrado {
                db.context.insert(day)
            }
            try db.context.save()
            let antes = dias(in: db).count

            WorkoutSeed.applyPlanUpdates(context: db.context)

            // `guard stored < planVersion` la corta de entrada. Acá el comentario **sí** vale:
            // el día borrado sigue borrado. La promesa se rompe recién en el salto de versión.
            #expect(dias(in: db).count == antes)
            #expect(!dias(in: db).contains { cal.startOfDay(for: $0.date) == borrado })
        }
    }

    @Test("I-23 · Al subir la versión, los días existentes no se pisan")
    func existingDaysAreNotOverwrittenOnAVersionBump() throws {
        let db = TestDB()
        let flags = InMemorySeedFlagStore(["seededPlanVersion": 1])

        try conFlags(flags) {
            // Un día del plan que el usuario ya completó y editó.
            let mío = makeDay(
                date(2026, 6, 2), type: .fuerza, title: "Fuerza A · mi versión",
                isCompleted: true, in: db.context
            )
            try db.context.save()

            WorkoutSeed.applyPlanUpdates(context: db.context)

            // La fecha ya existe, así que no se inserta ni se toca: lo que cargaste manda.
            let delDos = dias(in: db).filter {
                PlanConstants.calendar.isDate($0.date, inSameDayAs: date(2026, 6, 2))
            }
            #expect(delDos.count == 1, "No lo duplica")
            #expect(delDos.first?.title == "Fuerza A · mi versión", "No lo pisa")
            #expect(mío.isCompleted)
        }
    }
}
