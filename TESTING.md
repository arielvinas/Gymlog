# GymLog — Plan de pruebas

Estado actual: **cero tests, cero CI, cero hooks**. Este documento define qué probar, en qué
orden, y cuándo corre cada cosa. Es también el backlog: cada ítem tiene un ID estable y un
checkbox, para ir tachándolos de a uno.

## Estrategia

Tres niveles, con una regla de oro: **un test por comportamiento, no por método**. No buscamos
cobertura de líneas — buscamos que los invariantes que hoy sostienen la app a mano queden
escritos.

| Nivel | Qué prueba | Presupuesto |
|---|---|---|
| **Unit** | Lógica pura: parseo, cálculo, formateo, serialización | < 5 s |
| **Integración** | SwiftData en memoria: máquina de estados, seeds, wire | < 30 s |
| **E2E** | Recorridos de usuario sobre la app (XCUITest) | minutos |

Framework: **Swift Testing** (`@Test` / `#expect`), el default de Xcode 26. Para E2E, XCUITest.

Un build en caliente tarda **~13 s**, así que correr los tests localmente es barato. Eso
condiciona las decisiones de más abajo.

## Los 11 bugs que ya salieron de leer el código

Leer el código para diseñar los tests encontró once defectos **sin ejecutar nada**. Cada uno
tiene su test asignado. La regla: el test se escribe **primero para documentar el comportamiento
actual**; si confirma el bug, se arregla en un commit separado del test.

| # | Bug | Test |
|---|---|---|
| 1 | **`StrengthSeed.templates(for:)` matchea `title.contains("b")`** → cualquier día con una "b" en cualquier parte recibe la rutina del **Día B**. ✅ **CONFIRMADO y alcanzable** (U-18): el título **lo edita el usuario** (`WorkoutEditView` lo expone en un `TextField`) y `populateIfNeeded` relee el título actual. Renombrar un día A a "Fuerza A · brazos" —o a cualquier cosa con una b— lo llena con la rutina del Día B. Con los títulos del plan funciona **de casualidad**: ninguno de Día A tiene una "b". **Pendiente de arreglar.** | U-18 ✅ |
| 2 | **`StreakCalculator.currentWeekStreak` agrupa por `weekTitle` (String), no por semana calendario** → dos semanas con el mismo título se fusionan; una semana partida en dos títulos cuenta doble. | U-32 |
| 3 | ~~**`GuidedSessionEngine`: con `restSeconds == 0`, `onStateChanged` nunca se emite al entrar en tiempo extra**~~ → **confirmado pero NO alcanzable.** El 0 no se puede producir hoy por ninguna ruta. Agujero de la lógica, no bug visible. Ver I-06. | I-06 ✅ |
| 4 | **Ráfaga de alertas al volver de background.** ✅ **CONFIRMADO** en I-07: vuelve con 35 s de tiempo extra → **4 vibraciones en <1 s**. Alcanzable a diario (el reloj apaga la pantalla y deja de tickear). **Pendiente de arreglar.** | I-07 ✅ |
| 5 | ~~**`skipRest()` no valida la fase**~~ → **confirmado pero NO alcanzable** (I-11). En `.logging` saltea una serie; en la última, **deja la sesión en un callejón sin salida**; en `.done`, lo deshace. Lo tapan las UIs (el botón vive en la vista de descanso) y la guarda de `apply(_:)`. | I-11 ✅ |
| 6 | ~~**`bringExerciseNext` no valida que el ejercicio pertenezca al día**~~ → **confirmado pero NO alcanzable** (I-14). Peor de lo anotado: no "reordena para nada" — le **reescribe el `order` al ejercicio ajeno**, dejando **dos ejercicios con el mismo `order` en el otro día**. Como `sorted` no es estable, ese día queda con orden indefinido. Lo contiene `switchableExercises`, que solo ofrece ejercicios del día. | I-14 ✅ |
| 7 | **`richness()` no cuenta `perceivedEffort`, `activeCalories` ni `ExerciseSet.isDone`** → un día donde el usuario solo tildó las series puntúa **0** y `cleanupKneeRecovery` **lo borra**. | I-30 |
| 8 | **`StrengthSeed` pisa `exercise.notes` del usuario**: la asignación está dentro del `if exercise.targetReps == nil`. | I-34 |
| 9 | **`hasLoggedData` mira `reps`/`weight` pero no `isDone`** → a un día donde el usuario solo tildó series, `populateIfNeeded` **le borra los ejercicios**. | I-35 |
| 10 | **Estado absorbente en el sembrado:** flag en 0 + días ya existentes (CloudKit bajó los registros antes que el KVS) → `seedIfNeeded` sale sin marcar versión → `applyPlanUpdates` también sale → **el plan no se actualiza nunca más**. | I-21 |
| 11 | **Crashes por parámetro negativo:** `WeeklyVolume.recentWeeks(-1)` y `StrengthProgress.recentImprovements(limit: -1)` → `fatalError` / precondition failure. Sin guard. | U-27, U-35 |
| **12** | 🆕 **Reabrir un día terminado reinicia la sesión.** ✅ **CONFIRMADO y alcanzable** (I-15). `firstIncompleteIndex` hace `firstIndex { … } ?? 0`: sin series pendientes devuelve **0**, indistinguible de "la primera está pendiente". El botón "Empezar sesión guiada" **no está gateado por `isCompleted`**, así que abrir un día ya entrenado te deja en la serie 1 con el botón de completar listo — y seguir el flujo arranca un descanso de 90 s y rehace la sesión. La fase `.done` solo la pone `finish()`, o sea que **vive en memoria y no sobrevive a cerrar la sesión**. Datos no se pierden. **Pendiente de arreglar** — ⚠️ **ojo con el fix**: ver la nota de abajo. | I-15 ✅ |

| **13** | 🆕 **Un "Anterior" que llega tarde resucita una sesión terminada.** ✅ **CONFIRMADO** (I-19). `apply(.goBack)` es el **único** comando sin guarda de fase: su `else if index > 0` se cumple igual en `.done`. La carrera es real: el espejo del iPhone dibuja "Anterior" en la fase de carga, y entre el toque y la llegada del comando al reloj hay un viaje de WatchConnectivity. Efecto: la sesión vuelve a `.logging`, el índice retrocede y **des-marca la anteúltima serie** (no la última), dejando el día **marcado como completo pero con un hueco**. Nadie lo devuelve a `.done`. **A diferencia de los bugs 3, 5 y 6, la UI no lo tapa** — la guarda que falta es precisamente contra la ventana en que la UI está vieja. **Pendiente de arreglar.** | I-19 ✅ |

