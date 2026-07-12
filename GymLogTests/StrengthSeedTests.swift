//
//  StrengthSeedTests.swift
//  GymLogTests
//
//  `StrengthSeed` decide **qué rutina le toca a cada día de fuerza**. Es una
//  función pura de (título, fecha) → lista de ejercicios, y de ella depende lo
//  que el usuario encuentra al abrir la sesión guiada.
//
//  Backlog: TESTING.md · U-18..U-21
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Rutinas de fuerza · selección")
struct StrengthSeedTests {

    /// Una fecha fuera de las semanas de pico y taper, para que el filtro de saltos no
    /// interfiera cuando lo que se está probando es la elección de rutina (ver U-20).
    private let fechaNormal = date(2026, 6, 10)

    /// Los nombres de la rutina que le toca a un día. Se compara por nombre porque
    /// `ExerciseTemplate` no es `Equatable` — y el nombre es lo que distingue una rutina de
    /// la otra, que es justo lo que estos tests miran.
    @MainActor
    private func nombres(_ day: WorkoutDay) -> [String] {
        StrengthSeed.templates(for: day).map(\.name)
    }

    // MARK: - U-18

    // ⚠️ **Bug 1.** La rutina se elige mirando el título:
    //
    //     if title.contains("liviana") { … } else if title.contains("b") { dayB } else { dayA }
    //
    // Ese `contains("b")` no busca "el día B": busca **la letra b, en cualquier lugar del
    // título**. Con los títulos que siembra el plan funciona de casualidad — ninguno de los
    // de Día A tiene una "b". Pero el título **lo edita el usuario** (`WorkoutEditView` lo
    // expone en un `TextField`), y ahí se cae.

    @Test("U-18 · Con los títulos del plan, la elección es la correcta")
    func thePlanTitlesPickTheRightRoutine() {
        let db = TestDB()

        let diaA = makeDay(fechaNormal, type: .fuerza, title: "Fuerza A", in: db.context)
        let diaB = makeDay(fechaNormal, type: .fuerza, title: "Fuerza B", in: db.context)

        // Esta es la razón por la que el bug no explotó nunca: "fuerza a" no tiene ninguna
        // "b" suelta. Es una coincidencia afortunada, no una garantía.
        #expect(nombres(diaA) == StrengthSeed.dayA.map(\.name))
        #expect(nombres(diaB) == StrengthSeed.dayB.map(\.name))
    }

    @Test(
        "U-18 · ⚠️ Cualquier 'b' en el título trae la rutina del Día B",
        arguments: [
            // Lo que un usuario escribiría al renombrar un día de Día A.
            "Fuerza A · brazos",
            "Fuerza A (banco plano)",
            "Gimnasio básico",
            "Fuerza A · bloque principal",
            // Y el caso más incómodo: el título ni siquiera menciona la letra como tal.
            "Hombros y abdominales",
        ]
    )
    func anyBInTheTitleBringsDayB(title: String) {
        let db = TestDB()
        let day = makeDay(fechaNormal, type: .fuerza, title: title, in: db.context)

        // ⚠️ Todos estos son días de **Día A** para el usuario, y reciben la rutina del
        // **Día B**: otros ejercicios, otras series, otro trabajo.
        #expect(
            nombres(day) == StrengthSeed.dayB.map(\.name),
            "Comportamiento actual: la letra 'b' en \"\(title)\" gana"
        )
        #expect(nombres(day) != StrengthSeed.dayA.map(\.name))
    }

    @Test("U-18 · Es alcanzable: el título lo edita el usuario y el seed lo relee")
    func itIsReachableThroughTheTitleEditor() {
        let db = TestDB()

        // `WorkoutEditView` expone el título en un `TextField`. El usuario renombra su día A
        // para acordarse de qué hace.
        let day = makeDay(fechaNormal, type: .fuerza, title: "Fuerza A", in: db.context)
        #expect(nombres(day) == StrengthSeed.dayA.map(\.name))

        day.title = "Fuerza A · empuje y brazos"

        // Y `populateIfNeeded` llama a `templates(for:)` con el título **actual**, así que
        // un día vacío renombrado se llena con la rutina equivocada. No hace falta que el
        // usuario haga nada raro: alcanza con que le ponga nombre a su propio entrenamiento.
        #expect(nombres(day) == StrengthSeed.dayB.map(\.name), "⚠️ Cambió de rutina al renombrarlo")
    }

    @Test("U-18 · 'liviana' gana sobre la 'b', pero por orden, no por precisión")
    func livianaWinsByOrdering() {
        let db = TestDB()

        // Este título tiene las dos cosas: "liviana" **y** una "b" (en "banco"). Cae en el
        // taper y no en el Día B completo, pero solo porque el `if` de "liviana" va
        // **primero**. Si alguien reordenara los dos `if`, este día cambiaría de rutina.
        let taper = makeDay(fechaNormal, type: .fuerza,
                            title: "Fuerza liviana (banco)", in: db.context)

        let rutina = StrengthSeed.templates(for: taper).map(\.name)
        #expect(rutina != StrengthSeed.dayB.map(\.name), "No es el Día B completo: es su variante de taper")
        #expect(rutina.count < StrengthSeed.dayB.count, "El taper saca ejercicios")

        // O sea: el orden de los `if` es lo único que evita que "liviana" y "b" choquen. Un
        // `switch` sobre un campo explícito (un `enum` de rutina en el día) haría innecesaria
        // toda esta adivinanza sobre el texto.
    }
}
