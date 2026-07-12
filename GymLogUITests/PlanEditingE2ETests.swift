//
//  PlanEditingE2ETests.swift
//  GymLogUITests
//
//  E2E-06: marcar un suplemento.
//  E2E-07: crear, editar y borrar un día en la tab Plan.
//
//  Backlog: TESTING.md · E2E-06, E2E-07
//

import XCTest

final class PlanEditingE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - E2E-06

    /// ⚠️ **Lo que este test NO afirma, a propósito:** el número de adherencia que muestra Progreso.
    ///
    /// La tab Detalle abre en "hoy si está en el plan; si no, el día más cercano". El plan termina
    /// el 5/7/2026, así que hoy —11/7— muestra el 5/7, y marcar el suplemento registra la toma **de
    /// ese día**. Si el test afirmara "adherencia de 7 días = 1/7", andaría hoy y **se rompería
    /// solo** la semana que viene, cuando el 5/7 se caiga de la ventana. Un test que se rompe con el
    /// calendario y no con el código es peor que no tenerlo.
    ///
    /// Lo que sí se afirma es lo que no depende de la fecha: **la tarjeta refleja la marca** (que es
    /// el ida y vuelta que importa: se guardó y se volvió a leer) y **Progreso muestra la sección de
    /// suplementos**.
    func testE2E06_MarcarUnSuplemento() {
        let app = XCUIApplication.launchForUITesting()

        // La tab Detalle es la de arranque.
        let creatina = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Creatina'")
        ).firstMatch
        scrollHasta(creatina, in: app, "la fila de Creatina")

        XCTAssertTrue(
            creatina.label.contains("Sin registrar") || creatina.label.contains("Pendiente"),
            "La creatina no debería arrancar marcada: \(creatina.label)"
        )

        creatina.tap()

        // La marca sobrevive al ida y vuelta contra la base.
        let marcada = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Creatina' AND label CONTAINS 'Tomado'")
        ).firstMatch
        esperar(marcada, "la creatina marcada como tomada")

        // Y se puede desmarcar: el toggle va para los dos lados.
        marcada.tap()
        let desmarcada = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Creatina' AND (label CONTAINS 'Sin registrar' OR label CONTAINS 'Pendiente')")
        ).firstMatch
        esperar(desmarcada, "la creatina desmarcada")

        // Progreso tiene su sección de suplementos.
        app.tabBars.buttons["Progreso"].tap()
        let seccion = app.staticTexts["Suplementos"]
        scrollHasta(seccion, in: app, "la sección de suplementos en Progreso")
    }

    // MARK: - E2E-07

    func testE2E07_CrearEditarYBorrarUnDia() {
        let app = XCUIApplication.launchForUITesting()
        app.tabBars.buttons["Plan"].tap()
        esperar(app.staticTexts["Fondo largo 12 km"], "el plan sembrado", timeout: 15)

        // --- Crear ---
        app.buttons["Agregar día"].tap()
        esperar(app.navigationBars["Nuevo día"], "la hoja de nuevo día")

        let titulo = app.textFields["Título (ej. Fondo largo 14 km)"]
        esperar(titulo, "el campo de título")
        titulo.tap()
        titulo.typeText("Test rodaje regenerativo")

        app.buttons["Guardar"].tap()

        // El día aparece en el plan.
        let creado = app.staticTexts["Test rodaje regenerativo"]
        scrollHasta(creado, in: app, "el día recién creado")

        // --- Editar ---
        // Se edita el **detalle**, que arranca vacío, en vez de reescribir el título. Limpiar un
        // campo de texto en XCUITest pide el menú de "Select All", que depende del idioma del
        // simulador y de un long-press que a veces no engancha: frágil por razones que no tienen
        // nada que ver con lo que se está probando.
        creado.swipeLeft()

        let editar = app.buttons["Editar"]
        esperar(editar, "la acción de editar")
        editar.tap()
        esperar(app.navigationBars["Editar día"], "la hoja de editar")

        let detalle = app.textFields["Detalle (ej. Z2 conversacional)"]
        esperar(detalle, "el campo de detalle")
        detalle.tap()
        detalle.typeText("Z2 suave")

        app.buttons["Guardar"].tap()

        // La fila del plan muestra el detalle: la edición se guardó y se releyó.
        scrollHasta(app.staticTexts["Z2 suave"], in: app, "el detalle editado en la fila")

        // --- Borrar ---
        let aBorrar = creado
        let etiqueta = aBorrar.label
        scrollHasta(aBorrar, in: app, "el día a borrar")
        aBorrar.swipeLeft()

        let eliminar = app.buttons["Eliminar"]
        esperar(eliminar, "la acción de eliminar")
        eliminar.tap()

        // Y se fue. Se le da un momento a la lista para redibujar.
        let desapareció = app.staticTexts[etiqueta].waitForNonExistence(timeout: 10)
        XCTAssertTrue(desapareció, "El día '\(etiqueta)' sigue en el plan después de borrarlo")
    }
}