| **14** | 🆕 **El espejo del iPhone cuenta una serie que no hiciste.** ✅ **CONFIRMADO y alcanzable** (I-11 → I-20). `loggedSetsCount` cuenta series **con datos** (`reps != nil \|\| weight != nil`), y el prellenado (I-17) ya le pone reps y peso a la serie actual. Al abrir la sesión, sin confirmar nada, `LiveSessionMirrorView` ya muestra **"1 series"**. `totalVolume` arrastra el mismo error (70 kg × 8 reps de una serie sin hacer). **En el resumen final los dos números son correctos** —ahí no queda ninguna prellenada de más— así que es un defecto del **espejo en vivo**, no del registro. Cosmético. | I-20 ✅ |

| **15** | 🆕 **El tonelaje semanal cuenta series que no hiciste.** ✅ **CONFIRMADO y alcanzable** (U-22). `WeeklyVolume.tonnage` **no filtra por `isDone`**: suma peso × reps de **todas** las series de la semana. Con el prellenado (I-17) poniendo peso y reps en la serie actual, **abrir la sesión guiada y no entrenar ya le suma volumen a la semana**. Hermano del bug 14, pero peor: el 14 es cosmético y en vivo; este **queda** en la tarjeta de tendencia. Asimétrico con los km, que sí filtran por `isCompleted` (U-24). **Pendiente de arreglar.** | U-22 ✅ |

Además, dos contradicciones entre el código y sus comentarios, que hay que resolver decidiendo
cuál gana: `applyPlanUpdates` dice "los días que el usuario borre no se vuelven a insertar" pero
compara por fecha (I-23), y `taperVariant` dice "sin el trabajo de pierna" pero solo saca
"Flexión de rodillas" (U-19).

> ❓ **Decisión pendiente (U-19), no es un fix obvio.** El taper saca `Flexión de rodillas` y deja
> **extensión de rodillas, aductores, peso muerto a una pierna y equilibrio en bosu**. Las dos
> lecturas son coherentes y llevan a arreglos opuestos:
> **(a)** si la intención era *descargar las piernas antes de la carrera*, el taper **no la
> cumple** y hay que sacar los otros cuatro; **(b)** si era *solo bajar el volumen*, el código
> está bien y **el comentario miente**. El test documenta lo que hace hoy. Falta que decidas.

> ⚠️ **Nota sobre el fix del bug 12 (hallada en I-16).** El reloj **sí quiere** reabrir días
> completos: `WatchWorkoutView` rotula el botón **"Repetir sesión"** cuando `day.isCompleted`.
> O sea que reabrir no es el bug — el bug es **cómo se reabre**. En el iPhone el botón dice
> "Empezar sesión guiada" pase lo que pase (no distingue), y en ninguna de las dos plataformas
> el engine **des-marca las series**: caés en la serie 1 ya tildada como hecha, con los pesos
> viejos. Un `phase = .done` al arrancar rompería el "Repetir sesión" del reloj. Lo que hace
> falta es distinguir **retomar** (ir a la primera pendiente) de **repetir** (limpiar los
> `isDone` y arrancar de cero), y que la UI diga cuál de las dos pidió.

## Lo que NO se puede automatizar

Hay que decirlo de entrada para no fingir cobertura que no existe. Necesitan hardware real y
quedan como **checklist manual** antes de cada release:

- Sync por CloudKit entre iPhone ↔ reloj ↔ Mac.
- Live Activity en pantalla bloqueada y Dynamic Island, con sus botones.
- Pulso en vivo (el simulador de watchOS no genera frecuencia cardíaca).
- Import desde Apple Salud (HealthKit no tiene datos en el simulador).
- Notificaciones locales de suplementos.
- Que el PDF *se vea bien* (que se genere y se comparta sí lo cubre E2E-09).

---

## Fase 0 — Prerequisitos

