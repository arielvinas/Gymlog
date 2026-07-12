//
//  WeeklyVolumeTests.swift
//  GymLogTests
//
//  El volumen semanal: los kilómetros corridos y el **tonelaje** levantado. Son
//  los números de la tarjeta de tendencia — lo que el usuario mira para saber si
//  está progresando. Si suman mal, mienten en silencio: no hay forma de darse
//  cuenta desde la app.
//
//  Backlog: TESTING.md · U-22..U-29
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Volumen semanal")
struct WeeklyVolumeTests {

    /// Un miércoles cualquiera, lejos de los bordes de la semana.
    private let miercoles = date(2026, 6, 17)

    // MARK: - U-22

    @Test("U-22 · El tonelaje es la suma de peso × reps de cada serie")
    func tonnageIsTheSumOfWeightTimesReps() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // 3 series de press: 80×8, 80×8, 85×6 → 640 + 640 + 510 = 1790.
        let press = makeExercise("Press banca", on: day, order: 0,
                                 sets: [(80, 8), (80, 8), (85, 6)], in: db.context)

        let total = WeeklyVolume.tonnage(for: miercoles, among: [press])
        #expect(total == 1790)
    }

    @Test("U-22 · Las series sin peso o sin reps no suman")
    func setsWithoutWeightOrRepsDoNotCount() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // El core y la plancha no llevan peso (ver U-21), así que sus series tienen reps
        // pero no kilos. Si contaran como peso 0 el resultado sería el mismo, pero si
        // contaran como peso 1 —o si `weight` viniera con basura— inflarían el tonelaje.
        let plancha = makeExercise("Puente lateral", on: day, order: 0,
                                   sets: [(nil, 30), (nil, 30)], in: db.context)

        // Y una serie cargada a medias: el usuario puso el peso pero no las reps (se fue del
        // gimnasio antes de anotarlas). No hay forma de saber cuánto levantó.
        let press = makeExercise("Press banca", on: day, order: 1,
                                 sets: [(80, 8), (80, nil)], in: db.context)

        let total = WeeklyVolume.tonnage(for: miercoles, among: [plancha, press])

        // Solo la serie completa: 80 × 8. La plancha no aporta, y la serie a medias tampoco.
        #expect(total == 640)
    }

    @Test("U-22 · Solo cuentan los ejercicios de esa semana")
    func onlyThisWeeksExercisesCount() {
        let db = TestDB()

        let estaSemana = makeDay(miercoles, type: .fuerza, in: db.context)
        let deEstaSemana = makeExercise("Press banca", on: estaSemana, order: 0,
                                        sets: [(80, 10)], in: db.context)

        // El lunes de la semana siguiente. El filtro es por semana calendario
        // (`toGranularity: .weekOfYear`), no por "hace 7 días".
        let semanaQueViene = makeDay(date(2026, 6, 22), type: .fuerza, in: db.context)
        let deOtraSemana = makeExercise("Press banca", on: semanaQueViene, order: 0,
                                        sets: [(100, 10)], in: db.context)

        let total = WeeklyVolume.tonnage(for: miercoles, among: [deEstaSemana, deOtraSemana])
        #expect(total == 800, "Los 1000 kg de la semana que viene no entran")
    }

    @Test("U-22 · ⚠️ Cuenta las series que todavía no confirmaste")
    func tonnageCountsUnconfirmedSets() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // Dos series: una hecha, otra no. La segunda tiene datos porque el **prellenado** se
        // los puso (ver I-17: al llegar a la serie, las reps van al objetivo y el peso al
        // último usado).
        let press = makeExercise("Press banca", on: day, order: 0,
                                 sets: [(80, 8), (80, 8)], in: db.context)
        press.orderedSets[0].isDone = true
        press.orderedSets[1].isDone = false

        // ⚠️ `tonnage` no mira `isDone`: suma las dos. O sea que abrir la sesión guiada —sin
        // levantar nada— ya le agrega 640 kg a la semana.
        let total = WeeklyVolume.tonnage(for: miercoles, among: [press])
        #expect(total == 1280, "⚠️ Suma la serie sin confirmar")

        // Es el mismo defecto que el bug 14 (`loggedSetsCount` en el espejo), pero acá pega
        // en un número que **queda**: el tonelaje de la semana en la tarjeta de tendencia.
        // Si abrís la sesión y no entrenás, la semana igual muestra volumen.
        //
        // Y es asimétrico con los km, que **sí** filtran por `isCompleted` (ver U-24): un
        // rodaje no cuenta hasta que lo marcás como hecho, pero una serie cuenta apenas la
        // app le pone un número encima.
    }

    @Test("U-22 · Una serie con peso 0 suma 0, no rompe")
    func aZeroWeightSetAddsNothing() {
        let db = TestDB()
        let day = makeDay(miercoles, type: .fuerza, in: db.context)

        // Peso 0 con reps es un dato válido (una barra vacía, una progresión desde cero).
        // Entra al cálculo —no lo descarta el `guard`, porque 0 no es `nil`— y aporta 0.
        let press = makeExercise("Press banca", on: day, order: 0,
                                 sets: [(0, 10), (80, 10)], in: db.context)

        #expect(WeeklyVolume.tonnage(for: miercoles, among: [press]) == 800)
    }
}
