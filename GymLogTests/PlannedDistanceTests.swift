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
}