- [x] **P0-1 · Target de tests.** ✅ Hecho. `GymLogTests` (unit + integración, Swift Testing,
      `TEST_HOST` = `Maraton.app`, `@testable import Maraton`) y `GymLogUITests` (XCUITest). Ambos
      son `PBXFileSystemSynchronizedRootGroup`: **agregar un archivo `.swift` a la carpeta lo suma
      solo al target**, sin tocar el `.pbxproj`. También se versionó el scheme compartido
      (`xcshareddata/xcschemes/Maraton.xcscheme`) con los dos targets en su Test action, para que
      `xcodebuild test` sea reproducible en el CI.
      Correr todo: `xcodebuild test -scheme Maraton -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
      (~17 s). Solo unitarios: agregar `-only-testing:GymLogTests` (~13 s).

- [x] **P0-2 · Fechas deterministas.** ✅ Hecho. `PlanConstants.calendar` y los `DateFormatter` de
      `DateFormatting` usan la **TZ del dispositivo**, así que una fecha a medianoche puede caer en
      otro día según dónde corra el test. `TestSupport.swift` expone `date(2026, 7, 1)`, que
      construye la fecha **a mediodía**. **Usarla siempre**; no construir fechas a mano.

- [x] **P0-3 · Container en memoria.** ✅ Hecho (parcial). `AppData.makeContainer(inMemory: Bool = false)`
      devuelve un contenedor efímero, sin disco y sin CloudKit. Ojo: `ModelConfiguration` trae
      `cloudKitDatabase: .automatic` por defecto — sin el `.none` explícito, SwiftData intenta
      montar CloudKit **hasta sobre un store en memoria**.
      También se aisló el host: `MaratonApp.init()` detecta que está hosteando los tests unitarios
      (`AppData.isHostingUnitTests`) y arranca inerte — contenedor en memoria, sin sembrar y sin
      abrir el canal con el reloj. **Sin esto, cada corrida de tests escribía los flags de sembrado
      que los tests de seed necesitan controlar.** Los tests de UI no pasan por ahí: la app corre
      como proceso aparte y arranca normal.
      *Falta:* el `fatalError` de la rama no-in-memory sigue ahí (mataría el runner si alguien
      llamara `makeContainer()` sin `inMemory` desde un test).

      > ⚠️ **Trampa que ya nos costó una hora.** El `ModelContext` **no mantiene vivo** a su
      > `ModelContainer`. Un helper que cree el contenedor y devuelva solo `container.mainContext`
      > deja el contexto colgado apenas retorna → el test **crashea con `SIGTRAP`**, no falla. Y
      > como Swift Testing corre en paralelo, el crash **se lleva puesto al resto de los tests del
      > proceso**, que aparecen como fallados sin mensaje. Por eso `TestSupport` expone `TestDB`,
      > que guarda contenedor y contexto juntos: **guardalo en una variable del test.**

- [ ] **P0-4 · Flags de sembrado inyectables.** Los seeds leen y escriben **6 claves globales**
      (`seededPlanVersion`, `seededStrengthVersion`, `cleanedKneeRecoveryV1`, cada una en
      `UserDefaults.standard` **y** en `NSUbiquitousKeyValueStore.default`). Un test tendría que
      resetear las 6, y aun así el resultado dependería de si el bundle de tests tiene entitlement
      de iCloud: el KVS sin entitlement devuelve 0/false y **descarta escrituras en silencio**. Es
      una fábrica de flakes. Extraer `protocol SeedFlagStore` + una implementación en memoria.
      **Bloquea I-19..I-36.**

- [ ] **P0-5 · `AppData.iCloudSyncEnabled` es `static let`** (`Shared/AppData.swift:20`) → la rama
      "sin iCloud" de los seeds es inalcanzable desde un test. Pasarlo a `static var` o derivarlo
      del store de P0-4.

- [ ] **P0-6 · Reloj inyectable en el engine** *(mejora, no bloqueante)*. `startRest`, `adjustRest`
      y `makeSnapshot` usan `Date()` interno; `tickRest(now:)` **ya** recibe la fecha. Los tests del
      engine **se pueden escribir hoy** calculando `now` relativo a `engine.restEndDate!` — feo pero
      determinista. Inyectar un `var clock: () -> Date = Date.init` los deja mucho más legibles.
      Hacerlo cuando los tests del engine ya estén verdes, no antes.

- [ ] **P0-7 · `LiveSessionConnectivity.handle(_:)` es `private`**
      (`Shared/LiveSession/LiveSessionConnectivity.swift:107`). Adentro vive la regla de descarte
      de snapshots viejos, que es lógica pura y crítica para la sync reloj↔iPhone. Extraerla a
      `static func shouldAccept(_ new: LiveSessionSnapshot, over current: LiveSessionSnapshot?) -> Bool`.
      Es el refactor más barato del repo. **Bloquea I-37..I-39.**

Los protocolos para HealthKit, UNUserNotificationCenter, WCSession y HKWorkoutSession
(`HealthManager`, `NotificationManager`, `LiveActivityController`, `WatchWorkoutManager` — todos
singletons sin costura) **quedan para después**: no bloquean nada de lo que sigue.

---

## Fase 1 — Unit

Todo esto se escribe **sin refactorizar nada** salvo P0-1 (el target).

### Parseo de distancia (`PlannedDistance.parse`) — empezar por acá

La función más pura del repo y la que más casos raros tiene.

- [x] **U-01** `"Fondo largo 12 km"` → `12`. `"12,5 km"` → `12.5`. `"12.5km"` sin espacio → `12.5`. ✅
      (También `"0 km"` → `0`, que es un valor válido y no un "sin dato".)
- [x] **U-02** Rango → **promedio**: `"Fondo 13-14 km"` → `13.5`. Con en-dash (`13–14`) también. ✅
      El en-dash importa: es el que mete la sustitución automática de iOS al tipear. También con
      espacios alrededor del guion, con decimales, y un rango invertido (`14-13`) que promedia igual.
- [x] **U-03** Sin km → `nil`: `"Series 8x400 m"`, `"Descanso"`, `"Fuerza A"`. ✅
      Incluye los números que **no** son distancia (series, minutos, metros) y la ruta real por
      `WorkoutDay.plannedKm`: un día de fuerza o descanso no aporta km fantasma al volumen semanal.
- [x] **U-04** Case-insensitive: `"FONDO 10 KM"` → `10`. ✅
- [x] **U-05** ⚠️ Toma el **primer** match de `title + " " + detail`: `"Rodaje"` + `"5 km/h de
      viento, 10 km totales"` → `5`. Y `"1.000 km"` → `1.0`. ✅ **Ambos confirmados.**
      Ninguno muerde hoy —el plan siempre pone la distancia en el título y el ritmo en el detalle,
      y nadie planifica 1000 km en un día—, pero quedan escritos. El del separador de miles es
      irreparable sin cambiar el contrato: el regex acepta punto **y** coma como decimal, así que
      no puede distinguir `1.000` (mil, es-AR) de `1.000` (uno coma cero). Si algún día se formatean
      los km con separador de miles, esto los rompe.

### Formateo (`NumberFormatting`, `TimeFormatting`, `DateFormatting`)

- [x] **U-06** `Int.restLabel`: `45 → "45 s"`, `60 → "1 min"`, `90 → "1:30 min"`, `120 → "2 min"`. ✅
      La regla: no mostrar ceros que no aportan (un minuto justo no lleva `:00`), y el segundo con
      cero a la izquierda (si no, `"1:5 min"` se leería como uno coma cinco).
      Límite conocido, no bug: **no hay tramo de horas** — `3600 → "60 min"`. Irrelevante para un
      descanso; importaría si se reusa la función para otra duración.
- [x] **U-07** `Int.countdownLabel`: `90 → "1:30"`, `5 → "0:05"`. ✅ Siempre `m:ss`, sin caso
      especial para el 0: **la misma función formatea las dos mitades del descanso**, la que baja y
      la que sube (las tres vistas hacen `"+\(segundos.countdownLabel)"` en tiempo extra). Forma
      fija porque es un número que cambia cada segundo: si alternara de forma, saltaría de ancho.
      Acá el **no tener tramo de horas sí es alcanzable** —el tiempo extra no tiene techo (I-05)—
      pero solo crece el ancho del texto: `3600 → "60:00"`.
- [x] **U-08** ⚠️ Negativos: `(-30).restLabel` → `"-30 s"` (legible), `(-5).countdownLabel` →
      **`"0:-5"`** y `(-90)` → **`"-1:-30"`** (roto: Swift trunca hacia cero y el resto se lleva el
      signo, así que el `%02d` no rellena nada). ✅ **No alcanzable**: los cuatro valores que
      llegan a estas funciones están recortados **en origen** — `restRemaining` toca fondo en 0,
      `restOvertime` nace en 0 y crece, `restTotal` no baja de 15 (I-08), y el espejo hace
      `max(0, …)` sobre el tiempo extra que calcula solo.
      ⚠️ **La garantía vive en los cuatro que llaman, no en la función.** Un call site nuevo que se
      olvide del clamp pinta `"0:-5"` en la muñeca.
      `restRemaining` es `Int` — fijar qué se espera.
- [x] **U-09** `Double.formattedKm` / `.formattedKg`: coma decimal, un decimal, sin `,0` colgando,
      cero y negativos. ✅ `formattedKg` **es** `formattedKm` (cambiar uno cambia el otro).
      Dos cosas no obvias: los **miles se separan con punto** (`3.200 kg` — pasa siempre en el
      resumen de una sesión de fuerza), y ese `"1.000"` **no vuelve a entrar** por
      `PlannedDistance.parse`, que lo leería como `1,0` (U-05): formatear y re-parsear no es una
      ida y vuelta segura. Hoy ninguna ruta lo hace.
      El locale está **fijado a `es_AR`** a mano: un teléfono en inglés igual ve `12,5`. Decisión,
      no bug.
- [x] **U-10** `Double.formattedPace`: `330 → "5'30\"/km"`; redondea (no trunca) los segundos
      fraccionarios, que es lo normal porque el ritmo sale de una división. ✅
      El `km > 0` de `paceSecondsPerKm` es lo que evita el `inf`: **sin ese guard,
      `Int(inf.rounded())` crashea**. Testeado.
      ⚠️ Pero **no exige `minutes > 0`**: un día con km y duración 0 (importación de HealthKit de
      una corrida de menos de un minuto, o carga manual) da ritmo 0 → `"0'00\"/km"` en el detalle
      y en el export. No rompe; miente menos que un guion. Alcanzable.
      Sin tramo de horas, igual que U-07: `3700 → "61'40\"/km"`.
