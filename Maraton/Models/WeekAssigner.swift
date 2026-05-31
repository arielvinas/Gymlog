//
//  WeekAssigner.swift
//  Maraton
//
//  Asigna la semana (título/etiqueta/orden) a un día según su fecha.
//

import Foundation

enum WeekAssigner {
    struct WeekInfo {
        let title: String
        let tag: String?
        let order: Int
    }

    /// Determina la semana de un día: si ya existen días en la misma semana
    /// calendario, hereda su agrupación; si no, crea una semana nueva.
    static func weekInfo(for date: Date, among days: [WorkoutDay]) -> WeekInfo {
        let cal = PlanConstants.calendar

        if let sameWeek = days.first(where: {
            cal.isDate($0.date, equalTo: date, toGranularity: .weekOfYear)
        }) {
            return WeekInfo(title: sameWeek.weekTitle, tag: sameWeek.weekTag, order: sameWeek.weekOrder)
        }

        // Semana nueva: título basado en el inicio de esa semana.
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let weekStart = cal.date(from: comps) ?? date
        let nextOrder = (days.map(\.weekOrder).max() ?? 0) + 1
        return WeekInfo(title: "Semana del \(weekStart.dayMonth)", tag: nil, order: nextOrder)
    }
}
