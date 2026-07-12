//
//  DeduplicateDaysTests.swift
//  GymLogTests
//
//  La limpieza de días duplicados. Cuando el iPhone y el reloj siembran el plan antes de que
//  CloudKit sincronice el flag "ya sembrado", queda un día por fecha **de cada uno**. Esta función
//  elige cuál sobrevive y borra el resto.
//
//  Es la única parte del código que **borra datos del usuario sin preguntar**. Si elige mal, lo
//  que se pierde no vuelve.
//
//  Backlog: TESTING.md · I-24, I-25, I-26, I-28
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Deduplicación de días")
struct DeduplicateDaysTests {

    @MainActor
    private func dias(in db: TestDB) -> [WorkoutDay] {
        (try? db.context.fetch(FetchDescriptor<WorkoutDay>())) ?? []
    }

    @MainActor
    private func dias(on fecha: Date, in db: TestDB) -> [WorkoutDay] {
        dias(in: db).filter { PlanConstants.calendar.isDate($0.date, inSameDayAs: fecha) }
    }

    // MARK: - I-24 · El camino feliz

    @Test("I-24 · Sin duplicados no toca nada")
    func withoutDuplicatesItDoesNothing() {
        let db = TestDB()

        makeDay(date(2026, 6, 15), type: .fuerza, in: db.context)
        makeDay(date(2026, 6, 16), type: .rodaje, in: db.context)

        WorkoutSeed.deduplicateDays(context: db.context)

        #expect(dias(in: db).count == 2)
    }

    @Test("I-24 · Entre dos copias, gana la que tiene datos del usuario")
    func theDayWithUserDataWins() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        // La copia del reloj: sembrada y nunca tocada.
        makeDay(fecha, type: .fondo, title: "Fondo largo 12 km", in: db.context)
        // La copia del iPhone: la que usaste de verdad.
        makeDay(
            fecha, type: .fondo, title: "Fondo largo 12 km",
            isCompleted: true, actualKm: 12.4, durationMinutes: 68, in: db.context
        )
        try db.context.save()

        WorkoutSeed.deduplicateDays(context: db.context)