- [x] **U-11** `Date.dayMonth` / `.weekdayAndDay` / `.longDate` (+ `.weekdayDayMonth`,
      `.weekdayName`) en es-AR. ✅ Comparados contra un `DateFormatter` construido en el test, **no**
      contra literales: si iCU cambia las abreviaturas cambian los dos lados y el test sigue
      diciendo lo que quiere decir.
      La capitalización **es deliberada, no despareja**: las tres que encabezan una tarjeta llevan
      mayúscula inicial (el español no capitaliza días ni meses, por eso el `capitalizedFirst` a
      mano), pero `weekdayName` va en minúscula **a propósito** porque se mete dentro de una frase
      ("entrenás el jueves"). Emparejarlas rompe las frases.
      Locale clavado en `es_AR`, igual que U-09. Y queda fijado que `date()` construye **al
      mediodía**: los formateadores no fijan `timeZone`, así que el mediodía es lo que evita que
      una zona horaria corra la fecha de día. De eso dependen todos los tests con fechas.

### Serialización de la sesión en vivo (`Shared/LiveSession/LiveSessionState.swift`)

La fruta madura: importa **solo Foundation**, todo es `Codable` + `Equatable`, y `LiveSessionWire`
ya encapsula el encode/decode. Cero refactor, y protege el contrato reloj↔iPhone, que hoy no tiene
ninguna red.

- [x] **U-12** Round-trip de un `LiveSessionSnapshot` completo. ✅
- [x] **U-13** Round-trip con todos los opcionales en `nil`. ✅
- [x] **U-14** Round-trip de `LiveSessionAction.adjustRest(±15)` — el caso con valor asociado, el
      más frágil ante un rename. Y cada `case` restante. ✅
- [x] **U-15** `LiveSessionWire.payload(for:)` → `snapshot(from:)` devuelve un snapshot igual. ✅
      (También el comando, y que cada decodificador solo entienda su propia clave.)
- [x] **U-16** `snapshot(from:)` con `Data` corrupta o sin la clave → `nil`. **Documenta un fallo
      silencioso**: hoy usa `try?`, así que un payload de otra versión del schema se descarta sin
      log. ✅ **Confirmado.** Un JSON válido al que le falte un campo requerido —exactamente lo que
      mandaría un reloj con una versión vieja de la app— hace que **se pierda el snapshot entero,
      sin ninguna pista**. La sesión en vivo simplemente no aparece. El comportamiento actual
      (devolver `nil` en vez de crashear) está bien; lo que falta es **logging** o una **versión en
      el payload**. Pendiente de decidir: no es un bug de corrección, es de diagnosticabilidad.
- [x] **U-17** Fidelidad de las `Date` en el round-trip. Blinda contra que alguien cambie la
      estrategia de encoding de un solo lado — el encoder y el decoder son dos instancias distintas. ✅
      Incluye precisión de subsegundo en `restEndDate` (de la que depende el cronómetro) y un canario
      que falla si el wire empezara a aceptar fechas ISO-8601.

### Plantillas de fuerza (`Shared/StrengthSeed.swift`)

- [x] **U-18** ⚠️ **Bug 1 — CONFIRMADO y alcanzable.** ✅ `templates(for:)` elige la rutina con
      `title.contains("b")`, que no busca "el Día B" sino **la letra b en cualquier lugar**.
      Alcanzable porque el título **lo edita el usuario** y `populateIfNeeded` relee el actual:
      renombrar un día A a `"Fuerza A · brazos"`, `"Gimnasio básico"` o `"Hombros y abdominales"`
      lo llena con la rutina del **Día B** — otros ejercicios, otras series.
      Con los títulos del plan anda **de casualidad**: ninguno de Día A tiene una "b".
      Y `"liviana"` solo le gana a la `"b"` porque su `if` va **primero** — probado con
      `"Fuerza liviana (banco)"`, que tiene las dos. Reordenar los `if` cambiaría la rutina.
      El arreglo natural: un campo explícito en el día (un `enum` de rutina), no adivinar del texto.
      **Pendiente de arreglar.**
- [x] **U-19** ⚠️ Un día "liviana" → `taperVariant`. ✅ Las series se parten al medio **redondeando
      hacia arriba** (3 → 2, no 1: hacia abajo dejaría de ser un entrenamiento) y `max(1, …)`
      garantiza al menos una serie. Tres hallazgos:
      **(a) La contradicción es real** (ver abajo): dice "sin pierna" y solo saca `Flexión de
      rodillas`. Quedan aductores, extensión de rodillas, peso muerto a una pierna y equilibrio.
      **Necesita una decisión tuya**, no un fix obvio.
      **(b) ⚠️ La nota del taper pisa la original**, que era la que explicaba el **circuito**
      ("3 vueltas, sin pausa"). El usuario deja de ver esa instrucción. La rama que preservaba la
      nota (`sets == 0`) es **código muerto**: ninguna plantilla tiene 0 series.
      **(c) 🧨 Mina:** `taperVariant` reconstruye los templates **sin pasar `weighted`** (default
      `true`), así que en la copia hasta el core figura "con peso". Hoy es inofensivo porque
      `insert()` no lee ese flag y `tracksWeight` resuelve **por nombre** contra las listas
      originales. El día que alguien haga que `insert()` use `template.weighted` —lo natural—, el
      día de taper va a pedir kilos para el puente lateral y el equilibrio en bosu.
- [x] **U-20** Semana de pico (15-21/6) y taper (29/6-5/7): se filtran los ejercicios de salto. ✅
      Los dos bordes son inclusivos y la comparación va por `startOfDay` (la hora no influye).
      Saca exactamente el salto y nada más. Es un filtro **independiente del título**: en el día de
      taper del 1/7 se combinan los dos (mitad de series **y** sin salto) sin pisarse.
      ⚠️ **Las ventanas están clavadas a 2026 y ya pasaron.** Eran el pico y el taper de la carrera
      del 5/7/2026. Para cualquier día de hoy en adelante el filtro **nunca** se activa, y en 2027
      tampoco (el año está en la constante). No es un bug —nadie espera hoy que se saquen los
      saltos— pero es **código muerto esperando un evento que no vuelve**. Si el taper hace falta
      otra vez, hay que rehacerlo **relativo a una fecha objetivo**. Va con la deuda de HANDOFF
      ("el plan se quedó sin días" el 5/7/2026).
      Bordes exactos: 14/6 no, 15/6 sí, 21/6 sí, 22/6 no, 28/6 no, 29/6 sí, 5/7 sí, 6/7 no.
