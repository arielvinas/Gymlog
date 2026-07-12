//
//  NumberFormattingTests.swift
//  GymLogTests
//
//  Los números que el usuario ve: kilómetros, kilos y ritmo. Están en es-AR,
//  así que el separador decimal es la **coma** — no es un detalle cosmético, es
//  la diferencia entre leer "12,5 km" y "12.5 km" en un país donde el punto
//  separa los miles.
//
//  Backlog: TESTING.md · U-09..U-10
//

import Foundation
import Testing
@testable import Maraton

@Suite("Formato de números")
struct NumberFormattingTests {

    // MARK: - U-09

    @Test(
        "U-09 · Los kilómetros van con coma decimal y sin decimales de más",
        arguments: [
            // El caso que da nombre a todo: coma, no punto.
            (12.5, "12,5"),
            (5.5, "5,5"),
            // Un entero no arrastra un ",0" al pedo.
            (12.0, "12"),
            (5.0, "5"),
            // Cero es un valor, no un vacío.
            (0.0, "0"),
        ]
    )
    func kilometresUseACommaAndNoTrailingZero(value: Double, expected: String) {
        #expect(value.formattedKm == expected)
    }

    @Test(
        "U-09 · Se redondea a un decimal",
        arguments: [
            (12.34, "12,3"),
            (12.37, "12,4"),
            // Un decimal alcanza para km y para kilos: nadie carga 12,34 km ni 42,37 kg.
            (42.51, "42,5"),
        ]
    )
    func roundsToOneDecimal(value: Double, expected: String) {
        #expect(value.formattedKm == expected)
    }

    @Test("U-09 · Los kilos usan exactamente el mismo formato")
    func kilogramsShareTheFormat() {
        // `formattedKg` es literalmente `formattedKm`. Está bien —las dos magnitudes se leen
        // igual— pero conviene saberlo: cambiar una cambia la otra.
        #expect(42.5.formattedKg == "42,5")
        #expect(42.5.formattedKg == 42.5.formattedKm)
        #expect(80.0.formattedKg == "80")
    }

    @Test("U-09 · Los miles se separan con punto")
    func thousandsUseADot() {
        // `numberStyle = .decimal` trae el separador de miles activado. Importa de verdad:
        // el resumen de la sesión en el reloj muestra el volumen total en kg, y una sesión
        // de fuerza pasa los mil sin esfuerzo (5 series × 80 kg × 8 reps ya son 3.200).
        #expect(3200.0.formattedKg == "3.200")
        #expect(12500.0.formattedKg == "12.500")

        // ⚠️ Ojo con la simetría rota: este "1.000" **no** vuelve a entrar por
        // `PlannedDistance.parse`, que lo leería como 1,0 (ver U-05). Formatear y volver a
        // parsear no es una ida y vuelta segura. Hoy no hay ninguna ruta que lo haga.
        #expect(1000.0.formattedKm == "1.000")
    }

    @Test("U-09 · Un negativo se formatea sin romperse")
    func negativesAreFormatted() {
        // No es alcanzable (no hay km ni kilos negativos), pero a diferencia de
        // `countdownLabel` (ver U-08) acá el negativo sale bien igual.
        #expect((-5.5).formattedKm == "-5,5")
    }

    @Test("U-09 · El idioma del teléfono no cambia el separador")
    func theFormatIsPinnedToArgentina() {
        // El formateador fija `Locale(identifier: "es_AR")` a mano, en vez de usar el del
        // sistema. O sea: un teléfono en inglés **igual** ve "12,5". Es deliberado —la app
        // es en español y el plan se escribió con comas— pero queda escrito para que no
        // sorprenda: no es un bug de localización, es una decisión.
        #expect(12.5.formattedKm == "12,5")
        #expect(!12.5.formattedKm.contains("."))
    }
}