        let sobrevive = try #require(dias(on: fecha, in: db).first)
        #expect(dias(on: fecha, in: db).count == 1)
        #expect(sobrevive.isCompleted)
        #expect(sobrevive.actualKm == 12.4, "Se quedó con la corrida que registraste")
    }

    @Test("I-24 · Con tres copias sobrevive una sola")
    func threeCopiesCollapseToOne() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        makeDay(fecha, type: .fondo, in: db.context)
        makeDay(fecha, type: .fondo, in: db.context)
        makeDay(fecha, type: .fondo, isCompleted: true, actualKm: 12, in: db.context)
        try db.context.save()

        WorkoutSeed.deduplicateDays(context: db.context)

        #expect(dias(on: fecha, in: db).count == 1)
        #expect(try #require(dias(on: fecha, in: db).first).actualKm == 12)
    }

    @Test("I-24 · Correrla dos veces no cambia el resultado")
    func itIsIdempotent() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        makeDay(fecha, type: .fondo, in: db.context)
        makeDay(fecha, type: .fondo, isCompleted: true, in: db.context)
        try db.context.save()

        WorkoutSeed.deduplicateDays(context: db.context)
        let despuésDeLaPrimera = dias(in: db).count

        WorkoutSeed.deduplicateDays(context: db.context)

        #expect(dias(in: db).count == despuésDeLaPrimera)
        #expect(despuésDeLaPrimera == 1)
    }

    @Test("I-24 · Solo agrupa por fecha: días distintos no compiten")
    func daysOnDifferentDatesNeverCompete() {
        let db = TestDB()

        // Dos días distintos, uno vacío y uno con datos. No son duplicados.
        makeDay(date(2026, 6, 15), type: .fondo, isCompleted: true, actualKm: 12, in: db.context)
        makeDay(date(2026, 6, 16), type: .rodaje, in: db.context)

        WorkoutSeed.deduplicateDays(context: db.context)

        #expect(dias(in: db).count == 2, "El vacío del 16 no se borra por ser más pobre que el 15")
    }

    // MARK: - I-26 · El borrado arrastra los ejercicios

    @Test("I-26 · Al borrar la copia perdedora, sus ejercicios y series se van con ella")
    func deletingALoserCascadesToItsExercises() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        // La copia que va a perder, con su rutina sembrada (sin datos cargados).
        let perdedora = makeDay(fecha, type: .fuerza, in: db.context)
        makeExercise("Press banca", on: perdedora, order: 0, sets: [(nil, nil), (nil, nil)], in: db.context)

        // La ganadora: completada.
        let ganadora = makeDay(fecha, type: .fuerza, isCompleted: true, in: db.context)
        makeExercise("Press banca", on: ganadora, order: 0, sets: [(80, 8)], in: db.context)
        try db.context.save()

        #expect((try? db.context.fetchCount(FetchDescriptor<Exercise>())) == 2)
        #expect((try? db.context.fetchCount(FetchDescriptor<ExerciseSet>())) == 3)

        WorkoutSeed.deduplicateDays(context: db.context)

        // La regla de borrado en cascada de `WorkoutDay.exercises` hace el trabajo: no quedan
        // ejercicios ni series colgando de un día que ya no existe.
        #expect(dias(on: fecha, in: db).count == 1)
        #expect((try? db.context.fetchCount(FetchDescriptor<Exercise>())) == 1, "Sin huérfanos")
        #expect((try? db.context.fetchCount(FetchDescriptor<ExerciseSet>())) == 1)
    }

    // MARK: - I-28 · Bug 7 · Lo que la "riqueza" no mira

    /// ⚠️ **Bug 7 CONFIRMADO y alcanzable.** `richness()` puntúa `isCompleted`, `actualKm`,
    /// `durationMinutes`, `avgHeartRate`, `notes` y las series con reps o peso. **No mira**
    /// `perceivedEffort`, `activeCalories` ni `ExerciseSet.isDone`.
    ///
    /// O sea: un día donde registraste el esfuerzo percibido y las calorías vale **cero**. Una
    /// nota de un solo carácter (`+10`) le gana. Y si el duplicado también está vacío, los dos
    /// empatan en 0 y el que sobrevive lo decide el desempate por ID —una moneda al aire sobre
    /// **tus datos**—.
    ///
    /// El test no depende del ID: le da a la copia vacía una nota, que sí puntúa. Si el esfuerzo
    /// y las calorías valieran algo, la copia con datos ganaría igual. Pierde.
    @Test("I-28 · ⚠️ El esfuerzo percibido y las calorías no cuentan: una nota de una letra les gana")
    func effortAndCaloriesAreWorthNothing() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        // Copia A: solo una nota. Puntaje: 10.
        makeDay(fecha, type: .fondo, in: db.context).notes = "x"
        // Copia B: el esfuerzo que cargaste y las calorías que trajo el reloj. Puntaje: 0.
        let conDatos = makeDay(fecha, type: .fondo, in: db.context)
        conDatos.perceivedEffort = 8
        conDatos.activeCalories = 620
        try db.context.save()

        WorkoutSeed.deduplicateDays(context: db.context)

        let sobrevive = try #require(dias(on: fecha, in: db).first)
        #expect(dias(on: fecha, in: db).count == 1)
        #expect(sobrevive.notes == "x")
        #expect(sobrevive.perceivedEffort == nil, "El esfuerzo se borró")
        #expect(sobrevive.activeCalories == nil, "Y las calorías también")
    }

    /// ⚠️ **La otra mitad del bug 7 (y el bug 9).** `richness()` cuenta las series con `reps` o
    /// `weight`, pero **no las que solo están tildadas** (`isDone`). El día que hiciste la rutina
    /// tildando cada serie sin anotar los kilos vale **cero**.
    @Test("I-28 · ⚠️ Las series tildadas sin peso ni reps valen cero")
    func tickedSetsWithoutDataAreWorthNothing() throws {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        // Copia A: solo una nota. Puntaje: 10.
        makeDay(fecha, type: .fuerza, in: db.context).notes = "x"

        // Copia B: la sesión que hiciste, tildando las cinco series sin anotar los kilos.
        let entrenada = makeDay(fecha, type: .fuerza, in: db.context)
        let ejercicio = makeExercise(
            "Press banca", on: entrenada, order: 0,
            sets: [(nil, nil), (nil, nil), (nil, nil), (nil, nil), (nil, nil)],
            in: db.context
        )
        for set in ejercicio.orderedSets { set.isDone = true }
        try db.context.save()

        WorkoutSeed.deduplicateDays(context: db.context)

        let sobrevive = try #require(dias(on: fecha, in: db).first)
        #expect(sobrevive.notes == "x")
        #expect(
            sobrevive.orderedExercises.first?.orderedSets.contains { $0.isDone } != true,
            "La sesión tildada se borró entera"
        )
    }

    @Test("I-28 · Lo que sí cuenta, cuenta en el orden esperado")
    func whatCountsIsRankedAsExpected() throws {
        let db = TestDB()

        // Completado (1000) le gana a km (200).
        let f1 = date(2026, 6, 15)
        makeDay(f1, type: .fondo, actualKm: 20, in: db.context)
        makeDay(f1, type: .fondo, isCompleted: true, in: db.context)

        // Km (200) le gana a duración (50).
        let f2 = date(2026, 6, 16)
        makeDay(f2, type: .fondo, durationMinutes: 90, in: db.context)
        makeDay(f2, type: .fondo, actualKm: 5, in: db.context)
        try db.context.save()

        WorkoutSeed.deduplicateDays(context: db.context)

        #expect(try #require(dias(on: f1, in: db).first).isCompleted)
        #expect(try #require(dias(on: f2, in: db).first).actualKm == 5)
    }

    // MARK: - I-25 · El desempate

    /// ⚠️ Con dos copias de **igual riqueza**, el desempate es
    /// `String(describing: persistentModelID)`. El comentario del código lo llama "id estable
    /// (consistente en el device)", y para el caso normal alcanza: si las dos copias empatan
    /// porque **las dos están vacías**, da igual cuál sobrevive.
    ///
    /// El problema no es el desempate: **es el bug 7.** Cuando `richness()` no mira un campo que
    /// el usuario llenó, dos días que *no* son equivalentes terminan empatados, y ahí el sorteo
    /// por ID decide sobre datos reales. El desempate arbitrario es inofensivo *solo mientras*
    /// la función de riqueza sea completa. Hoy no lo es.
    @Test("I-25 · Con dos copias vacías sobrevive exactamente una, y da igual cuál")
    func aTieLeavesExactlyOneSurvivor() {
        let db = TestDB()
        let fecha = date(2026, 6, 15)

        makeDay(fecha, type: .fondo, title: "Fondo largo 12 km", in: db.context)
        makeDay(fecha, type: .fondo, title: "Fondo largo 12 km", in: db.context)

        WorkoutSeed.deduplicateDays(context: db.context)

        // No se afirma **cuál** sobrevive: son intercambiables. Lo que importa es que quede una.
        let quedan = dias(on: fecha, in: db)
        #expect(quedan.count == 1)
        #expect(quedan.first?.title == "Fondo largo 12 km")
    }
}
