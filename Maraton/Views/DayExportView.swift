//
//  DayExportView.swift
//  Maraton
//
//  Exportar UN día de entrenamiento a un PDF compartible, para evaluar la
//  performance de esa sesión: en los días de fuerza, los pesos y repeticiones
//  de cada serie de cada ejercicio (más el volumen); en las corridas, los datos
//  registrados (km, ritmo, FC, etc.). Espeja la maquinaria del plan
//  (`PlanExportView`/`PlanPDF`): vista SwiftUI → `ImageRenderer` → PDF y
//  `ShareLink` con un `Transferable` de tipo `.pdf`.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - Vista que se renderiza al PDF

/// Diseño de un día para el PDF: encabezado + (según el tipo) la rutina de
/// gimnasio con sus series o el resumen de la corrida. Ancho flexible: al
/// renderizar, `DayPDF` la enmarca a un ancho fijo (A4).
struct DayExportView: View {
    let day: WorkoutDay
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if day.type == .fuerza {
                if healthMetrics.isEmpty == false {
                    metricsSection(title: "Sesión", rows: healthMetrics)
                }
                strengthSection
            } else if day.type.isRun {
                metricsSection(title: "Corrida", rows: runMetrics)
            }

            if let notes = day.notes, !notes.isEmpty {
                notesSection(notes)
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
            HStack(spacing: 8) {
                Image(systemName: day.type.symbolName)
                    .foregroundStyle(day.type.color)
                Text(day.type.displayName.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(day.type.color)
                if day.isCompleted {
                    Label("Completado", systemImage: "checkmark.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
            }

            Text(day.title)
                .font(.largeTitle.bold())
                .foregroundStyle(.black)

            if !day.detail.isEmpty {
                Text(day.detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text(day.date.longDate)
                .font(.headline)
                .foregroundStyle(.secondary)

            Divider().padding(.top, 4)
        }
    }

    // MARK: Fuerza

    @ViewBuilder
    private var strengthSection: some View {
        let exercises = day.orderedExercises
        if exercises.isEmpty {
            Text("Sin ejercicios registrados.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(exercises) { exercise in
                    exerciseBlock(exercise)
                }

                if totalVolume > 0 {
                    Divider()
                    HStack {
                        Text("Volumen total")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                        Spacer()
                        Text("\(totalVolume.formattedKg) kg")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WorkoutType.fuerza.color)
                    }
                }
            }
        }
    }

    private func exerciseBlock(_ exercise: Exercise) -> some View {
        let sets = exercise.orderedSets
        let tracksWeight = exercise.tracksWeight
        let unit = exercise.countUnit

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(.black)
                Spacer()
                if let target = exercise.targetReps, !target.isEmpty {
                    Text("Objetivo: \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if sets.isEmpty || !exercise.hasLoggedData {
                Text("Sin registro")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Cabecera de la tabla de series.
                HStack {
                    Text("Serie").frame(width: 50, alignment: .leading)
                    if tracksWeight {
                        Text("Peso").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(unit.capitalizedFirst).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(sets) { set in
                    HStack {
                        HStack(spacing: 4) {
                            if set.isDone {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            Text("\(set.order)")
                        }
                        .frame(width: 50, alignment: .leading)

                        if tracksWeight {
                            Text(set.weight.map { "\($0.formattedKg) kg" } ?? "—")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(set.reps.map { "\($0)" } ?? "—")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.black)
                }

                if tracksWeight, let volume = volume(of: exercise), volume > 0 {
                    Text("Volumen: \(volume.formattedKg) kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.04))
        )
    }

    // MARK: Métricas (corrida o salud)

    private func metricsSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .fontWeight(.medium)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.04))
        )
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notas")
                .font(.headline)
                .foregroundStyle(.black)
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    // MARK: Datos derivados

    /// Métricas de Apple Salud guardadas en el día (si se importaron).
    private var healthMetrics: [(String, String)] {
        var rows: [(String, String)] = []
        if let minutes = day.durationMinutes { rows.append(("Duración", "\(minutes) min")) }
        if let hr = day.avgHeartRate { rows.append(("Frec. cardíaca", "\(Int(hr)) bpm")) }
        if let cal = day.activeCalories { rows.append(("Calorías", "\(Int(cal)) kcal")) }
        if let effort = day.perceivedEffort { rows.append(("Esfuerzo", "\(effort)/10")) }
        return rows
    }

    /// Resumen de una corrida registrada.
    private var runMetrics: [(String, String)] {
        var rows: [(String, String)] = []
        if let km = day.actualKm { rows.append(("Distancia", "\(km.formattedKm) km")) }
        if let minutes = day.durationMinutes { rows.append(("Duración", "\(minutes) min")) }
        if let pace = day.paceSecondsPerKm { rows.append(("Ritmo", pace.formattedPace)) }
        if let hr = day.avgHeartRate { rows.append(("Frec. cardíaca", "\(Int(hr)) bpm")) }
        if let cal = day.activeCalories { rows.append(("Calorías", "\(Int(cal)) kcal")) }
        if let effort = day.perceivedEffort { rows.append(("Esfuerzo", "\(effort)/10")) }
        if rows.isEmpty { rows.append(("Estado", "Sin registro")) }
        return rows
    }

    /// Volumen (kg) de un ejercicio: suma de peso × reps de sus series.
    private func volume(of exercise: Exercise) -> Double? {
        guard exercise.tracksWeight else { return nil }
        return exercise.orderedSets.reduce(0) { acc, set in
            guard let w = set.weight, let r = set.reps else { return acc }
            return acc + w * Double(r)
        }
    }

    /// Volumen total de la sesión de fuerza.
    private var totalVolume: Double {
        day.orderedExercises.reduce(0) { $0 + (volume(of: $1) ?? 0) }
    }
}

// MARK: - Generación de PDF

@MainActor
enum DayPDF {
    /// Renderiza un día a un PDF (una página continua del ancho dado).
    static func makeData(for day: WorkoutDay, width: CGFloat = 595) -> Data {
        let content = DayExportView(day: day, generatedAt: Date()).frame(width: width)
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

    /// Nombre de archivo legible (ej. "Entrenamiento 23 jun.pdf").
    static func fileName(for day: WorkoutDay) -> String {
        "Entrenamiento \(day.date.dayMonth).pdf"
    }

    /// Escribe el PDF a un archivo temporal y devuelve su URL para compartir.
    static func writeTempFile(for day: WorkoutDay) -> URL? {
        let data = makeData(for: day)
        guard !data.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: day))
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
struct DayPDFFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(file.url)
        }
    }
}

// MARK: - Hoja de compartir

/// Genera el PDF de un día y ofrece la vista previa + el botón de compartir.
struct DayExportSheet: View {
    let day: WorkoutDay

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
                .navigationTitle("Compartir día")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Listo") { dismiss() }
                    }
                    if case let .ready(url) = state {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(
                                item: DayPDFFile(url: url),
                                preview: SharePreview(
                                    day.title.isEmpty ? "Entrenamiento" : day.title,
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
                Text("Generando PDF del día…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            ScrollView {
                DayExportView(day: day, generatedAt: Date())
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 2, y: 1)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))

        case .empty:
            ContentUnavailableView(
                "No se pudo generar el PDF",
                systemImage: "doc",
                description: Text("Probá de nuevo en un momento.")
            )
        }
    }

    private func generate() async {
        guard let url = DayPDF.writeTempFile(for: day) else {
            state = .empty
            return
        }
        thumbnail = DayPDF.thumbnail(of: url)
        state = .ready(url)
    }
}

#Preview {
    DayExportSheet(day: WorkoutSeed.allWorkoutDays().first { $0.type == .fuerza } ?? WorkoutSeed.allWorkoutDays()[0])
        .modelContainer(PreviewData.container)
}
