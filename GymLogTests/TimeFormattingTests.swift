//
//  TimeFormattingTests.swift
//  GymLogTests
//
//  Las dos etiquetas de duración de la app. Son cortas y sin dependencias, pero
//  se leen en cada serie: `restLabel` es el descanso que muestra la rutina
//  ("1:30 min") y `countdownLabel` es la cuenta regresiva del reloj ("0:05").
//
//  Backlog: TESTING.md · U-06..U-08
//

import Foundation
import Testing
@testable import Maraton

@Suite("Formato de duraciones")
struct TimeFormattingTests {

    // MARK: - U-06

    // `restLabel` tiene tres formas según el valor, y la regla es no mostrar ceros
    // que no aportan: menos de un minuto va en segundos, un minuto justo va sin
    // segundos, y el resto va en `m:ss`.

    @Test(
        "U-06 · El descanso se muestra en la unidad que corresponde",
        arguments: [
            // Menos de un minuto: segundos pelados. Es el descanso de los circuitos.
            (30, "30 s"),
            (45, "45 s"),
            (59, "59 s"),
            // Minutos justos: sin `:00` colgando.
            (60, "1 min"),
            (120, "2 min"),
            (180, "3 min"),
            // Minutos con segundos: el segundo va con cero a la izquierda, si no
            // "1:5 min" se leería como uno coma cinco.
            (90, "1:30 min"),
            (75, "1:15 min"),
            (65, "1:05 min"),
            (150, "2:30 min"),
        ]
    )
    func restLabelUsesTheRightUnit(seconds: Int, expected: String) {
        #expect(seconds.restLabel == expected)
    }

    @Test("U-06 · Cero segundos es un valor válido, no un vacío")
    func zeroIsAValidRest() {
        // No es alcanzable como descanso real (ver I-06: las plantillas usan 30–120 s y
        // `adjustRest` recorta a 15 como mínimo), pero la función igual tiene que dar algo
        // legible en vez de romperse o devolver "".
        #expect(0.restLabel == "0 s")
    }

    @Test("U-06 · Una hora se muestra en minutos, no en horas")
    func anHourIsShownInMinutes() {
        // Límite conocido: no hay tramo de horas. Un descanso de una hora se lee "60 min".
        // No molesta —nadie descansa una hora entre series— pero queda escrito para que no
        // sorprenda si alguna vez se reusa la función para otra cosa (una duración de
        // sesión, por ejemplo, donde sí importaría).
        #expect(3600.restLabel == "60 min")
        #expect(3661.restLabel == "61:01 min")
    }
}
