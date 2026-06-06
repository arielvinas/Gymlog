//
//  ProgressReport.swift
//  Maraton
//
//  Arma el reporte de progreso para el profesor: junta la adherencia al plan,
//  las corridas, la fuerza, los suplementos y los datos de Apple Salud en una
//  estructura lista para renderizar a PDF.
//

import Foundation

// MARK: - Filas del reporte

struct ReportTypeCount: Identifiable {
    let id = UUID()
    let type: WorkoutType
    let completed: Int
    let planned: Int
}

struct ReportRunRow: Identifiable {
    let id = UUID()
    let date: Date
    let typeName: String
    let km: Double
    let paceSecPerKm: Double?
    let avgHeartRate: Double?
    let activeCalories: Double?
    let perceivedEffort: Int?
}

struct ReportSupplementRow: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let adherence7: Double
    let adherence30: Double
    let adherencePlan: Double
    let streak: Int
}

// MARK: - Reporte

struct ProgressReport {
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let daysToRace: Int

    // Adherencia al plan
    let trainingDaysCount: Int
    let completedTrainingDays: Int
    let weekStreak: Int
    let dayStreak: Int
    let typeCounts: [ReportTypeCount]

    // Corridas
    let totalActualKm: Double
    let totalPlannedKm: Double
    let runCount: Int
    let avgPaceSecPerKm: Double?
    let longestRunKm: Double?
    let longestRunDate: Date?
    let avgPerceivedEffort: Double?
    let recentRuns: [ReportRunRow]
    let projection: RaceProjection?

    // Fuerza
    let strengthSessions: Int
    let improvements: [ExerciseImprovement]

    // Suplementos
    let supplements: [ReportSupplementRow]

    // Apple Salud / Fitness
    let health: HealthSnapshot

    /// Porcentaje de entrenamientos completados (0..1).
    var completionRate: Double {
        trainingDaysCount > 0 ? Double(completedTrainingDays) / Double(trainingDaysCount) : 0
    }
}

// MARK: - Constructor

enum ProgressReportBuilder {

    /// Construye el reporte a partir de los datos locales y el snapshot de Salud.
    static func build(
        days: [WorkoutDay],
        exercises: [Exercise],
        logs: [SupplementLog],
        health: HealthSnapshot,
        today: Date = Date()
    ) -> ProgressReport {
        let cal = PlanConstants.calendar
        let todayStart = cal.startOfDay(for: today)
        let sorted = days.sorted { $0.date < $1.date }
        let periodStart = sorted.first?.date ?? today

        // Días del plan transcurridos (hasta hoy inclusive).
        let periodDays = sorted.filter { cal.startOfDay(for: $0.date) <= todayStart }

        let trainingDays = periodDays.filter { $0.type != .descanso }
        let completedTraining = trainingDays.filter(\.isCompleted)

        // Conteo por tipo (sólo los que aparecen en el período).
        let orderedTypes: [WorkoutType] = [.rodaje, .calidad, .fondo, .fuerza, .carrera]
        let typeCounts = orderedTypes.map { type in
            ReportTypeCount(
                type: type,
                completed: periodDays.filter { $0.type == type && $0.isCompleted }.count,
                planned: periodDays.filter { $0.type == type }.count
            )
        }.filter { $0.planned > 0 }

        // Corridas registradas con distancia.
        let runs = periodDays.filter { $0.type.isRun && $0.isCompleted && ($0.actualKm ?? 0) > 0 }
        let totalActualKm = runs.compactMap(\.actualKm).reduce(0, +)
        let totalPlannedKm = periodDays.compactMap(\.plannedKm).reduce(0, +)

        // Ritmo promedio ponderado por distancia (sólo corridas con duración).
        let pacedRuns = runs.filter { ($0.durationMinutes ?? 0) > 0 }
        let totalSeconds = pacedRuns.reduce(0.0) { $0 + Double($1.durationMinutes ?? 0) * 60 }
        let pacedKm = pacedRuns.compactMap(\.actualKm).reduce(0, +)
        let avgPace = pacedKm > 0 ? totalSeconds / pacedKm : nil

        let longest = runs.max { ($0.actualKm ?? 0) < ($1.actualKm ?? 0) }

        let efforts = runs.compactMap(\.perceivedEffort)
        let avgEffort = efforts.isEmpty ? nil : Double(efforts.reduce(0, +)) / Double(efforts.count)

        let recentRuns = runs.sorted { $0.date > $1.date }.prefix(10).map { day in
            ReportRunRow(
                date: day.date,
                typeName: day.type.displayName,
                km: day.actualKm ?? 0,
                paceSecPerKm: day.paceSecondsPerKm,
                avgHeartRate: day.avgHeartRate,
                activeCalories: day.activeCalories,
                perceivedEffort: day.perceivedEffort
            )
        }

        let projection = AveragePaceProjection()
            .project(from: RaceProjectionBuilder.samples(from: periodDays), today: today)

        let strengthSessions = periodDays.filter { $0.type == .fuerza && $0.isCompleted }.count
        let improvements = StrengthProgress.recentImprovements(exercises: exercises)

        // Suplementos: adherencia 7d / 30d / todo el plan + racha.
        let planDays = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: periodStart), to: todayStart).day ?? 0) + 1)
        let supplements = SupplementKind.allCases.map { kind in
            ReportSupplementRow(
                name: kind.displayName,
                symbol: kind.symbolName,
                adherence7: SupplementTracker.adherence(kind, lastDays: 7, logs: logs, today: today),
                adherence30: SupplementTracker.adherence(kind, lastDays: 30, logs: logs, today: today),
                adherencePlan: SupplementTracker.adherence(kind, lastDays: planDays, logs: logs, today: today),
                streak: SupplementTracker.currentStreak(kind, logs: logs, today: today)
            )
        }

        return ProgressReport(
            generatedAt: today,
            periodStart: periodStart,
            periodEnd: today,
            daysToRace: PlanConstants.daysUntilRace(),
            trainingDaysCount: trainingDays.count,
            completedTrainingDays: completedTraining.count,
            weekStreak: StreakCalculator.currentWeekStreak(days: days, today: today),
            dayStreak: StreakCalculator.currentDayStreak(days: days, today: today),
            typeCounts: typeCounts,
            totalActualKm: totalActualKm,
            totalPlannedKm: totalPlannedKm,
            runCount: runs.count,
            avgPaceSecPerKm: avgPace,
            longestRunKm: longest?.actualKm,
            longestRunDate: longest?.date,
            avgPerceivedEffort: avgEffort,
            recentRuns: Array(recentRuns),
            projection: projection,
            strengthSessions: strengthSessions,
            improvements: improvements,
            supplements: supplements,
            health: health
        )
    }
}
