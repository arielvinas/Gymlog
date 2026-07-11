//
//  PlannedDistanceTests.swift
//  GymLogTests
//
//  `PlannedDistance.parse` saca los kilómetros del texto libre del plan
//  ("Fondo largo 12 km" → 12). De acá sale `WorkoutDay.plannedKm`, que alimenta
//  el volumen semanal y el reporte: si el parseo se equivoca, los números que ve
//  el usuario se equivocan, en silencio.
//
//  Backlog: TESTING.md · U-01..U-05
//

import Foundation
import Testing
@testable import Maraton

@Suite("Distancia planificada")
struct PlannedDistanceTests {

    // MARK: - U-01

    @Test(
        "U-01 · Un número seguido de km",
        arguments: [
            ("Fondo largo 12 km", 12.0),
            ("Rodaje suave 5 km", 5.0),
            // Coma decimal: es el separador de es-AR, el que el usuario escribe.
            ("Fondo 12,5 km", 12.5),
            // Punto decimal: por si el texto viene de otro lado.
            ("Fondo 12.5 km", 12.5),
            // Sin espacio entre el número y la unidad.
            ("Fondo 10km", 10.0),
            // Cero es un valor válido, no un "sin dato".
            ("Prueba 0 km", 0.0),
        ]
    )
    func parsesASingleDistance(text: String, expected: Double) {
        #expect(PlannedDistance.parse(text) == expected)
    }

    // MARK: - U-02

    // Un rango ("13-14 km") es una banda de objetivo, no dos números: el plan la
    // resuelve tomando el **promedio**. Esa decisión es la que hace que los km
    // planificados de la semana no dependan de si el día se escribió con rango o
    // con un número redondo.

    @Test(
        "U-02 · Un rango se promedia",
        arguments: [
            ("Fondo 13-14 km", 13.5),
            ("Fondo 10-12 km", 11.0),
            // Guion largo (en-dash): es el que mete la sustitución automática de
            // iOS al tipear "13-14" en el campo de detalle.
            ("Fondo 13–14 km", 13.5),
            // Con espacios alrededor del guion.
            ("Fondo 13 - 14 km", 13.5),
            // Rango con decimales.
            ("Fondo 12,5-13,5 km", 13.0),
        ]
    )
    func averagesARange(text: String, expected: Double) {
        #expect(PlannedDistance.parse(text) == expected)
    }

    @Test("U-02 · Un rango invertido igual promedia")
    func invertedRangeStillAverages() {
        // El parser no valida el orden. "14-13" da lo mismo que "13-14", que es lo
        // razonable: el promedio es simétrico y no hay razón para tratarlo como error.
        #expect(PlannedDistance.parse("Fondo 14-13 km") == 13.5)
    }

    // MARK: - U-03

    // El otro lado del contrato: **sin km, `nil`**. Es lo que evita que un día de
    // fuerza o de descanso aporte kilómetros fantasma al volumen de la semana.
    // Ojo con los números que NO son distancia (series, minutos, metros): el parser
    // solo debe morder los que llevan "km" pegado.

    @Test(
        "U-03 · Un texto sin km no aporta distancia",
        arguments: [
            // Días que no son de correr.
            "Descanso",
            "Descanso / movilidad",
            "Fuerza A",
            "Fuerza B · Espalda + tríceps + core",
            // Números que no son kilómetros.
            "Series 8x400 m",
            "Calidad · 2×10' tempo",
            "Trote suave 15 min",
            "Movilidad 10'",
            // Texto vacío y unidad suelta.
            "",
            "km",
            "Fondo km",
        ]
    )
    func returnsNilWithoutKilometres(text: String) {
        #expect(PlannedDistance.parse(text) == nil)
    }

    @Test("U-03 · Un día de fuerza del plan no suma km")
    func aStrengthDayContributesNoDistance() {
        // Lo mismo, pero entrando por donde entra de verdad: `WorkoutDay.plannedKm`
        // concatena título + detalle, así que el test cubre la ruta real.
        let fuerza = makeDay(
            date(2026, 7, 1),
            type: .fuerza,
            title: "Fuerza A",
            detail: "Empuje + pierna + core"
        )
        #expect(fuerza.plannedKm == nil)

        let descanso = makeDay(
            date(2026, 7, 2),
            type: .descanso,
            title: "Descanso",
            detail: "Movilidad 10'"
        )
        #expect(descanso.plannedKm == nil)
    }
}
