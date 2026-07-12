//
//  SessionCompletionE2ETests.swift
//  GymLogUITests
//
//  E2E-04: completar una sesión entera y que el día quede marcado.
//  E2E-05: cambiar el próximo ejercicio a mitad de sesión.
//
//  Backlog: TESTING.md · E2E-04, E2E-05
//

import XCTest

final class SessionCompletionE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Abre la sesión guiada del día de fuerza del 16/6 (posterior al corte del 9/6, así que tiene
    /// la rutina sembrada — ver la nota de E2E-03).
    private func abrirSesionGuiada(_ app: XCUIApplication) {
        app.tabBars.buttons["Plan"].tap()

        let fila = app.staticTexts["Día 1 · sin saltos"]
        scrollHasta(fila, in: app, "el día de fuerza del 16/6")
        fila.tap()

        let rutina = app.staticTexts["Rutina de gimnasio"]
        esperar(rutina, "el acceso a la rutina")
        rutina.tap()

        let empezar = app.buttons["Empezar sesión guiada"]
        esperar(empezar, "el botón de empezar")
        empezar.tap()
    }

    // MARK: - E2E-04

    func testE2E04_CompletarLaSesionEnteraMarcaElDia() {
        let app = XCUIApplication.launchForUITesting()
        abrirSesionGuiada(app)

        let completa = app.staticTexts["¡Sesión completa!"]
        esperar(app.buttons["Completar serie"], "la primera serie", timeout: 15)

        // Machaca el par (cargar → descansar) hasta llegar al final. El tope es un cortafuegos: si
        // la sesión no termina nunca —un bucle en la máquina de estados— el test falla en vez de
        // colgarse hasta el timeout del runner.
        var vueltas = 0
        while !completa.exists && vueltas < 200 {
            vueltas += 1

            if app.buttons["Completar serie"].exists {
                app.buttons["Completar serie"].tap()
            } else if app.buttons["Marcar como hecho"].exists {
                // Los ejercicios sin series (los de tiempo) usan este botón.
                app.buttons["Marcar como hecho"].tap()
            } else if app.buttons["Saltear descanso"].exists {
                app.buttons["Saltear descanso"].tap()
            } else if app.buttons["Empezar serie"].exists {
                // El descanso se pasó de largo: el botón cambia de nombre.
                app.buttons["Empezar serie"].tap()
            } else {
                break
            }
        }

        esperar(completa, "la pantalla de sesión completa", timeout: 15)
        XCTAssertLessThan(vueltas, 200, "La sesión no terminó: ¿la máquina de estados quedó en loop?")

        // El resumen aparece con lo que se cargó.
        XCTAssertTrue(app.staticTexts["Series cargadas"].exists, "Falta el resumen de la sesión")

        app.buttons["Listo"].tap()

        // Y el día quedó marcado. Volvemos a su detalle: la insignia tiene que decir "Completado".
        let volver = app.navigationBars.buttons.firstMatch
        esperar(volver, "el botón de volver")
        volver.tap()

        esperar(app.staticTexts["Completado"], "la insignia de día completado", timeout: 15)
    }

    // MARK: - E2E-05

    func testE2E05_CambiarElProximoEjercicio() {
        let app = XCUIApplication.launchForUITesting()
        abrirSesionGuiada(app)

        esperar(app.buttons["Completar serie"], "la primera serie", timeout: 15)
        XCTAssertTrue(app.staticTexts["Ejercicio 1 de 12"].exists
                      || app.staticTexts.matching(
                          NSPredicate(format: "label BEGINSWITH 'Ejercicio 1 de'")
                      ).firstMatch.exists,
                      "La sesión no arrancó en el primer ejercicio")

        // El botón de la barra: sin la etiqueta de accesibilidad sería un ícono mudo.
        let cambiar = app.buttons["Cambiar ejercicio"]
        esperar(cambiar, "el botón de cambiar ejercicio")
        cambiar.tap()

        // La hoja lista los ejercicios que quedan pendientes.
        esperar(app.navigationBars["Cambiar ejercicio"], "la hoja de cambiar ejercicio")
        XCTAssertTrue(app.staticTexts["¿Qué hacés ahora?"].exists)

        // Elegimos uno de los que vienen más adelante y nos guardamos su nombre.
        let candidato = app.cells.element(boundBy: 1)
        esperar(candidato, "un ejercicio para adelantar")
        let elegido = candidato.staticTexts.firstMatch.label
        candidato.tap()

        // La hoja se cierra y la sesión sigue donde estaba: cambiar el orden no interrumpe la
        // serie en curso.
        esperar(app.buttons["Completar serie"], "la vuelta a la sesión")

        // Terminamos el ejercicio actual. El siguiente tiene que ser el que elegimos.
        var vueltas = 0
        while !app.staticTexts[elegido].exists && vueltas < 30 {
            vueltas += 1
            if app.buttons["Completar serie"].exists {
                app.buttons["Completar serie"].tap()
            } else if app.buttons["Saltear descanso"].exists {
                app.buttons["Saltear descanso"].tap()
            } else if app.buttons["Empezar serie"].exists {
                app.buttons["Empezar serie"].tap()
            } else if app.buttons["Marcar como hecho"].exists {
                app.buttons["Marcar como hecho"].tap()
            } else {
                break
            }
        }

        XCTAssertTrue(
            app.staticTexts[elegido].exists,
            "El ejercicio que adelantamos (\(elegido)) no quedó como el próximo"
        )
    }
}
