//
//  RunAndExportE2ETests.swift
//  GymLogUITests
//
//  E2E-08: completar una corrida (km + minutos) y ver el ritmo calculado.
//  E2E-09: generar el reporte PDF.
//  E2E-10: exportar el plan a PDF.
//
//  Backlog: TESTING.md · E2E-08, E2E-09, E2E-10
//

import XCTest

final class RunAndExportE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - E2E-08

    func testE2E08_CompletarUnaCorridaYVerElRitmo() {
        let app = XCUIApplication.launchForUITesting()
        app.tabBars.buttons["Plan"].tap()

        // El fondo del 31/5: 12 km planificados.
        let fila = app.staticTexts["Fondo largo 12 km"]
        scrollHasta(fila, in: app, "el día de fondo")
        fila.tap()

        let completar = app.buttons["Marcar como completado"]
        esperar(completar, "el botón de completar", timeout: 15)
        completar.tap()

        esperar(app.navigationBars["Completar"], "el formulario de completar")

        // 10 km en 50 minutos → 5'00"/km, un número redondo a propósito: si el ritmo se calculara
        // mal, ese valor exacto no aparecería por casualidad.
        //
        // ⚠️ El formato sale de `formattedPace` (`5'00"/km`), no de un "5:00 min/km" inventado. Es
        // el mismo que fijan los unitarios de U-10: el E2E no redefine el contrato, lo consume.
        let km = app.textFields.element(boundBy: 0)
        km.tap()
        km.typeText("10")

        let minutos = app.textFields.element(boundBy: 1)
        minutos.tap()
        minutos.typeText("50")

        // El ritmo se calcula **en vivo**, antes de guardar.
        //
        // ⚠️ `LabeledContent` no expone la etiqueta y el valor por separado: los junta en **un solo**
        // texto ("Ritmo, 5'00\"/km"). Buscar `staticTexts["5'00\"/km"]` a secas no encuentra nada,
        // aunque el número esté en pantalla. Por eso el match es por contenido.
        let ritmoEnVivo = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "5'00\"/km")
        ).firstMatch
        XCTAssertTrue(
            ritmoEnVivo.waitForExistence(timeout: 5),
            "El formulario no mostró el ritmo mientras se cargaban los datos"
        )

        app.buttons["Guardar"].tap()

        // Y queda en el resumen del día, ya guardado.
        esperar(app.staticTexts["Completado"], "el día marcado como completado", timeout: 15)
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "5'00\"/km")
            ).firstMatch.waitForExistence(timeout: 5),
            "El ritmo guardado no coincide con el que mostró el formulario"
        )
    }

    // MARK: - E2E-09

    func testE2E09_GenerarElReportePDF() {
        let app = XCUIApplication.launchForUITesting()
        app.tabBars.buttons["Progreso"].tap()

        let reporte = app.buttons["Reporte"]
        esperar(reporte, "el botón del reporte", timeout: 15)
        reporte.tap()

        // El reporte se arma y se muestra. No se afirma sobre el PDF en sí —eso ya lo cubren los
        // unitarios de `ProgressReportBuilder` (U-42..U-44)—: acá lo que importa es que la pantalla
        // **abre sin romperse**, que es donde un `nil` mal manejado o una división por cero
        // aparecerían.
        esperar(app.navigationBars.firstMatch, "la pantalla del reporte")
        XCTAssertTrue(
            app.staticTexts["Fuerza"].waitForExistence(timeout: 10)
                || app.staticTexts["Suplementos"].exists,
            "El reporte abrió vacío"
        )
    }

    // MARK: - E2E-10

    func testE2E10_ExportarElPlanAPDF() {
        let app = XCUIApplication.launchForUITesting()
        app.tabBars.buttons["Plan"].tap()
        esperar(app.staticTexts["Fondo largo 12 km"], "el plan sembrado", timeout: 15)

        let compartir = app.buttons["Compartir plan"]
        esperar(compartir, "el botón de compartir el plan")
        compartir.tap()

        // La vista previa del plan se arma con los días sembrados.
        esperar(app.navigationBars.firstMatch, "la vista de exportar", timeout: 15)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Fondo largo'")
            ).firstMatch.waitForExistence(timeout: 10),
            "La exportación del plan abrió vacía"
        )
    }
}
