//
//  PlanE2ETests.swift
//  GymLogUITests
//
//  E2E-01: el primer arranque siembra el plan.
//
//  Backlog: TESTING.md · E2E-01
//

import XCTest

final class PlanE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testE2E01_ElPrimerArranqueSiembraElPlan() {
        let app = XCUIApplication.launchForUITesting()

        // Las tres secciones están.
        esperar(app.tabBars.firstMatch, "la barra de tabs")
        XCTAssertTrue(app.tabBars.buttons["Plan"].exists, "Falta la tab Plan")
        XCTAssertTrue(app.tabBars.buttons["Progreso"].exists, "Falta la tab Progreso")

        app.tabBars.buttons["Plan"].tap()

        // El plan sembrado tiene que estar a la vista. No se afirma sobre "hoy": el plan es un
        // bloque con fechas fijas (mayo–julio de 2026) y, según cuándo corra el test, hoy puede
        // caer fuera de él. El sembrado, en cambio, siempre deja estos días.
        esperar(app.staticTexts["Fondo largo 12 km"], "un día del plan sembrado", timeout: 15)
    }
}
