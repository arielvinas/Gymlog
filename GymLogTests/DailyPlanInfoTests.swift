//
//  DailyPlanInfoTests.swift
//  GymLogTests
//
//  Lo que la app te dice del día: el estado (Pendiente / Completado / Descanso), el objetivo en
//  una línea y el titular de la tarjeta de hoy. Es la primera pantalla que ves, así que si acá
//  algo miente, miente todos los días.
//
//  Backlog: TESTING.md · U-40
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Día · estado y objetivo")
struct DailyPlanInfoTests {

    // MARK: - U-40 · dailyStatus

    @Test("U-40 · Un día de entrenamiento está pendiente hasta que lo completás")
    func aTrainingDayIsPendingUntilCompleted() {
        let db = TestDB()

        let pendiente = makeDay(date(2026, 6, 17), type: .fondo, in: db.context)
        let hecho = makeDay(date(2026, 6, 18), type: .fondo, isCompleted: true, in: db.context)

        #expect(pendiente.dailyStatus == .pending)
        #expect(hecho.dailyStatus == .completed)
    }

    @Test("U-40 · ⚠️ Un día de descanso marcado como completado igual dice 'Descanso'")
    func aRestDayStaysRestEvenIfMarkedCompleted() {
        let db = TestDB()

        let descanso = makeDay(date(2026, 6, 17), type: .descanso, in: db.context)
        let descansoMarcado = makeDay(
            date(2026, 6, 18), type: .descanso, isCompleted: true, in: db.context
        )

        // El `if type == .descanso` corta **antes** de mirar `isCompleted`, así que el flag queda
        // ignorado. No es un bug: descansar no se "completa", y una tilde verde en un día de
        // descanso sería ruido. Pero el dato queda guardado en la base sin que nada lo muestre —si
        // mañana alguien filtra por `isCompleted` para contar días activos, se va a llevar los
        // descansos marcados de regalo.
        #expect(descanso.dailyStatus == .rest)
        #expect(descansoMarcado.dailyStatus == .rest)
        #expect(descansoMarcado.isCompleted, "El flag sigue ahí, solo que nadie lo lee")
    }

    @Test("U-40 · Todos los tipos de entrenamiento pasan por pendiente/completado")
    func everyTrainingTypeUsesPendingAndCompleted() {
        let db = TestDB()

        for (i, tipo) in [WorkoutType.fuerza, .rodaje, .calidad, .fondo, .carrera].enumerated() {
            let dia = makeDay(date(2026, 6, 1 + i), type: tipo, in: db.context)
            #expect(dia.dailyStatus == .pending, "\(tipo.displayName) sin completar")

            dia.isCompleted = true
            #expect(dia.dailyStatus == .completed, "\(tipo.displayName) completado")
        }
    }

    // MARK: - U-40 · objective

    @Test("U-40 · El objetivo de una corrida junta título y detalle")
    func theObjectiveOfARunJoinsTitleAndDetail() {
        let db = TestDB()

        let dia = makeDay(
            date(2026, 6, 17),
            type: .fondo,
            title: "Fondo largo 12 km",
            detail: "Z2 conversacional",
            in: db.context
        )

        #expect(dia.objective == "Fondo largo 12 km · Z2 conversacional")
    }

    @Test("U-40 · Con el detalle vacío, el objetivo es solo el título — sin el separador colgando")
    func anEmptyDetailDropsTheSeparator() {
        let db = TestDB()

        let dia = makeDay(
            date(2026, 6, 17), type: .rodaje, title: "Rodaje 6 km", detail: "", in: db.context
        )

        // Si no chequeara `detail.isEmpty`, saldría "Rodaje 6 km · " con el punto medio colgando.
        #expect(dia.objective == "Rodaje 6 km")
    }

    @Test("U-40 · El descanso y la fuerza tienen un objetivo fijo: no leen el título")
    func restAndStrengthHaveAFixedObjective() {
        let db = TestDB()

        let descanso = makeDay(
            date(2026, 6, 17), type: .descanso, title: "Descanso", detail: "Caminata suave",
            in: db.context
        )
        let fuerza = makeDay(
            date(2026, 6, 18), type: .fuerza, title: "Fuerza A", detail: "Tren superior",
            in: db.context
        )

        // Los dos tienen su `case` propio, así que el `detail` que escribas **no se muestra** acá.
        // En fuerza tiene sentido (el detalle real son los ejercicios), pero en descanso significa
        // que una nota como "Caminata suave" queda invisible en la tarjeta de hoy.
        #expect(descanso.objective == "Descansá y recuperá")
        #expect(fuerza.objective == "Completar sesión de gimnasio")
    }

    // MARK: - U-40 · todayHeadline

    @Test("U-40 · El titular sale del tipo de día")
    func theHeadlineComesFromTheType() {
        let db = TestDB()

        let descanso = makeDay(date(2026, 6, 17), type: .descanso, in: db.context)
        let fondo = makeDay(date(2026, 6, 18), type: .fondo, in: db.context)

        #expect(descanso.todayHeadline == "Hoy es día de descanso")
        #expect(fondo.todayHeadline == "Hoy toca Fondo")
    }

    // MARK: - U-40 · DailyPlanInfo.workout

    @Test("U-40 · Encuentra el día por fecha, sin importar la hora")
    func itFindsTheDayRegardlessOfTheTime() throws {
        let db = TestDB()

        let dias = [
            makeDay(date(2026, 6, 16), type: .rodaje, title: "Rodaje", in: db.context),
            makeDay(date(2026, 6, 17), type: .fondo, title: "Fondo", in: db.context),
            makeDay(date(2026, 6, 18), type: .descanso, title: "Descanso", in: db.context)
        ]

        // `isDate(inSameDayAs:)` compara el día del calendario, no el instante: da igual que el
        // día esté guardado a las 00:00 y lo busques a las 23:00.
        let cal = PlanConstants.calendar
        let alaNoche = try #require(
            cal.date(bySettingHour: 23, minute: 30, second: 0, of: date(2026, 6, 17))
        )

        let encontrado = try #require(DailyPlanInfo.workout(in: dias, on: alaNoche))
        #expect(encontrado.title == "Fondo")
    }

    @Test("U-40 · Un día fuera del plan devuelve nil")
    func aDayOutsideThePlanReturnsNil() {
        let db = TestDB()

        let dias = [makeDay(date(2026, 6, 17), type: .fondo, in: db.context)]

        #expect(DailyPlanInfo.workout(in: dias, on: date(2026, 6, 18)) == nil)
        #expect(DailyPlanInfo.workout(in: [], on: date(2026, 6, 17)) == nil)
    }

    @Test("U-40 · Con días duplicados devuelve el primero de la lista")
    func withDuplicateDaysItReturnsTheFirstOne() throws {
        let db = TestDB()

        // Los duplicados no deberían existir —hubo un fix entero para eso— pero si vuelven a
        // aparecer por una sincronización, `first` elige por posición en el array, no por
        // "el más completo". Es arbitrario, y queda dicho.
        let dias = [
            makeDay(date(2026, 6, 17), type: .fondo, title: "Original", in: db.context),
            makeDay(date(2026, 6, 17), type: .fondo, title: "Duplicado", in: db.context)
        ]

        let encontrado = try #require(DailyPlanInfo.workout(in: dias, on: date(2026, 6, 17)))
        #expect(encontrado.title == "Original")
    }
}
