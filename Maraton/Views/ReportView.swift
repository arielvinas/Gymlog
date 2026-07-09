//
//  ReportView.swift
//  Maraton
//
//  Documento visual del reporte de progreso (para leer y para renderizar a PDF)
//  y la hoja que lo genera, lo previsualiza y lo comparte con el profesor.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - Documento del reporte

struct ReportView: View {
    let report: ProgressReport

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            adherenceSection
            runningSection
            strengthSection
            supplementsSection
            healthSection
            footer
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    // MARK: Encabezado

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reporte de progreso")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text("Media Maratón Córdoba · \(PlanConstants.raceDistanceKm.formattedKm) km")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Text("Período: \(report.periodStart.dayMonth) – \(report.periodEnd.dayMonth)")
                Text("Faltan \(report.daysToRace) días")
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("Generado el \(report.generatedAt.longDate)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().padding(.top, 4)
        }
    }

    // MARK: Adherencia

    private var adherenceSection: some View {
        section("Adherencia al plan", systemImage: "checkmark.seal.fill", tint: .green) {
            row("Entrenamientos completados",
                "\(report.completedTrainingDays) de \(report.trainingDaysCount)  (\(percent(report.completionRate)))")
            row("Racha de semanas", "\(report.weekStreak)")
            row("Racha de días", "\(report.dayStreak)")

            if !report.typeCounts.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(report.typeCounts) { tc in
                    row(tc.type.displayName, "\(tc.completed) de \(tc.planned)")
                }
            }
        }
    }

    // MARK: Corridas

    private var runningSection: some View {
        section("Corridas", systemImage: "figure.run", tint: .blue) {
            row("Km recorridos", "\(report.totalActualKm.formattedKm) de \(report.totalPlannedKm.formattedKm) km planificados")
            row("Cantidad de corridas", "\(report.runCount)")
            row("Ritmo promedio", report.avgPaceSecPerKm.map { $0.formattedPace } ?? "—")
            if let km = report.longestRunKm, let date = report.longestRunDate {
                row("Corrida más larga", "\(km.formattedKm) km · \(date.dayMonth)")
            }
            row("Esfuerzo percibido promedio", report.avgPerceivedEffort.map { String(format: "%.1f/10", $0) } ?? "—")

            if let p = report.projection {
                Divider().padding(.vertical, 2)
                row("Proyección 10 km", p.time10kSeconds.formattedRaceTime)
                row("Proyección media maratón", p.timeHalfSeconds.formattedRaceTime)
                row("Ritmo base proyectado", p.basePaceSecPerKm.formattedPace)
            }

            if !report.recentRuns.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Últimas corridas")
                    .font(.subheadline.weight(.semibold))
                runsTable
            }
        }
    }

    private var runsTable: some View {
        VStack(spacing: 0) {
            runsHeaderRow
            ForEach(report.recentRuns) { run in
                HStack(spacing: 0) {
                    cell(run.date.dayMonth, width: 70)
                    cell(run.typeName, width: 70)
                    cell("\(run.km.formattedKm)", width: 48, align: .trailing)
                    cell(run.paceSecPerKm.map { $0.formattedPace } ?? "—", width: 78, align: .trailing)
                    cell(run.avgHeartRate.map { "\(Int($0.rounded()))" } ?? "—", width: 44, align: .trailing)
                    cell(run.activeCalories.map { "\(Int($0.rounded()))" } ?? "—", width: 50, align: .trailing)
                    cell(run.perceivedEffort.map { "\($0)/10" } ?? "—", width: 48, align: .trailing)
                }
                .font(.caption)
                Divider()
            }
        }
    }

    private var runsHeaderRow: some View {
        HStack(spacing: 0) {
            cell("Fecha", width: 70)
            cell("Tipo", width: 70)
            cell("Km", width: 48, align: .trailing)
            cell("Ritmo", width: 78, align: .trailing)
            cell("FC", width: 44, align: .trailing)
            cell("Kcal", width: 50, align: .trailing)
            cell("RPE", width: 48, align: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Fuerza

    private var strengthSection: some View {
        section("Fuerza", systemImage: "dumbbell.fill", tint: .purple) {
            row("Sesiones completadas", "\(report.strengthSessions)")
            if report.improvements.isEmpty {
                Text("Todavía no hay suficientes sesiones para comparar progresos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider().padding(.vertical, 2)
                Text("Mejores series recientes")
                    .font(.subheadline.weight(.semibold))
                ForEach(report.improvements) { imp in
                    HStack(alignment: .firstTextBaseline) {
                        Text(imp.name)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(imp.previous.text) → \(imp.last.text)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(signedPercent(imp.percentChange))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(imp.percentChange >= 0 ? .green : .red)
                            .frame(width: 56, alignment: .trailing)
                    }
                    Divider()
                }
            }
        }
    }

    // MARK: Suplementos

    private var supplementsSection: some View {
        section("Suplementos", systemImage: "pills.fill", tint: .teal) {
            HStack(spacing: 0) {
                cell("Suplemento", width: 110)
                cell("7 días", width: 70, align: .trailing)
                cell("30 días", width: 70, align: .trailing)
                cell("Plan", width: 60, align: .trailing)
                cell("Racha", width: 60, align: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .overlay(alignment: .bottom) { Divider() }

            ForEach(report.supplements) { s in
                HStack(spacing: 0) {
                    cell(s.name, width: 110)
                    cell(percent(s.adherence7), width: 70, align: .trailing)
                    cell(percent(s.adherence30), width: 70, align: .trailing)
                    cell(percent(s.adherencePlan), width: 60, align: .trailing)
                    cell("\(s.streak)", width: 60, align: .trailing)
                }
                .font(.caption)
                Divider()
            }
        }
    }

    // MARK: Apple Salud

    private var healthSection: some View {
        section("Apple Salud / Fitness", systemImage: "heart.fill", tint: .pink) {
            if !report.health.available {
                Text("No se pudo leer Apple Salud (no disponible o sin permiso).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let h = report.health
                trendRow("FC en reposo", h.restingHeartRate, unit: "ppm", decimals: 0)
                trendRow("Variabilidad (HRV)", h.hrv, unit: "ms", decimals: 0)
                trendRow("VO₂ máx", h.vo2Max, unit: "ml/kg·min", decimals: 1)
                trendRow("Peso corporal", h.bodyMass, unit: "kg", decimals: 1, showChange: true)
                row("Sueño promedio", h.avgSleepHours.map { hoursLabel($0) + "  (\(h.sleepNights) noches)" } ?? "Sin datos")

                Divider().padding(.vertical, 2)
                Text("Entrenamientos de Apple Fitness")
                    .font(.subheadline.weight(.semibold))
                if report.health.workouts.isEmpty {
                    Text("Sin entrenamientos registrados en el período.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    row("Total de entrenamientos", "\(h.workouts.count)")
                    row("Tiempo total", hoursLabel(Double(h.totalWorkoutMinutes) / 60))
                    row("Calorías activas totales", "\(Int(h.totalActiveCalories.rounded())) kcal")
                    if !typeBreakdown.isEmpty {
                        row("Por tipo", typeBreakdown)
                    }
                }
            }
        }
    }

    /// Resumen "Carrera ×4 · Fuerza ×3 · …" de los workouts de Salud.
    private var typeBreakdown: String {
        let counts = Dictionary(grouping: report.health.workouts, by: \.activityName)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return counts.map { "\($0.name) ×\($0.count)" }.joined(separator: " · ")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.bottom, 4)
            Text("Generado por la app GymLog · datos de Apple Salud y del plan de entrenamiento.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Componentes reutilizables

    private func section<Content: View>(_ title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private func trendRow(_ label: String, _ trend: HealthTrend?, unit: String, decimals: Int, showChange: Bool = false) -> some View {
        guard let trend, trend.hasData else {
            return AnyView(row(label, "Sin datos"))
        }
        var parts: [String] = []
        if let latest = trend.latest { parts.append("\(number(latest, decimals)) \(unit)") }
        if let avg = trend.average { parts.append("prom. \(number(avg, decimals))") }
        if showChange, let change = trend.change, abs(change) >= 0.1 {
            parts.append("(\(change >= 0 ? "+" : "")\(number(change, decimals)))")
        }
        return AnyView(row(label, parts.joined(separator: " · ")))
    }

    private func cell(_ text: String, width: CGFloat, align: Alignment = .leading) -> some View {
        Text(text)
            .frame(width: width, alignment: align)
            .lineLimit(1)
            .padding(.vertical, 3)
    }

    // MARK: - Formato

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%@%.0f%%", value >= 0 ? "+" : "", value)
    }

    private func number(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private func hoursLabel(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
}

// MARK: - Generación de PDF

@MainActor
enum ReportPDF {
    /// Renderiza el reporte a un PDF (una página continua del ancho dado).
    static func makeData(for report: ProgressReport, width: CGFloat = 595) -> Data {
        let renderer = ImageRenderer(content: ReportView(report: report).frame(width: width))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)

        let data = NSMutableData()
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            renderInContext(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }

    /// Escribe el PDF a un archivo temporal y devuelve su URL para compartir.
    static func writeTempFile(for report: ProgressReport) -> URL? {
        let data = makeData(for: report)
        guard !data.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reporte de progreso.pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Miniatura de la primera página del PDF, para la vista previa de compartir.
    static func thumbnail(of url: URL, width: CGFloat = 220) -> Image? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let scale = width / bounds.width
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return Image(uiImage: page.thumbnail(of: size, for: .mediaBox))
    }
}

/// Archivo PDF compartible: declara explícitamente el tipo de contenido `.pdf`
/// para que el destino (WhatsApp, Mail, Archivos…) lo reciba como un documento
/// PDF y no como un enlace.
struct ReportPDFFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(file.url)
        }
    }
}

// MARK: - Hoja: generar, previsualizar y compartir

struct ReportSheet: View {
    let days: [WorkoutDay]
    let exercises: [Exercise]
    let logs: [SupplementLog]

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading
    @State private var thumbnail: Image?

    private enum LoadState {
        case loading
        case ready(ProgressReport, URL?)
        case empty
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Reporte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Listo") { dismiss() }
                    }
                    if case let .ready(_, url?) = state {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(
                                item: ReportPDFFile(url: url),
                                preview: SharePreview(
                                    "Reporte de progreso",
                                    image: thumbnail ?? Image(systemName: "doc.richtext")
                                )
                            ) {
                                Label("Compartir", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
        }
        .task { await generate() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Generando reporte…\nLeyendo Apple Salud")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .ready(report, _):
            ScrollView {
                ReportView(report: report)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 2, y: 1)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))

        case .empty:
            ContentUnavailableView(
                "Sin datos para el reporte",
                systemImage: "doc",
                description: Text("Cargá algún entrenamiento del plan para generar un reporte.")
            )
        }
    }

    private func generate() async {
        guard !days.isEmpty else {
            state = .empty
            return
        }
        let start = days.map(\.date).min() ?? Date()
        let health = await HealthManager.shared.snapshot(from: start, to: Date())
        let report = ProgressReportBuilder.build(days: days, exercises: exercises, logs: logs, health: health)
        let url = ReportPDF.writeTempFile(for: report)
        thumbnail = url.flatMap { ReportPDF.thumbnail(of: $0) }
        state = .ready(report, url)
    }
}
