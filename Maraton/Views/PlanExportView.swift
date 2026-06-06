//
//  PlanExportView.swift
//  Maraton
//
//  Exportar el plan de entrenamiento a un PDF compartible (para mandárselo a
//  amigos). Espeja la maquinaria del reporte de progreso (`ReportView`): se
//  arma una vista SwiftUI, se renderiza con `ImageRenderer` a una página PDF
//  continua y se comparte vía `ShareLink` con un `Transferable` de tipo `.pdf`.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - Vista que se renderiza al PDF

/// Diseño del plan para el PDF: encabezado de la carrera + las semanas con sus
/// días. Ancho flexible: en la vista previa ocupa el ancho disponible y, al
/// renderizar el PDF, `PlanPDF` la enmarca a un ancho fijo (A4).
struct PlanExportView: View {
    let days: [WorkoutDay]
    let generatedAt: Date

    /// Días agrupados por semana, ordenados por la fecha de su primer día.
    private var weeks: [(title: String, tag: String?, days: [WorkoutDay])] {
        let sorted = days.sorted { $0.date < $1.date }
        let grouped = Dictionary(grouping: sorted, by: { $0.weekTitle })
        return grouped.values
            .sorted { ($0.first?.date ?? .distantPast) < ($1.first?.date ?? .distantPast) }
            .compactMap { weekDays in
                guard let first = weekDays.first else { return nil }
                return (title: first.weekTitle, tag: first.weekTag, days: weekDays)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ForEach(weeks, id: \.title) { week in
                weekSection(week)
            }
            footer
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Encabezado

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mi plan de entrenamiento")
                .font(.largeTitle.bold())
                .foregroundStyle(.black)
            Text("Media Maratón de Córdoba · \(PlanConstants.raceDistanceKm.formattedKm) km")
                .font(.title3)
                .foregroundStyle(.secondary)
            Label(PlanConstants.raceDate.longDate, systemImage: "flag.checkered")
                .font(.headline)
                .foregroundStyle(WorkoutType.carrera.color)
            Divider()
                .padding(.top, 4)
        }
    }

    // MARK: Semana

    private func weekSection(_ week: (title: String, tag: String?, days: [WorkoutDay])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(week.title)
                    .font(.headline)
                    .foregroundStyle(.black)
                if let tag = week.tag {
                    Text(tag)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(dateRange(of: week.days))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            ForEach(week.days) { day in
                dayRow(day)
            }
        }
        .padding(.vertical, 4)
    }

    private func dayRow(_ day: WorkoutDay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(day.date.weekdayAndDay)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Image(systemName: day.type.symbolName)
                .font(.subheadline)
                .foregroundStyle(day.type.color)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(day.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                if !day.detail.isEmpty {
                    Text(day.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    // MARK: Pie

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Generado el \(generatedAt.longDate)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func dateRange(of days: [WorkoutDay]) -> String {
        let sorted = days.map(\.date).sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        return "\(first.dayMonth) – \(last.dayMonth)"
    }
}

// MARK: - Generación de PDF

@MainActor
enum PlanPDF {
    /// Renderiza el plan a un PDF (una página continua del ancho dado).
    static func makeData(for days: [WorkoutDay], width: CGFloat = 595) -> Data {
        let content = PlanExportView(days: days, generatedAt: Date()).frame(width: width)
        let renderer = ImageRenderer(content: content)
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
    static func writeTempFile(for days: [WorkoutDay]) -> URL? {
        let data = makeData(for: days)
        guard !data.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mi plan de entrenamiento.pdf")
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

/// Archivo PDF compartible (tipo `.pdf` explícito para que WhatsApp, Mail o
/// Archivos lo reciban como documento y no como enlace).
struct PlanPDFFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(file.url)
        }
    }
}

// MARK: - Hoja de compartir

/// Genera el PDF del plan y ofrece la vista previa + el botón de compartir.
struct PlanExportSheet: View {
    let days: [WorkoutDay]

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading
    @State private var thumbnail: Image?

    private enum LoadState {
        case loading
        case ready(URL)
        case empty
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Compartir plan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Listo") { dismiss() }
                    }
                    if case let .ready(url) = state {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(
                                item: PlanPDFFile(url: url),
                                preview: SharePreview(
                                    "Mi plan de entrenamiento",
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
                Text("Generando PDF del plan…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            ScrollView {
                PlanExportView(days: days, generatedAt: Date())
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 2, y: 1)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))

        case .empty:
            ContentUnavailableView(
                "No hay plan para exportar",
                systemImage: "doc",
                description: Text("Agregá algún día al plan para poder compartirlo.")
            )
        }
    }

    private func generate() async {
        guard !days.isEmpty else {
            state = .empty
            return
        }
        guard let url = PlanPDF.writeTempFile(for: days) else {
            state = .empty
            return
        }
        thumbnail = PlanPDF.thumbnail(of: url)
        state = .ready(url)
    }
}

#Preview {
    PlanExportSheet(days: WorkoutSeed.allWorkoutDays())
        .modelContainer(PreviewData.container)
}
