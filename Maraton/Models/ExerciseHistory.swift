//
//  ExerciseHistory.swift
//  Maraton
//
//  Búsqueda del registro anterior de un mismo ejercicio ("última vez").
//

import Foundation
import SwiftData

enum ExerciseHistory {
    /// Busca la sesión anterior más reciente del ejercicio con el mismo
    /// nombre, anterior a `currentDate`, que tenga datos registrados.
    /// Devuelve un resumen de sus series o `nil` si no hay histórico.
    @MainActor
    static func lastSession(
        name: String,
        before currentDate: Date,
        context: ModelContext
    ) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { exercise in
                exercise.name == trimmed && exercise.dayDate < currentDate
            },
            sortBy: [SortDescriptor(\Exercise.dayDate, order: .reverse)]
        )
        descriptor.fetchLimit = 10

        guard let matches = try? context.fetch(descriptor) else { return nil }

        // Toma el más reciente que efectivamente tenga datos cargados.
        guard let previous = matches.first(where: { $0.hasLoggedData }) else { return nil }

        let resumenSeries = previous.orderedSets
            .filter { $0.reps != nil || $0.weight != nil }
            .map { $0.summary }
            .joined(separator: ", ")

        guard !resumenSeries.isEmpty else { return nil }
        return resumenSeries
    }
}
