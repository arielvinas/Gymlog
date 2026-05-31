//
//  HealthManager.swift
//  Maraton
//
//  Lectura de entrenamientos de Apple Salud (HealthKit) para los días de corrida.
//

import Foundation
import HealthKit

/// Datos importados de un entrenamiento de Apple Salud.
struct ImportedWorkout {
    var km: Double?
    var minutes: Int?
    var avgHeartRate: Double?
    var activeCalories: Double?
}

enum HealthError: LocalizedError {
    case notAvailable
    case noWorkoutFound

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Salud no está disponible en este dispositivo."
        case .noWorkoutFound:
            return "No encontramos una corrida registrada para este día en Apple Salud."
        }
    }
}

@MainActor
final class HealthManager {
    static let shared = HealthManager()
    private let store = HKHealthStore()

    private init() {}

    /// Tipos que necesitamos leer.
    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    /// Solicita permiso de lectura a Apple Salud.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Busca la corrida del día indicado y devuelve sus métricas.
    /// Si hay varias, toma la de mayor distancia.
    func importRun(for date: Date) async throws -> ImportedWorkout {
        try await requestAuthorization()
        let workouts = try await workouts(on: date, activityTypes: [.running])
        // La de mayor distancia recorrida.
        guard let workout = workouts.max(by: { (distanceKm(of: $0) ?? 0) < (distanceKm(of: $1) ?? 0) }) else {
            throw HealthError.noWorkoutFound
        }
        return ImportedWorkout(
            km: distanceKm(of: workout),
            minutes: Int((workout.duration / 60.0).rounded()),
            avgHeartRate: try await averageHeartRate(for: workout),
            activeCalories: activeCalories(of: workout)
        )
    }

    /// Busca la sesión de fuerza del día y devuelve sus métricas globales
    /// (duración, FC promedio, calorías). HealthKit no expone series ni peso.
    /// Si hay varias, toma la de mayor duración.
    func importStrength(for date: Date) async throws -> ImportedWorkout {
        try await requestAuthorization()
        let workouts = try await workouts(
            on: date,
            activityTypes: [.traditionalStrengthTraining, .functionalStrengthTraining]
        )
        // La de mayor duración.
        guard let workout = workouts.max(by: { $0.duration < $1.duration }) else {
            throw HealthError.noWorkoutFound
        }
        return ImportedWorkout(
            km: nil,
            minutes: Int((workout.duration / 60.0).rounded()),
            avgHeartRate: try await averageHeartRate(for: workout),
            activeCalories: activeCalories(of: workout)
        )
    }

    // MARK: - Consultas

    /// Devuelve los workouts del día que coincidan con alguno de los tipos dados.
    private func workouts(on date: Date, activityTypes: [HKWorkoutActivityType]) async throws -> [HKWorkout] {
        let cal = PlanConstants.calendar
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let typePredicates = activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Distancia del workout en kilómetros.
    private func distanceKm(of workout: HKWorkout) -> Double? {
        let type = HKQuantityType(.distanceWalkingRunning)
        guard let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return sum.doubleValue(for: .meterUnit(with: .kilo))
    }

    /// Calorías activas del workout en kcal.
    private func activeCalories(of workout: HKWorkout) -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        guard let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return sum.doubleValue(for: .kilocalorie())
    }

    /// Frecuencia cardíaca promedio durante el workout (bpm).
    private func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let bpm = statistics?.averageQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }
}
