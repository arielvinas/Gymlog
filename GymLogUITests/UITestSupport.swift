//
//  UITestSupport.swift
//  GymLogUITests
//
//  Andamio de los E2E. Lo único que hace es lanzar la app con `-uitesting`, que la obliga a
//  arrancar con el contenedor **y** los flags de sembrado en memoria (ver `AppData.isUITesting`).
//
//  Sin eso, el primer test siembra el plan y deja el flag puesto en el simulador, y el segundo
//  arranca con un estado distinto: los E2E salen flaky por una razón que no tiene nada que ver con
//  lo que están probando.
//

import XCTest

extension XCUIApplication {

    /// Lanza la app sobre una base efímera, recién sembrada.
    @discardableResult
    static func launchForUITesting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitesting"]
        app.launch()
        return app
    }
}

extension XCTestCase {

    /// Espera a que el elemento exista, o falla con un mensaje que se entiende sin abrir Xcode.
    @discardableResult
    func esperar(
        _ element: XCUIElement,
        _ descripción: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let apareció = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(apareció, "No apareció: \(descripción)", file: file, line: line)
        return apareció
    }

    /// Scrollea hasta que el elemento aparezca y se pueda tocar.
    ///
    /// Hace falta porque las `List` de SwiftUI son **perezosas**: una fila que todavía no se
    /// dibujó no está en el árbol de accesibilidad, así que `waitForExistence` no la encuentra
    /// nunca por más que uno espere. La lista del plan tiene decenas de días.
    @discardableResult
    func scrollHasta(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ descripción: String,
        intentos: Int = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        for _ in 0..<intentos {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        XCTAssertTrue(
            element.exists && element.isHittable,
            "No apareció ni scrolleando: \(descripción)",
            file: file, line: line
        )
        return false
    }
}
