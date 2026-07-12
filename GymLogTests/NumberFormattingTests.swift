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

    // MARK: - U-10

    // El ritmo entra en **segundos por km** (un `Double`, porque sale de una división) y sale
    // como `5'30"/km`. Es el número que el corredor mira primero, y el único de la app que
    // no se lee en base 10: 5,5 minutos por km no es "5,5" sino "5'30"".

    @Test(
        "U-10 · El ritmo se muestra en minutos y segundos por km",
        arguments: [
            (330.0, "5'30\"/km"),
            // Segundos justos: el `00` no se puede omitir (a diferencia de `restLabel`),
            // porque un ritmo se lee siempre con los dos campos.
            (300.0, "5'00\"/km"),
            // Cero a la izquierda en los segundos: sin él, "6'5" se leería como seis y medio.
            (365.0, "6'05\"/km"),
            (240.0, "4'00\"/km"),
            (272.0, "4'32\"/km"),
        ]
    )
    func paceIsShownInMinutesAndSecondsPerKm(seconds: Double, expected: String) {
        #expect(seconds.formattedPace == expected)
    }

    @Test(
        "U-10 · Los segundos fraccionarios se redondean, no se truncan",
        arguments: [
            // El ritmo casi nunca es un entero: sale de dividir minutos por km. Redondear
            // (y no truncar) evita que 5'29,6" se muestre como 5'29".
            (330.4, "5'30\"/km"),
            (330.6, "5'31\"/km"),
            (329.5, "5'30\"/km"),
        ]
    )
    func fractionalSecondsAreRounded(seconds: Double, expected: String) {
        #expect(seconds.formattedPace == expected)
    }

    @Test("U-10 · Un ritmo de cero sale legible, y es alcanzable")
    func aZeroPaceIsFormattedAndReachable() throws {
        #expect(0.0.formattedPace == "0'00\"/km")

        // Y no es un caso teórico. `WorkoutDay.paceSecondsPerKm` exige `km > 0` —así que no
        // hay división por cero— pero **no exige que los minutos sean > 0**. Un día con km
        // cargados y duración 0 da ritmo 0.
        let db = TestDB()
        let dia = makeDay(date(2026, 7, 1), type: .rodaje, title: "Rodaje", in: db.context)
        dia.actualKm = 5
        dia.durationMinutes = 0

        let ritmo = try #require(dia.paceSecondsPerKm)
        #expect(ritmo == 0)
        #expect(ritmo.formattedPace == "0'00\"/km", "El detalle del día mostraría esto")

        // Cómo se llega: el formulario de completar sí valida `minutes > 0` para el ritmo que
        // calcula **en vivo**, pero el que se guarda no pasa por ahí. Una importación de
        // HealthKit de una corrida de menos de un minuto también redondea la duración a 0.
        // No rompe nada —"0'00"/km" se lee como un dato faltante— pero es un cero que miente
        // menos que un guion.
    }

    @Test("U-10 · Sin km o sin duración no hay ritmo")
    func noPaceWithoutDistanceOrDuration() {
        let db = TestDB()

        let sinKm = makeDay(date(2026, 7, 1), type: .rodaje, in: db.context)
        sinKm.durationMinutes = 30
        #expect(sinKm.paceSecondsPerKm == nil)

        let sinDuracion = makeDay(date(2026, 7, 2), type: .rodaje, in: db.context)
        sinDuracion.actualKm = 5
        #expect(sinDuracion.paceSecondsPerKm == nil)

        // El `km > 0` es lo que evita la división por cero: sin él, un día con 0 km y
        // duración daría `inf`, y `Int(inf.rounded())` **crashea**.
        let ceroKm = makeDay(date(2026, 7, 3), type: .rodaje, in: db.context)
        ceroKm.actualKm = 0
        ceroKm.durationMinutes = 30
        #expect(ceroKm.paceSecondsPerKm == nil, "Sin este guard, `formattedPace` crashearía")
    }

    @Test("U-10 · Un ritmo muy lento no tiene tramo de horas")
    func aVerySlowPaceHasNoHours() {
        // Mismo límite que `countdownLabel` (U-07): más de 60 minutos por km se lee
        // "61'40"/km" en vez de "1h01'40"". Alcanzable solo caminando muy despacio o con una
        // duración mal cargada. Se lee igual, solo crece el ancho.
        #expect(3700.0.formattedPace == "61'40\"/km")
    }
}
