//
//  SmokeUITests.swift
//  GymLogUITests
//
//  Prueba de humo: la app arranca en el simulador y muestra su UI.
//  Los recorridos E2E de verdad están enumerados en TESTING.md (E2E-01..E2E-10).
//

import XCTest

final class SmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLaAppArranca() {
        let app = XCUIApplication()
        app.launch()

        // La app arranca en un TabView; si aparece cualquier tab, el arranque fue bien.
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 10),
            "La app no llegó a mostrar la barra de tabs"
        )
    }
}
