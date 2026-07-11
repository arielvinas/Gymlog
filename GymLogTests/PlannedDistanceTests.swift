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

    // MARK: - U-04

    @Test(
        "U-04 · La unidad se reconoce sin importar la caja",
        arguments: [
            "FONDO 10 KM",
            "Fondo 10 Km",
            "fondo 10 kM",
            "Fondo 10 km",
        ]
    )
    func unitIsCaseInsensitive(text: String) {
        // El plan lo escribe el usuario a mano: nadie garantiza que "km" venga en
        // minúscula. Si el regex fuese sensible a la caja, un "10 KM" contaría 0.
        #expect(PlannedDistance.parse(text) == 10)
    }

    // MARK: - U-05

    // ⚠️ Estos tests **documentan limitaciones**, no las aprueban.
    //
    // `parse` toma el **primer** match de `title + " " + detail` y se detiene ahí.
    // Mientras el título lleve la distancia y el detalle sea el ritmo, funciona. Pero
    // basta con que aparezca un número con "km" antes del que importa para que lea el
    // equivocado — y no hay forma de notarlo salvo mirando el total de la semana.

    @Test("U-05 · Toma el primer km del texto, aunque no sea el que importa")
    func takesTheFirstMatchEvenIfWrong() {
        // El caso que funciona: la distancia va primero, el ritmo después.
        #expect(PlannedDistance.parse("Rodaje 8 km a 5:30 min/km") == 8)

        // El caso que NO: si el detalle menciona otra cosa medida en km antes de la
        // distancia real, se lleva ese número. Acá el día es de 10 km, pero cuenta 5.
        #expect(
            PlannedDistance.parse("Rodaje 5 km/h de viento, 10 km totales") == 5,
            "Comportamiento actual: se queda con el primer número, no con la distancia"
        )
    }

    @Test("U-05 · El separador de miles se lee como decimal")
    func thousandsSeparatorIsMisreadAsDecimal() {
        // El regex acepta punto Y coma como separador decimal, así que no puede
        // distinguir "1.000 km" (mil, formato es-AR) de "1.000" (uno coma cero).
        // Gana la lectura decimal. En la práctica no molesta —nadie planifica 1000 km
        // en un día— pero si algún día se formatean km con separador de miles, esto
        // los rompe.
        #expect(PlannedDistance.parse("Fondo 1.000 km") == 1.0)
    }
}