- [x] **U-21** `tracksWeight`: los 12 de peso corporal / banda / core / equilibrio / salto →
      `false`. Los desconocidos (los que agrega el usuario a mano) → `true`, que es la apuesta
      correcta: un campo de kilos de más se ignora; al revés, no tendría dónde anotar la carga. ✅
      La lista **se deriva de las plantillas** (`dayA + dayB` con `weighted: false`), así que no hay
      una segunda lista que mantener sincronizada — y es lo que hoy hace inofensiva la mina de U-19.
      ⚠️ **El match es exacto** (`Set<String>.contains`, sin trim ni case-insensitive):
      `"puente lateral"`, `"Puente lateral "` o `"Puente Lateral"` pasan a **"con peso"**.
      Alcanzable renombrando un ejercicio. Misma raíz que el bug 1: **se deduce del texto lo que
      debería ser un dato** — `ExerciseTemplate.weighted` existe, pero no se persiste en el
      `Exercise`, así que hay que reconstruirlo por nombre.

### Volumen (`Maraton/Models/WeeklyVolume.swift`)

- [x] **U-22** `tonnage` = Σ (peso × reps). Las series sin peso o sin reps **no suman** (core,
      plancha, o una serie cargada a medias). Peso 0 **sí** entra y aporta 0 — no es `nil`. Filtra
      por semana **calendario** (`toGranularity: .weekOfYear`), no por "hace 7 días". ✅
      ⚠️ **Bug 15 (nuevo):** no filtra por `isDone`. Ver la tabla de bugs.
- [x] **U-23** `tonnage` con lista vacía → 0. ✅ También: un ejercicio **sin series** (el core del
      plan) suma 0, y una semana sin gimnasio da 0 **sin contagiar** a las de al lado.
      No es un caso de borde: el cero es lo que ve la mayoría de las semanas. `reduce(0, +)` hace
      lo correcto sin caso especial — para una barra de volumen, "cero kilos" y "sin datos" son lo
      mismo.
- [ ] **U-24** `actualKm` suma solo días completados. ⚠️ Asimétrico con `plannedKm`, que no filtra.
- [ ] **U-25** `recentWeeks(6)`: devuelve 6, de la más vieja a la más nueva, la última contiene
      `today`.
- [ ] **U-26** `recentWeeks` sin datos → 6 semanas en cero (es el caso que dibuja la tarjeta vacía).
- [ ] **U-27** ⚠️ **Bug 11.** `recentWeeks(0)` → `[]`, pero `recentWeeks(-1)` → **crash**.
- [ ] **U-28** La semana arranca el **lunes**. Test con un domingo y el lunes siguiente.
- [ ] **U-29** Cruce de año (semana del 29/12 al 4/1).

### Racha (`StreakCalculator`)

- [ ] **U-30** `currentWeekStreak` cuenta semanas consecutivas con al menos un día completado.
- [ ] **U-31** Una semana en curso sin completar **no corta** la racha (se cuenta desde la última
      semana activa hacia atrás).
- [ ] **U-32** ⚠️ **Bug 2.** Agrupa por `weekTitle` (String), no por semana calendario. Test con
      dos semanas del mismo título.
- [ ] **U-33** `currentDayStreak`: los días de descanso intercalados no cortan ni suman; hoy
      pendiente no corta; ayer pendiente sí.

### Fuerza e historial

- [ ] **U-34** `StrengthProgress.recentImprovements` detecta una subida de peso; ignora ejercicios
      con menos de 2 sesiones con datos.
- [ ] **U-35** ⚠️ **Bug 11.** `limit: 0` → `[]`, pero `limit: -1` → **crash**. Y ⚠️ `percentChange`
      **puede ser negativo** — el tipo se llama "improvement" pero incluye retrocesos: fijar el
      contrato.
- [ ] **U-36** `ExerciseHistory.lastWeight` = el **mayor** peso de la última sesión anterior con
      datos. Ignora el día actual (comparación con `<` estricto).
- [ ] **U-37** ⚠️ **Asimetría:** `lastWeight` sigue buscando hacia atrás si la última sesión no
      tiene ningún peso, pero `lastSession` solo mira la primera con datos. Y ambas tienen
      `fetchLimit = 10`: con más de 10 registros previos sin datos, se pierde el histórico.

### Suplementos, tipos y reporte

- [ ] **U-38** `SupplementTracker.adherence`: fracción en la ventana; `days <= 0` → 0 (protegido);
      logs duplicados el mismo día cuentan una vez; logs futuros no cuentan.
- [ ] **U-39** `SupplementTracker.currentStreak`: solo hoy → 1; solo ayer (hoy no) → 1 (**el día en
      curso no corta la racha**); un hueco corta.
- [ ] **U-40** `WorkoutDay.dailyStatus`: un día de descanso marcado como completado igual devuelve
      `.rest`. Y `objective` con `detail` vacío.
- [ ] **U-41** `WeekAssigner.weekInfo`: hereda el título si hay un día de esa semana; si no, crea
      `"Semana del …"` con `order = max + 1`. Con `days` vacío → `order = 1`.
- [ ] **U-42** `ProgressReportBuilder.build` con `days` vacío → `periodStart = today`,
      `completionRate = 0`, `avgPace = nil`, sin crash. (Es `static`, puro, con `today` inyectable
      y `HealthSnapshot()` sirve de stub — el mejor test de integración de lógica pura del repo.)
- [ ] **U-43** `ProgressReportBuilder`: una corrida con km pero **sin duración** cuenta en el total
      de km pero **no** en el ritmo promedio. Y `avgPace` es ponderado por distancia.
- [ ] **U-44** `ProgressReportBuilder`: `completionRate` con 0 días de entrenamiento → 0 (división
      protegida).

---

## Fase 2 — Integración

Container SwiftData en memoria.

### La máquina de estados de la sesión guiada

El corazón de la app, hoy sin una sola prueba. Y la buena noticia: **es testeable tal como está,
sin refactor**. Importa solo Foundation + SwiftData; el `ModelContext` es **opcional** (sin él el
engine funciona entero en memoria, solo no persiste ni consulta historial); y sus cuatro efectos
externos ya están inyectados como closures (`onRestAlert`, `onStateChanged`, `onRestStarted`,
`onRestEnded`) → **se espían con contadores, sin mocks**. `tickRest(now:)` recibe la fecha, así que
el cronómetro se simula sin esperar tiempo real. Es el mayor retorno del repo.

- [x] **I-01** `start(day:)` arma los pasos (ejercicios × series) y arranca en `.logging` sobre la
      primera serie incompleta. ✅ También: el core (sin series) ocupa un paso, y `start` es
      idempotente — la vista llama `prepare` en el init y `start` en el `onAppear`, así que rearmar
      los pasos perdería el progreso de la sesión en curso.
- [x] **I-02** `completeCurrent` → `.resting` con el descanso del ejercicio. En la última serie →
      `.done`. ✅ El descanso sale de **cada ejercicio** (press 90 s, remo 60 s), terminar marca el
      día como completado, y la última serie no abre un descanso que nadie va a consumir.
