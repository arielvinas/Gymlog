//
//  StrengthProgressTests.swift
//  GymLogTests
//
//  La evolución de fuerza: compara la mejor serie de la última sesión de cada
//  ejercicio contra la anterior. Es lo que le dice al usuario "subiste 5% en press
//  banca" — y como sale de comparar dos números que él mismo cargó, un error acá
//  no se ve: se cree.
//
//  Backlog: TESTING.md · U-34..U-36
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

@Suite("Progreso de fuerza")
struct StrengthProgressTests {

    /// Registra una sesión de un ejercicio en una fecha, con sus series.
    @MainActor
    @discardableResult
    private func sesion(
        _ nombre: String,
        _ fecha: Date,
        sets: [(weight: Double?, reps: Int?)],
        in context: ModelContext
    ) -> Exercise {
        let dia = makeDay(fecha, type: .fuerza, title: "Fuerza A", in: context)
        return makeExercise(nombre, on: dia, order: 0, sets: sets, in: context)
    }

    // MARK: - U-34

    @Test("U-34 · Detecta una subida de peso entre las dos últimas sesiones")
    func detectsAWeightIncrease() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(80, 8), (80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 17), sets: [(85, 6), (85, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        let press = try #require(mejoras.first { $0.name == "Press banca" })
        #expect(press.last.weight == 85)
        #expect(press.previous.weight == 80)

        // De 80 a 85 son 6,25%. Se compara contra el peso **anterior**, no contra el nuevo:
        // subir de 80 a 85 es +6,25%, no +5,88%.
        #expect(abs(press.percentChange - 6.25) < 0.001)
    }

    @Test("U-34 · La 'mejor serie' es la de mayor peso, no la última")
    func theTopSetIsTheHeaviestOne() throws {
        let db = TestDB()

        // Una sesión en pirámide que termina con una serie liviana de descarga. La comparación
        // tiene que agarrar los 90, no los 60 del final.
        sesion("Sentadilla", date(2026, 6, 10), sets: [(70, 10)], in: db.context)
        sesion("Sentadilla", date(2026, 6, 17), sets: [(80, 8), (90, 5), (60, 12)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        let sentadilla = try #require(mejoras.first { $0.name == "Sentadilla" })
        #expect(sentadilla.last.weight == 90)
        #expect(sentadilla.last.reps == 5, "Y se lleva las reps de esa serie, no de otra")
    }

    @Test("U-34 · Con el mismo peso, la mejor serie es la de más reps")
    func repsBreakTheTie() throws {
        let db = TestDB()

        sesion("Remo", date(2026, 6, 10), sets: [(60, 8)], in: db.context)
        // Mismo peso en las tres, distintas reps: gana la de 12.
        sesion("Remo", date(2026, 6, 17), sets: [(60, 8), (60, 12), (60, 10)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let remo = try #require(
            StrengthProgress.recentImprovements(exercises: ejercicios).first { $0.name == "Remo" }
        )

        #expect(remo.last.reps == 12)

        // ⚠️ Pero el porcentaje **solo mira el peso**: mismo peso, 0% de cambio, aunque hayas
        // hecho 4 reps más. La tarjeta va a decir "0%" sobre una sesión que fue claramente
        // mejor. No es un bug —el contrato es "variación del peso"— pero el nombre
        // `ExerciseImprovement` promete más de lo que mide.
        #expect(remo.percentChange == 0)
    }

    @Test("U-34 · Un ejercicio con una sola sesión no aparece")
    func exercisesWithASingleSessionAreIgnored() throws {
        let db = TestDB()

        // Solo una sesión: no hay contra qué comparar.
        sesion("Press banca", date(2026, 6, 17), sets: [(80, 8)], in: db.context)
        // Dos, pero una sin ningún peso cargado: `topSet` la descarta y queda una sola útil.
        sesion("Dominadas", date(2026, 6, 10), sets: [(nil, 8)], in: db.context)
        sesion("Dominadas", date(2026, 6, 17), sets: [(10, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        // El `guard conDatos.count >= 2` los saca a los dos. Está bien: mostrar "+100%" porque
        // antes no había dato sería mentir.
        #expect(mejoras.isEmpty)
    }

    @Test("U-34 · Compara las dos últimas sesiones, no la primera con la última")
    func itComparesTheTwoMostRecentSessions() throws {
        let db = TestDB()

        // Tres sesiones: 60 → 80 → 85. La tarjeta muestra el último salto (80 → 85), no el
        // acumulado desde el principio.
        sesion("Press banca", date(2026, 6, 3), sets: [(60, 10)], in: db.context)
        sesion("Press banca", date(2026, 6, 10), sets: [(80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 17), sets: [(85, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let press = try #require(
            StrengthProgress.recentImprovements(exercises: ejercicios).first
        )

        #expect(press.previous.weight == 80, "La anterior, no la primera de todas")
        #expect(press.last.weight == 85)
    }

    @Test("U-34 · Las mejoras salen ordenadas por fecha, la más reciente primero")
    func improvementsAreSortedByDate() throws {
        let db = TestDB()

        // Dos ejercicios con progreso en semanas distintas.
        sesion("Press banca", date(2026, 6, 3), sets: [(80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 10), sets: [(85, 8)], in: db.context)

        sesion("Sentadilla", date(2026, 6, 10), sets: [(100, 5)], in: db.context)
        sesion("Sentadilla", date(2026, 6, 17), sets: [(110, 5)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        // La sentadilla mejoró el 17, el press el 10. Primero la más fresca.
        //
        // El orden importa porque `prefix(limit)` corta después de ordenar: con muchos
        // ejercicios, los que se muestran son los **más recientes**, no los que más subieron.
        #expect(mejoras.map(\.name) == ["Sentadilla", "Press banca"])
    }

    // MARK: - U-35 · El límite y el signo del porcentaje

    @Test("U-35 · limit: 0 devuelve vacío (el borde seguro del bug 11)")
    func aLimitOfZeroReturnsNothing() throws {
        let db = TestDB()

        sesion("Press banca", date(2026, 6, 10), sets: [(80, 8)], in: db.context)
        sesion("Press banca", date(2026, 6, 17), sets: [(85, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())

        // Hay una mejora real de por medio: si sale vacío es por el límite, no por falta de datos.
        #expect(StrengthProgress.recentImprovements(exercises: ejercicios).count == 1)
        #expect(StrengthProgress.recentImprovements(exercises: ejercicios, limit: 0).isEmpty)
    }

    /// ⚠️ **Bug 11, segunda mitad.** `recentImprovements(limit: -1)` termina en
    /// `Array.prefix(-1)`, que **no** devuelve `[]`: dispara un *precondition failure* y mata el
    /// proceso. Igual que en `WeeklyVolume.recentWeeks(-1)` (U-27), no se puede escribir un test
    /// que lo provoque —los tests corren en paralelo y se caería toda la suite—, así que lo que
    /// se fija acá es la **contención**: `limit` es un parámetro con default y **ningún call site
    /// lo pasa**.
    ///
    /// Los dos únicos llamadores, a hoy:
    ///   - `ProgressDashboardView.improvements` → `recentImprovements(exercises: exercises)`
    ///   - `ProgressReportBuilder.build`        → `recentImprovements(exercises: exercises)`
    ///
    /// Ninguno tiene de dónde sacar un número negativo: no hay `Stepper`, ni `TextField`, ni
    /// preferencia del usuario detrás del límite. El crash existe, pero está fuera de alcance.
    /// El día que alguien haga configurable "cuántos ejercicios mostrar", este test es el
    /// recordatorio de que hace falta un `max(0, limit)`.
    @Test("U-35 · El límite por defecto es 5 y nadie lo pasa desde afuera")
    func theDefaultLimitIsFiveAndNoCallerOverridesIt() throws {
        let db = TestDB()

        // Seis ejercicios distintos, todos con la misma mejora (50 → 55), uno por mes: el press
        // banca en enero, el curl en junio.
        let nombres = ["Press banca", "Remo", "Sentadilla", "Peso muerto", "Dominadas", "Curl"]
        for (i, nombre) in nombres.enumerated() {
            sesion(nombre, date(2026, i + 1, 3), sets: [(50, 8)], in: db.context)
            sesion(nombre, date(2026, i + 1, 10), sets: [(55, 8)], in: db.context)
        }

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let mejoras = StrengthProgress.recentImprovements(exercises: ejercicios)

        // Seis mejoras, pero el default corta en 5.
        #expect(mejoras.count == 5)
        // Y corta **después** de ordenar por fecha: el que se cae es el más viejo (Press banca,
        // el primero del bucle), no el que menos subió —todos subieron lo mismo—.
        #expect(!mejoras.map(\.name).contains("Press banca"))
        #expect(mejoras.first?.name == "Curl", "El más reciente arriba")
    }

    @Test("U-35 · El porcentaje puede ser negativo: 'improvement' también registra retrocesos")
    func percentChangeCanBeNegative() throws {
        let db = TestDB()

        // Bajó de 100 a 90: un retroceso del 10%.
        sesion("Sentadilla", date(2026, 6, 10), sets: [(100, 5)], in: db.context)
        sesion("Sentadilla", date(2026, 6, 17), sets: [(90, 5)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let sentadilla = try #require(
            StrengthProgress.recentImprovements(exercises: ejercicios).first
        )

        // El tipo se llama `ExerciseImprovement`, pero el contrato real es **variación**: los
        // retrocesos no se filtran, aparecen con signo negativo. Está bien que sea así —esconder
        // una baja sería peor—, y las dos vistas lo asumen: `StrengthEvolutionCard` pinta de rojo
        // el valor negativo y `ReportView` también. El que engaña es el nombre del tipo.
        #expect(abs(sentadilla.percentChange - (-10)) < 0.001)
    }

    @Test("U-35 · Un peso anterior de 0 se descarta en vez de dividir por cero")
    func aPreviousWeightOfZeroIsSkipped() throws {
        let db = TestDB()

        // Alguien cargó "0 kg" (peso corporal, o un typo). La sesión siguiente sí tiene peso.
        sesion("Dominadas", date(2026, 6, 10), sets: [(0, 10)], in: db.context)
        sesion("Dominadas", date(2026, 6, 17), sets: [(10, 6)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())

        // El `guard anterior.top.weight > 0` lo saca de la lista. Sin ese guard el cálculo sería
        // (10 - 0) / 0 → infinito, y la tarjeta mostraría "+inf%". Prefiere no decir nada.
        #expect(StrengthProgress.recentImprovements(exercises: ejercicios).isEmpty)
    }

    @Test("U-35 · Pero un peso 0 en la última sesión sí entra: -100%")
    func aLastWeightOfZeroReportsMinusOneHundred() throws {
        let db = TestDB()

        // El guard solo mira el peso **anterior**. Si el 0 está en la sesión nueva, el cálculo
        // corre igual y da -100%.
        sesion("Dominadas", date(2026, 6, 10), sets: [(10, 6)], in: db.context)
        sesion("Dominadas", date(2026, 6, 17), sets: [(0, 12)], in: db.context)

        let ejercicios = try db.context.fetch(FetchDescriptor<Exercise>())
        let dominadas = try #require(
            StrengthProgress.recentImprovements(exercises: ejercicios).first
        )

        // Es asimétrico, pero no está mal: pasar de +10 kg a peso corporal **es** un retroceso
        // del 100% en carga externa. Lo que sí es raro es la asimetría en sí: el mismo dato (un 0)
        // se ignora si está atrás y se reporta si está adelante.
        #expect(abs(dominadas.percentChange - (-100)) < 0.001)
    }
}
