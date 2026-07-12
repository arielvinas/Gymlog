//
//  GuidedSessionE2ETests.swift
//  GymLogUITests
//
//  E2E-02 y E2E-03: navegar el plan y hacer el **recorrido principal** — la sesión guiada.
//
//  E2E-03 es el que más importa de los diez: es lo que uno hace con el teléfono apoyado en el
//  banco, entre serie y serie. Si esto se rompe, la app no sirve para lo único que hace.
//
//  Backlog: TESTING.md · E2E-02, E2E-03
//

import XCTest

final class GuidedSessionE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Deja la app parada en la rutina de un día de fuerza **con ejercicios sembrados**.
    ///
    /// ⚠️ Ojo con cuál se elige: `StrengthSeed` solo siembra la rutina en los días **del 9/6 en
    /// adelante** (ver I-29). Los "Fuerza A" de mayo existen en el plan pero están **vacíos**, así
    /// que la pantalla muestra el estado vacío y no hay ninguna sesión que empezar. Se usa el del
    /// 16/6, que se identifica sin ambigüedad por su detalle.
    private func abrirRutinaDeFuerza(_ app: XCUIApplication) {
        app.tabBars.buttons["Plan"].tap()

        let fila = app.staticTexts["Día 1 · sin saltos"]
        scrollHasta(fila, in: app, "el día de fuerza del 16/6")
        fila.tap()

        let rutina = app.staticTexts["Rutina de gimnasio"]
        esperar(rutina, "el acceso a la rutina de gimnasio")
        rutina.tap()
    }

    // MARK: - E2E-02

    func testE2E02_NavegarElPlanYEntrarAUnDia() {
        let app = XCUIApplication.launchForUITesting()

        app.tabBars.buttons["Plan"].tap()

        // El plan sembrado se ve, agrupado por semanas.
        esperar(app.staticTexts["Fondo largo 12 km"], "un día de fondo", timeout: 15)

        // Entrar a un día y volver: la navegación básica del plan.
        app.staticTexts["Fondo largo 12 km"].firstMatch.tap()
        esperar(app.staticTexts["Rutina de gimnasio"].exists
                ? app.staticTexts["Rutina de gimnasio"]
                : app.navigationBars.firstMatch,
                "el detalle del día")

        // Y las otras tabs siguen respondiendo.
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Progreso"].tap()
        esperar(app.navigationBars.firstMatch, "la sección Progreso")
    }

    // MARK: - E2E-03 · El recorrido principal

    func testE2E03_SesionGuiadaCompletarSerieDescansarYAvanzar() {
        let app = XCUIApplication.launchForUITesting()
        abrirRutinaDeFuerza(app)

        let empezar = app.buttons["Empezar sesión guiada"]
        esperar(empezar, "el botón de empezar la sesión guiada")
        empezar.tap()

        // Estamos en la primera serie del primer ejercicio.
        let completar = app.buttons["Completar serie"]
        esperar(completar, "el botón de completar la serie", timeout: 15)
        XCTAssertTrue(
            app.staticTexts["Serie 1 de 3"].exists,
            "La sesión no arrancó en la primera serie"
        )

        // "Hecho": marca la serie y entra en descanso.
        completar.tap()

        // El descanso ofrece saltearlo. Es la prueba de que el engine pasó a `.resting`: si no
        // hubiera entrado, seguiría mostrando "Completar serie".
        let saltear = app.buttons["Saltear descanso"]
        esperar(saltear, "el botón de saltear el descanso")

        // Y se puede ajustar: los ±15 s del descanso en curso.
        XCTAssertTrue(app.buttons["15 s"].firstMatch.exists, "Faltan los ajustes de ±15 s")

        saltear.tap()

        // Vuelve a la carga de datos, ya en la serie siguiente.
        esperar(app.buttons["Completar serie"], "la vuelta a cargar la serie")
        XCTAssertTrue(
            app.staticTexts["Serie 2 de 3"].waitForExistence(timeout: 5),
            "No avanzó a la serie 2"
        )
    }

    func testE2E03_SePuedeVolverALaSerieAnterior() {
        let app = XCUIApplication.launchForUITesting()
        abrirRutinaDeFuerza(app)

        app.buttons["Empezar sesión guiada"].tap()
        esperar(app.buttons["Completar serie"], "la primera serie", timeout: 15)

        // En la primera serie no hay a dónde volver: el botón está, pero deshabilitado.
        let anterior = app.buttons["Anterior"]
        XCTAssertTrue(anterior.exists)
        XCTAssertFalse(anterior.isEnabled, "En la serie 1 no debería poder retrocederse")

        // Avanzar, saltear el descanso, y volver.
        app.buttons["Completar serie"].tap()
        app.buttons["Saltear descanso"].tap()
        esperar(app.staticTexts["Serie 2 de 3"], "la serie 2")

        XCTAssertTrue(anterior.isEnabled, "Ahora sí se puede volver")
        anterior.tap()

        esperar(app.staticTexts["Serie 1 de 3"], "la vuelta a la serie 1")
    }
}