- [x] **I-03** Un paso **sin series** (core) → `completeCurrent` **saltea el descanso** y avanza
      directo. ✅ **Falsa alarma aclarada:** el paso de core nunca queda marcado como hecho
      (`step.set?.isDone` es un no-op sin serie). Parece un bug, pero no lo es: `firstIncompleteIndex`
      solo mira pasos **con** serie, así que al retomar la sesión el core se saltea igual y no
      bloquea nada. Queda escrito para que nadie lo "arregle" de más.
- [x] **I-04** `skipRest` → `.logging` de la serie siguiente. ✅ Avanzar limpia el `restEndDate` (si
      sobreviviera, el iPhone seguiría dibujando una cuenta regresiva sobre una serie que ya no
      descansa), y `skipRest` es también la salida del tiempo extra ("Empezar serie").
- [x] **I-05** **Regla clave:** cuando el descanso llega a cero, el engine **no avanza solo** —
      entra en tiempo extra y espera confirmación. Es la decisión de diseño más importante del
      engine y hoy solo la sostiene un comentario. ✅ **Ya no.** 120 ticks seguidos pasado el
      vencimiento no mueven la sesión ni un paso; solo `skipRest` avanza. Si avanzara solo, el reloj
      daría por empezada una serie que el usuario todavía no arrancó, y las reps y el peso quedarían
      asignados al momento equivocado.
- [x] **I-06** ⚠️ **Bug 3 — confirmado, pero NO alcanzable.** ✅ Con `restSeconds == 0`,
      `onStateChanged` nunca se emite al entrar en tiempo extra (`enteringOvertime = restRemaining > 0`
      no se cumple si ya arrancó en 0), así que el iPhone y la Live Activity no pintan el rojo.
      **Corrección de severidad:** el 0 **no es alcanzable hoy** — las plantillas usan 30-120 s,
      `adjustRest` clampea el total a un mínimo de 15, y ninguna vista escribe `restSeconds = 0`. Es
      un agujero de la lógica del engine, no un bug que el usuario pueda ver. El test queda como
      guardia: el día que se agregue una plantilla sin descanso (una superserie), se vuelve real.
      También queda fijado el caso normal: el cruce a tiempo extra avisa **exactamente una vez**, y
      los ticks con descanso restante **no** avisan (inundar WatchConnectivity con un snapshot por
      tick sería carísimo; la cuenta regresiva la dibuja cada cliente desde `restEndDate`).
- [x] **I-07** ⚠️ **Bug 4 — CONFIRMADO y alcanzable.** ✅ Volver de background con 35 s de tiempo
      extra encima dispara **4 vibraciones en menos de un segundo**, en vez de una.
      **Causa:** `tickRest` avisa si `restOvertime >= nextOvertimeAlert` y después hace
      `nextOvertimeAlert += 10`. El `+=` asume ticks seguidos: sube de a 10 por vez. Si la app
      estuvo suspendida, el contador arranca en 0 y tiene que **remontar** — y cada tick del remonte
      dispara su propia vibración.
      **Alcanzable todos los días:** bajás la muñeca, el reloj apaga la pantalla y deja de tickear.
      **Fix propuesto:** saltar `nextOvertimeAlert` al próximo múltiplo de 10 por encima del
      `restOvertime` actual, en vez de incrementarlo de a 10. **Pendiente de aplicar** (commit aparte).
- [x] **I-08** `adjustRest(±15)` mueve `restEndDate`, no lo deja en negativo, y **persiste
      `exercise.restSeconds`** (ojo: cambia la preferencia del ejercicio, no solo este descanso). ✅
      Confirmado que el ajuste **queda recordado**: la serie siguiente del mismo ejercicio ya arranca
      con el descanso nuevo. Es deliberado ("lo aprende"), pero implica que **no hay forma de alargar
      un descanso solo por esta vez**. Decisión de producto, no bug.
      Los dos clamps son distintos a propósito: el remanente baja a **1 s** (el descanso se corta ya)
      pero el total recordado no baja de **15 s** (para no dejar al ejercicio con un descanso
      inservible). Efecto colateral: el anillo de la UI queda casi vacío (`restFraction` = 1/15).
- [x] **I-09** `goBackFromLogging` vuelve atrás y **des-marca** la serie. En `index == 0` es no-op
      **y no emite `onStateChanged`** (el iPhone no recibe eco). ✅
      Des-marcar es lo que importa: si la serie siguiera marcada, al retomar la sesión el engine la
      saltearía y perderías la corrección. El no-op silencioso en el índice 0 **no es un bug** (el
      estado no cambió, no hay nada que difundir), pero implica que la Live Activity no puede
      distinguir "no llegó el comando" de "llegó y era no-op".
- [x] **I-10** `goBackFromResting` **no avanza el índice** (la serie a corregir es la actual) y
      **deja la serie marcada** —asimetría deliberada con I-09: la serie se hizo, lo que se corrige
      son sus números. ✅
      ⚠️ Confirmado: deja `restTotal`/`restRemaining`/`restOvertime` con basura del descanso
      anterior. **Hoy es inofensiva**: `makeSnapshot` deriva `restEndDate` e `isOvertime` de la
      fase, no de los contadores, y `startRest` los reinicia en el próximo descanso (incluido el
      umbral del aviso). El único que viaja crudo al snapshot es `restTotal`. Queda como deuda:
      si alguien lo usa suelto, va a leer los segundos de un descanso que ya no existe.
- [x] **I-11** ⚠️ **Bug 5 — confirmado, pero NO alcanzable.** ✅ `skipRest()` no valida la fase
      (es `onRestEnded` + `advance()`). Los tres daños, en orden de gravedad:
      en `.logging` se saltea una serie sin registrarla; en la **última** serie el índice se va
      fuera del arreglo y la sesión queda en un **callejón sin salida** (`currentStep == nil`,
      fase `.logging`, `finish()` nunca corre, `completeCurrent` es no-op — la única salida es
      volver atrás); en `.done` **deshace el `.done`** y cae en el mismo callejón.
      **No es alcanzable**: las tres UIs solo muestran el botón dentro de la vista de descanso y
      `apply(.skipRest)` valida `phase == .resting`. Esa guarda es lo único que lo separa de ser
      un bug real. Los tests quedan de guardia para el día que aparezca un call site nuevo.
- [x] **I-12** `bringExerciseNext` reordena los `Exercise.order` (0..n, persistidos: sobreviven a
      rearmar la sesión) y **preserva lo ya registrado**. ✅
      La parte que importa: `buildSteps` rearma los pasos desde cero, así que el engine tiene que
      **reencontrar** al usuario en su serie. Lo hace buscando la misma `ExerciseSet` **por
      identidad**, no por índice — si fuera por índice, reordenar te movería de serie.
