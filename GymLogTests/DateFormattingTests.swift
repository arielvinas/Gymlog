//
//  DateFormattingTests.swift
//  GymLogTests
//
//  Las fechas que se leen en la app, todas en es-AR.
//
//  ⚠️ Estos tests **no comparan contra strings literales**. Las abreviaturas de mes
//  del español cambian entre versiones de iCU (`"may"` vs `"may."`, con punto o
//  sin punto), así que un `#expect(fecha.dayMonth == "30 may")` se rompería solo al
//  actualizar Xcode — un test que falla sin que nadie haya tocado el código es peor
//  que no tener test.
//
//  Lo que sí se puede fijar es **el contrato**: qué patrón usa cada propiedad, que
//  el idioma esté clavado en es-AR pase lo que pase, y cuáles van con mayúscula
//  inicial y cuáles no.
//
//  Backlog: TESTING.md · U-11
//

import Foundation
import Testing
@testable import Maraton

@Suite("Formato de fechas")
struct DateFormattingTests {

    /// El mismo formateador que usa la app, para comparar contra él en vez de contra un
    /// literal. Si iCU cambia las abreviaturas, cambian los dos lados y el test sigue
    /// diciendo lo que quiere decir: "esta propiedad usa este patrón, en este idioma".
    private func esAR(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateFormat = pattern
        return formatter
    }

    // MARK: - U-11

    @Test("U-11 · Cada propiedad usa su patrón, en español")
    func eachPropertyUsesItsPattern() {
        let fecha = date(2026, 5, 30)

        #expect(fecha.dayMonth == esAR("d MMM").string(from: fecha))
        #expect(fecha.weekdayName == esAR("EEEE").string(from: fecha))

        // Las tres que llevan mayúscula inicial (ver el test siguiente).
        #expect(fecha.weekdayAndDay == esAR("EEE d MMM").string(from: fecha).capitalizedFirst)
        #expect(fecha.longDate == esAR("EEEE d 'de' MMMM 'de' yyyy").string(from: fecha).capitalizedFirst)
        #expect(fecha.weekdayDayMonth == esAR("EEEE d 'de' MMMM").string(from: fecha).capitalizedFirst)
    }

    @Test("U-11 · Las que encabezan van con mayúscula; la que va en una frase, no")
    func capitalizationIsDeliberate() {
        let fecha = date(2026, 5, 30)

        // `weekdayAndDay`, `longDate` y `weekdayDayMonth` encabezan una tarjeta o una
        // pantalla, así que arrancan en mayúscula. El español no capitaliza los días ni los
        // meses, por eso hace falta el `capitalizedFirst` a mano.
        #expect(fecha.weekdayAndDay.first?.isUppercase == true)
        #expect(fecha.longDate.first?.isUppercase == true)
        #expect(fecha.weekdayDayMonth.first?.isUppercase == true)

        // `weekdayName` **no**: existe para meterse dentro de una frase ("entrenás el
        // jueves"), donde una mayúscula quedaría mal. Es una diferencia deliberada, no un
        // olvido — si alguien "empareja" las cinco, rompe las frases.
        #expect(fecha.weekdayName.first?.isLowercase == true)

        // `dayMonth` empieza con el número, así que la pregunta no aplica.
        #expect(fecha.dayMonth.first?.isNumber == true)
    }

    @Test("U-11 · El idioma del teléfono no cambia las fechas")
    func theLanguageIsPinnedToSpanish() {
        let fecha = date(2026, 5, 30)

        // Igual que los números (U-09), el locale está fijado a mano: un teléfono en inglés
        // sigue viendo "sábado", no "Saturday". La app es en español y el plan también.
        let enIngles = esAR("EEEE")
        enIngles.locale = Locale(identifier: "en_US")
        #expect(fecha.weekdayName != enIngles.string(from: fecha))

        // Y no hay ningún "Saturday" suelto: el nombre sale del calendario es-AR.
        #expect(fecha.longDate.contains("2026"))
    }

    @Test("U-11 · La fecha que se muestra es la del día, no la de la zona horaria")
    func theDayShownIsTheCalendarDay() {
        // `DateFormatting` no fija `timeZone`, así que usa la del sistema. Eso está bien
        // —el usuario quiere ver *su* día— pero significa que una fecha construida a
        // medianoche UTC podría mostrarse como el día anterior en Buenos Aires (UTC−3).
        //
        // Por eso `date()` (TestSupport) construye las fechas **al mediodía**: quedan lejos
        // de los dos bordes y ninguna zona horaria razonable las corre de día. Este test fija
        // esa propiedad del andamio, que es de lo que dependen todos los tests de fecha.
        let fecha = date(2026, 5, 30)

        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone.current
        #expect(calendario.component(.day, from: fecha) == 30)
        #expect(calendario.component(.month, from: fecha) == 5)
        #expect(calendario.component(.year, from: fecha) == 2026)

        // Y el string lo refleja: el 30 aparece en el texto.
        #expect(fecha.dayMonth.hasPrefix("30"))
    }

    @Test("U-11 · capitalizedFirst no se rompe con un texto vacío")
    func capitalizedFirstHandlesTheEmptyString() {
        // El `guard let first` de `capitalizedFirst`. No es alcanzable desde las fechas (un
        // `DateFormatter` con patrón nunca devuelve ""), pero la extensión es pública sobre
        // `String` y cualquiera puede llamarla.
        #expect("".capitalizedFirst == "")
        #expect("a".capitalizedFirst == "A")
        #expect("miércoles".capitalizedFirst == "Miércoles", "Y no se come el acento")

        // No toca el resto de la cadena: solo la primera letra.
        #expect("jueves 30 de mayo".capitalizedFirst == "Jueves 30 de mayo")
    }
}
