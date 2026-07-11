# GymLog

App nativa de entrenamiento para **iPhone, Apple Watch y Mac**: llevá el plan de la
semana, registrá las series del gimnasio sin tocar el teclado y mirá cómo evoluciona
tu volumen. Escrita en SwiftUI + SwiftData, funciona 100% offline y sincroniza entre
tus dispositivos por iCloud.

Interfaz en español (es-AR), light y dark.

> Nació como una app para preparar la Media Maratón de Córdoba y evolucionó a una app
> de entrenamiento continuo (gimnasio + running). Por eso el proyecto, el target y el
> bundle id todavía se llaman `Maraton`: renombrarlos rompería el historial de la app
> instalada y su contenedor de iCloud. El nombre visible es **GymLog**.

## Qué hace

**Plan semanal.** Días tipificados (fuerza, rodaje, calidad, fondo, carrera, descanso),
cada uno con su color e ícono. Se navega como carrusel, con una tira de la semana para
saltar de un día a otro. El plan es editable: crear, modificar y borrar días.

**Sesión de gimnasio guiada.** Te lleva ejercicio por ejercicio y serie por serie, con
descanso cronometrado. Cada serie llega **pre-cargada** con las reps objetivo del plan y
el peso que usaste la última vez, así solo tocás lo que cambió. El peso y las reps se
eligen con **ruedas estilo alarma** (sin teclado). Si la máquina que seguía está ocupada,
"Cambiar ejercicio" reordena lo que falta. Cada ejercicio muestra su foto.

**La sesión corre en el reloj y se controla desde el teléfono.** El Apple Watch es la
autoridad (registra las series, mide el pulso, guarda el entrenamiento en Apple Salud);
el iPhone es espejo y control remoto. Con el teléfono bloqueado la sesión se ve y se
maneja desde una **Live Activity** (pantalla bloqueada y Dynamic Island), con botones para
completar la serie o saltear el descanso. Sin servidor: todo va por WatchConnectivity.

**Running con Apple Salud.** Importa las corridas desde HealthKit (km, ritmo, pulso,
calorías) y las asocia al día del plan.

**Progreso.** Volumen de la semana en curso (km corridos y kilos levantados), tendencia
de las últimas 6 semanas, rachas de consistencia y evolución de fuerza por ejercicio.

**Suplementos.** Creatina y proteína: marcado diario, adherencia, rachas y recordatorios
locales configurables.

**Exportar a PDF.** Tres reportes, todos compartibles con el share sheet:
- el **plan completo** semana por semana,
- un **día suelto** (tabla de peso × reps por serie y volumen por ejercicio),
- un **reporte de progreso** para el entrenador, que además suma métricas de Apple Salud
  (frecuencia cardíaca en reposo, HRV, VO₂máx, peso, sueño).

## Arquitectura

Cuatro targets, con los archivos organizados en grupos sincronizados por filesystem
(`PBXFileSystemSynchronizedRootGroup`): agregar un archivo a una carpeta lo suma solo a
los targets que la incluyen, sin tocar el `.pbxproj`.

| Carpeta | Target | Qué es |
|---|---|---|
| `Shared/` | iOS + watchOS | Código agnóstico de plataforma: modelos SwiftData (`WorkoutDay`, `Exercise`, `ExerciseSet`, `SupplementLog`), el `GuidedSessionEngine` (máquina de estados de la sesión guiada, compartida iPhone ↔ reloj), los seeds del plan y los formateadores |
| `Maraton/` | iOS + Mac Catalyst | La app de iPhone: vistas, HealthKit, notificaciones, generación de PDFs |
| `MaratonWatch Watch App/` | watchOS | La app del reloj: sesión guiada con corona digital, pulso en vivo vía `HKWorkoutSession` |
| `MaratonLiveActivity/` | Widget Extension | La Live Activity y sus `LiveActivityIntent` |

Los datos viven en **SwiftData** con backend CloudKit (contenedor `iCloud.ariel.Maraton`).
Se puede volver a un store puramente local con `AppData.iCloudSyncEnabled = false`.

Dos restricciones del modelo que impone CloudKit y conviene no romper: **todas las
relaciones tienen que ser opcionales** (incluidas las to-many — de ahí `orderedExercises`
y `orderedSets`) y **no puede haber `@Attribute(.unique)`**. La unicidad por fecha la
valida el código en `WorkoutSeed`.

## Compilar

Requiere Xcode con los platforms de **iOS 26.5+** y **watchOS 11+**. Como el target de
iOS embebe la app del reloj, sin el platform de watchOS tampoco compila el iPhone:

```sh
xcodebuild -downloadPlatform watchOS
```

**iPhone (simulador):**

```sh
xcodebuild -project Maraton.xcodeproj -scheme Maraton \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
```

**Apple Watch (simulador):**

```sh
xcodebuild -project Maraton.xcodeproj -scheme "MaratonWatch Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 7 (45mm)' build
```

**Mac (Catalyst), con firma local:**

```sh
xcodebuild -project Maraton.xcodeproj -scheme Maraton \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

Para correr en un dispositivo físico hace falta una cuenta del Apple Developer Program
(la firma automática necesita la cuenta logueada en Xcode). El pulso en vivo solo funciona
en un Apple Watch real: el simulador no genera frecuencia cardíaca.

En [`HANDOFF.md`](HANDOFF.md) están los comandos de instalación en dispositivo, el detalle
de la configuración de iCloud y las trampas conocidas.

## Estado

Versión 1.0, en preparación para TestFlight. La sincronización por iCloud funciona
end-to-end entre iPhone, Mac y Apple Watch.

Proyecto personal, sin licencia definida.