- [x] **I-13** `bringExerciseNext` sobre el ejercicio actual → no-op silencioso (sale por el
      `guard` **antes** de tocar los `order`; además `switchableExercises` ni lo ofrece). Durante
      `.resting` reubica el índice, **no cambia la fase y no toca el cronómetro**: misma
      `restEndDate`, sin `onRestEnded` ni `onRestStarted`. ✅
      Es el momento real de uso —elegís el próximo ejercicio *mientras* descansás— así que cortar
      o reiniciar el descanso ahí sería el peor efecto posible. Lo único que cambia es el "Sigue".
- [x] **I-14** ⚠️ **Bug 6 — confirmado, pero NO alcanzable.** ✅ El daño **no queda en la sesión en
      curso** (`buildSteps` lee de `day.exercises`: el intruso ni aparece, el usuario no ve nada
      raro) — queda **en el otro día**, esperando: le reescribe el `order` al ejercicio ajeno y lo
      deja **empatado con otro** de su propio día (`[0, 1, 1]`). `sorted` no garantiza estabilidad,
      así que ese día pasa a tener orden indefinido. De paso, deja huecos en el orden del día
      actual (`[0, 2, 3]`). Lo contiene la UI: los dos call sites recorren `switchableExercises`.
      El `guard` que falta es `day.orderedExercises.contains { $0 === exercise }`.
- [x] **I-15** ⚠️ **Bug 12 (nuevo) — CONFIRMADO y alcanzable.** ✅ Retomar a medias funciona bien:
      cae en la primera serie incompleta, incluso si el hueco está en el medio (`firstIndex`, no
      `lastIndex`). Pero **con todas las series hechas devuelve 0** y reabre la sesión en la serie
      1, en `.logging`, sobre un día completo. Alcanzable: "Empezar sesión guiada" no mira
      `isCompleted`. Seguir el flujo arranca un descanso de 90 s y rehace la sesión entera.
      La raíz: `.done` solo lo pone `finish()`, así que **la fase no se deriva del estado del día**
      y no sobrevive a cerrar la sesión. **Pendiente de arreglar.**
