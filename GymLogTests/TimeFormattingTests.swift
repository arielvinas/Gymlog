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

    // MARK: - U-07

    // `countdownLabel` es el número grande del descanso: el que mirás en la muñeca mientras
    // esperás. A diferencia de `restLabel`, **siempre** tiene la misma forma (`m:ss`), porque
    // es un número que cambia cada segundo: si alternara entre "1:30" y "45 s" saltaría de
    // ancho a mitad de la cuenta.

    @Test(
        "U-07 · La cuenta regresiva siempre tiene la forma m:ss",
        arguments: [
            (90, "1:30"),
            (60, "1:00"),
            (59, "0:59"),
            // Con un solo dígito el cero a la izquierda es lo que evita que "0:5" se lea
            // como cinco décimas o como cinco minutos.
            (5, "0:05"),
            (1, "0:01"),
            // El final de la cuenta. No es un caso raro: es el que se ve justo antes de
            // entrar en tiempo extra.
            (0, "0:00"),
            // Descansos largos, y los minutos altos del tiempo extra.
            (150, "2:30"),
            (600, "10:00"),
        ]
    )
    func countdownAlwaysUsesMinutesAndSeconds(seconds: Int, expected: String) {
        #expect(seconds.countdownLabel == expected)
    }

    @Test("U-07 · El tiempo extra usa la misma etiqueta, con un + adelante")
    func overtimeReusesTheSameLabel() {
        // Las tres vistas (reloj, iPhone y espejo) hacen `"+\(segundos.countdownLabel)"`.
        // O sea que esta misma función formatea las dos mitades del descanso: la que baja y
        // la que sube. Por eso no puede tener un caso especial para el 0.
        #expect("+\(35.countdownLabel)" == "+0:35")
        #expect("+\(90.countdownLabel)" == "+1:30")
    }

    @Test("U-07 · Tampoco acá hay tramo de horas")
    func noHoursHereEither() {
        // Mismo límite que `restLabel`. Acá **sí** es alcanzable: el tiempo extra cuenta
        // hacia arriba sin techo (ver I-05), así que una sesión abandonada con la pantalla
        // abierta llega a "60:00" y sigue. No rompe nada —el número se lee igual— pero el
        // ancho del texto crece y la vista no lo espera.
        #expect(3600.countdownLabel == "60:00")
        #expect(3665.countdownLabel == "61:05")
    }
}