- [x] **I-16** **Día sin ejercicios — confirmado, pero NO alcanzable.** ✅ `steps == []`,
      `currentStep == nil`, y `isLastStep` da **`true`** (`0 >= -1`): el engine cree estar en el
      último paso de una lista vacía. Pero `completeCurrent` sale por su `guard let step`, así que
      `finish()` nunca corre y **la sesión no llega nunca a `.done`** ni marca el día.
      El contraste que aísla la causa: un día con **solo un ejercicio de core** (sin series) sí
      termina — la diferencia no es "tener series", es **"tener pasos"**.
      Lo gatean las dos apps (`day.orderedExercises.isEmpty` → `emptyState` en iPhone, "Sin
      ejercicios cargados" en el reloj).
- [x] **I-17** `prefillCurrentSet` aplica reps objetivo (`"6-8"` → **8**, el máximo: es la meta, y
      la rueda solo se baja si no se llegó) + peso sugerido, y **nunca pisa** lo que el usuario ya
      cargó. ✅ Sin `targetReps` no inventa un número. Los de peso corporal no reciben peso.
      Corre también en `advance()`, no solo al arrancar: por eso la serie siguiente llega con el
      **último** peso cargado y la sesión es un tap por serie. El peso **no cruza de un ejercicio
      a otro** — un número plausible y equivocado sería peor que no prellenar.
- [x] **I-18** `suggestedWeight` prefiere el peso de la serie previa **de esta sesión** por sobre el
      historial. ✅ Correcto: si hoy subiste de 70 a 80, la serie que viene arranca en 80 — con la
      preferencia al revés, cada serie te haría bajar el peso que acabás de subir.
      El historial mira solo hacia atrás (`dayDate < currentDate`) y saltea las sesiones sin peso.
      Dos cosas para tener presentes, ninguna es bug: del historial toma el **máximo** de esa
      sesión, no el último peso (decisión de producto: el máximo es tu tope, el último puede ser
      una descarga — efecto: la sugerencia **no baja** si aflojás el final); y `fetchLimit = 10`
      hace que si las **10** sesiones más recientes del ejercicio no tienen peso, la sugerencia
      desaparezca **sin explicación**.
- [x] **I-19** ⚠️ **Bug 13 (nuevo) — CONFIRMADO, y este NO lo tapa la UI.** ✅ `apply(_:)` produce la
      misma transición que el método directo (test espejo: dos engines, uno por métodos y otro solo
      por comandos) e ignora los de otro `sessionID`. `completeCurrent` y `skipRest` **sí** se
      protegen de un snapshot viejo; `.end` es idempotente y **cerrar no es completar** (el día
      queda sin marcar). Pero `apply(.goBack)` **no valida la fase**: desde `.done` resucita la
      sesión, retrocede el índice y **des-marca la anteúltima serie**, dejando el día completo con
      un hueco. **Pendiente de arreglar.**
- [x] **I-20** `makeSnapshot` refleja paso, fase, índice, progreso y pulso (inyectado: el engine no
      conoce HealthKit); `restEndDate` e `isOvertime` solo en `.resting`; `isBodyweight`/`isTimeBased`
      viajan bien (deciden qué ruedas dibuja el otro lado). Round-trip por `LiveSessionWire` con un
      snapshot **real** de una sesión en curso — cierra el lazo engine ↔ serialización. ✅
      ⚠️ **Bug 14 confirmado acá** (venía de I-11): `loggedSetsCount` y `totalVolume` cuentan la
      serie **prellenada y sin confirmar**. `progressFraction` sí está bien (deriva del índice).

### Seeds y migraciones *(requieren P0-3, P0-4, P0-5)*

- [ ] **I-21** ⚠️ **Bug 10.** Estado absorbente: flag en 0 + días existentes → `seedIfNeeded` sale
      sin marcar versión → el plan no se actualiza nunca más.
- [ ] **I-22** `seedIfNeeded` siembra en DB vacía, marca la versión, y es idempotente.
- [ ] **I-23** ⚠️ **Contradicción.** `applyPlanUpdates` inserta solo fechas faltantes y no toca los
      existentes — pero el comentario dice "los días que el usuario borre no se vuelven a insertar"
      y **compara por fecha**: si sube `planVersion`, el día borrado **reaparece**.
- [ ] **I-24** `deduplicateDays` conserva el día con más datos del usuario, y es idempotente.
- [ ] **I-25** ⚠️ Con dos días de igual "riqueza", el ganador debe ser estable. Hoy desempata por
      `String(describing: persistentModelID)`, que en un container en memoria **no tiene orden
      garantizado** — si el test sale flaky, ese **es** el hallazgo.
- [ ] **I-26** El borrado arrastra en cascada `Exercise` y `ExerciseSet`: no quedan huérfanos.
- [ ] **I-27** `cleanupKneeRecoveryIfNeeded` borra los días vacíos del rango 24/6→5/7 y **preserva**
      los que tienen datos, incluida la carrera del 5/7.
- [ ] **I-28** ⚠️ **Bug 7.** `richness()` no cuenta `perceivedEffort`, `activeCalories` ni
      `isDone` → un día donde el usuario solo tildó las series **se borra**.
- [ ] **I-29** `populateIfNeeded` llena los días de fuerza vacíos del 9/6 en adelante y **no toca**
      los anteriores.
- [ ] **I-30** ⚠️ **Bug 8.** No debe pisar `exercise.notes` del usuario.
- [ ] **I-31** ⚠️ **Bug 9.** No debe borrar los ejercicios de un día donde el usuario solo tildó
      series (`isDone` sin reps/peso).
- [ ] **I-32** **Invariante global:** después de `AppData.seed` completo (seed → updates → strength
      → dedup → cleanup), **no hay ninguna fecha duplicada**. Es la unicidad que CloudKit no puede
      garantizar y que hoy sostiene el código a mano.

### Conectividad *(requiere P0-7)*

- [ ] **I-33** `shouldAccept` descarta un snapshot con `updatedAt` menor o igual al actual del mismo
      `sessionID`, y acepta uno de otro `sessionID`.
- [ ] **I-34** `handle(_:)` dispara `onSnapshot` / `onCommand` según el payload.
- [ ] **I-35** Política de entrega: reachable → `sendMessage`; no reachable → `transferUserInfo`;
      los snapshots además siempre van por `updateApplicationContext`, los comandos no. *(Requiere
      protocolizar `WCSession` — opcional, se puede diferir.)*

---

## Fase 3 — E2E (XCUITest)

Pocos y gordos: son los más lentos y frágiles, así que solo los caminos que, si se rompen, hacen la
app inusable.

- [ ] **E2E-01** Primer arranque: la app siembra el plan y muestra el día de hoy.
- [ ] **E2E-02** Navegar el carrusel de días y saltar con la tira de la semana.
- [ ] **E2E-03** **El recorrido principal:** sesión guiada — cargar peso y reps con la rueda,
      "Hecho", entra en descanso, saltear, avanza a la serie siguiente.
- [ ] **E2E-04** Completar una sesión entera → el día queda marcado como completado.
- [ ] **E2E-05** Cambiar el próximo ejercicio a mitad de sesión.
- [ ] **E2E-06** Marcar un suplemento y verlo reflejado en Progreso.
- [ ] **E2E-07** Crear, editar y borrar un día en la tab Plan.
- [ ] **E2E-08** Completar una corrida (km + minutos) y ver el ritmo calculado.
- [ ] **E2E-09** Generar el reporte PDF → aparece la hoja de compartir.
- [ ] **E2E-10** Exportar el plan a PDF → aparece la hoja de compartir.

Los E2E necesitan que la app arranque con una base **determinística**. Agregar un launch argument
(`-uitesting`) que fuerce container en memoria + plan sembrado fijo. Sin eso, los tests dependen de
lo que haya quedado en el simulador y salen flaky.

---

## Cuándo corre cada cosa

| Gate | Qué corre | Tiempo | Bloquea |
|---|---|---|---|
| **pre-commit** (hook) | Escaneo de datos personales y secretos | < 2 s | el commit |
| **pre-push** (hook) | Unit + Integración | ~40 s | el push |
| **CI** (push a `main` + PRs) | Build iOS + watchOS + Catalyst, Unit + Integración + E2E | ~10-15 min | el merge |

**El pre-commit no corre tests.** Commitear tiene que ser barato: si tarda 20 segundos, uno empieza
a usar `--no-verify` y el hook deja de servir. Lo que sí corre es el escaneo de datos personales —
que en este repo **ya no es hipotético**: el HANDOFF tenía el email y los UDIDs de los dispositivos,
y hubo que reescribir el historial para sacarlos. El hook existe para que no vuelva a pasar.

**El pre-push corre la pirámide rápida.** Es el gate real: 40 segundos antes de publicar es un
precio razonable y ataja casi todas las regresiones sin esperar al CI.

**El CI corre todo.** Ahora que el repo es público, los runners macOS de GitHub Actions son gratis
(en repos privados consumen minutos a 10×, lo que habría cambiado el cálculo). Compila **los tres
targets** — importante, porque el reloj y la extensión **no** se compilan al correr los tests del
target iOS, y es fácil romperlos sin enterarse.

⚠️ **A verificar al armar el CI:** el proyecto exige **iOS 26.5 / watchOS 26.5** (Xcode 26.6). Hay
que confirmar que la imagen de runner de GitHub trae un Xcode 26.x. Si no, el CI queda bloqueado
hasta que actualicen la imagen y la alternativa es un runner self-hosted en la Mac.

**Antes de cada release:** la checklist manual (CloudKit, Live Activity, pulso, HealthKit,
notificaciones). Nada de eso lo cubre el CI.

---

## Cómo escribir un test

El andamio ya está. `GymLogTests/TestSupport.swift` da:

- **`TestDB()`** — base SwiftData en memoria, aislada por test. Guardala en una variable (ver la
  trampa del `SIGTRAP` en P0-3).
- **`date(2026, 7, 1)`** — fecha determinística, a mediodía.
- **`makeDay(...)`** y **`makeExercise(...)`** — constructores de modelos con defaults razonables.

Agregar un archivo `.swift` a `GymLogTests/` alcanza: el target lo toma solo.

```swift
@Suite("Volumen semanal")
struct WeeklyVolumeTests {
    @Test("El tonelaje ignora las series sin peso")
    func tonnageIgnoresBodyweightSets() {
        let db = TestDB()
        let day = makeDay(date(2026, 7, 1), in: db.context)
        makeExercise("Plancha", on: day, sets: [(nil, nil)], in: db.context)
        makeExercise("Press", on: day, sets: [(50, 10)], in: db.context)

        #expect(WeeklyVolume.tonnage(for: date(2026, 7, 1), among: day.orderedExercises) == 500)
    }
}
```

## Orden de ataque

No es el orden de la pirámide:

1. ~~**P0-1** (target de tests)~~ ✅ hecho, junto con ~~P0-2~~ y ~~P0-3~~.
2. **U-12..U-17** (serialización) — cero refactor, y es lo único que protege el contrato
   reloj↔iPhone.
3. **U-01..U-05** (`PlannedDistance.parse`) — la función más pura y con más casos raros.
4. **I-01..I-20** (el engine) — **cero refactor**, es el corazón de la app, y ahí están los bugs
   3, 4, 5 y 6. No esperar a P0-6.
5. **Resto de la Fase 1** — cero refactor, valor inmediato.
6. **P0-3..P0-5** (los refactors de persistencia) → **I-21..I-32** — acá salen los bugs 7, 8, 9 y 10.
7. **P0-7** → **I-33..I-35** (conectividad). **P0-6** cuando el engine ya esté verde.
8. **Fase 3** (E2E) — al final, cuando lo de abajo ya no se mueve.

Los pasos 2, 3 y 4 **no requieren tocar una línea de producción** más allá de crear el target. Ese
es el arranque: red debajo de lo más crítico antes de refactorizar nada.
