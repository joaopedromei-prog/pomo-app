# Plano: Foco em tempo real, cronômetro como foco e modo Relógio

## Contexto

Hoje o app só registra uma sessão de foco quando ela termina **naturalmente** (timer chega a zero). Se o usuário fechar o app aos 20 min, o tempo é perdido. Além disso, o contador "tempo de foco hoje" mostrado abaixo do timer só atualiza ao vivo no modo Pomodoro — durante o cronômetro, o tempo decorrido em andamento não aparece somado (embora a sessão final, quando concluída, já entre na soma). Por fim, o usuário quer uma terceira opção no segmented control da aba Timer (ao lado de Pomodoro/Cronômetro) chamada "Relógio", apenas para visualizar a hora atual em HH:MM:SS.

Decisões confirmadas com o usuário:
- Encerrar manualmente **sempre** contabiliza o tempo decorrido até ali.
- Relógio mostra apenas HH:MM:SS, sem data por extenso.
- Sessão em andamento é salva no disco a cada **60 s** (perda máxima ~1 min em crash).
- No modo Relógio, os botões de play/pause/stop ficam escondidos.

---

## Feature 1 — Persistência em tempo real do foco

### Estratégia
Adicionar um arquivo `inflight.json` em `~/Library/Application Support/Pomo/` que contém **a sessão atualmente em andamento**. Ele é:
- Atualizado a cada 60 s pelo `TimerEngine` enquanto a sessão roda.
- Atualizado também ao **pausar** (snapshot do `effectiveElapsed` atual).
- **Removido** quando a sessão é finalizada (concluída naturalmente, encerrada via reset, parada via `stopStopwatch`, ou pulada via `skip`) — antes da remoção, é convertido em `Session` e inserido em `sessions.json` se `actualDuration > 0`.
- **Recuperado na inicialização** do app: se existir um `inflight.json` órfão (do último crash/quit), ele é convertido em `Session` final e adicionado à lista, depois removido.

### Modelo
Adicionar à `Session.swift` um struct novo (mesmo arquivo):

```swift
struct InflightSession: Codable {
    var id: UUID            // será reusado como Session.id ao finalizar
    var startedAt: Date
    var lastTickAt: Date    // serve como endedAt provisório
    var kind: SessionKind
    var plannedDuration: Int
    var actualDuration: Int // = effectiveElapsed atualizado
}
```

### Mudanças em `PersistenceStore.swift`
- Adicionar propriedade observável `var inflight: InflightSession?`.
- Adicionar métodos:
  - `func setInflight(_ session: InflightSession)` → atualiza propriedade + grava `inflight.json`.
  - `func clearInflight()` → zera propriedade + remove arquivo.
  - `func finalizeInflight(endedAt: Date)` → se `inflight` existir e `actualDuration > 0`, converte em `Session` (reusando id), faz `insert(session:)`, depois `clearInflight()`. Se duração for 0, só limpa.
- Em `init() → load()`: ao carregar, se `inflight.json` existir, chamar `finalizeInflight(endedAt: inflight.lastTickAt)` para incorporar a sessão recuperada às `sessions` antes da UI subir.

### Mudanças em `TimerEngine.swift`
- Adicionar callback `var onInflightTick: ((InflightSession) -> Void)?` e `var onInflightClear: (() -> Void)?`.
- Em `start()`: ao iniciar uma sessão (focus ou stopwatch), criar um `InflightSession` com `id` novo e disparar `onInflightTick` imediatamente.
- Em `tick()`: a cada 60 s de `effectiveElapsed` (i.e., quando `effectiveElapsed % 60 == 0`), disparar `onInflightTick` com snapshot atualizado.
- Em `pause()`: disparar `onInflightTick` (snapshot final do que foi acumulado).
- Em `completeCurrentPhase()`, `stopStopwatch()`, `reset()`, `skip()`:
  - **Antes** de fazer `onSessionComplete?(data)` (quando aplicável), disparar `onInflightClear` para evitar dupla contagem na UI/persistência durante o frame de transição.
  - Em `reset()` e `skip()` também precisamos preservar o tempo: se `effectiveElapsed > 0` e a phase era `.focus`/`.stopwatchRunning`, disparar `onSessionComplete` com a duração parcial **antes** do `onInflightClear`. Hoje `reset()` simplesmente zera; vamos mudar para chamar uma rotina interna `flushPartialSessionIfAny()` antes do reset propriamente dito.

### Mudanças em `TimerView.swift`
- Em `setupCallback()`, conectar também:
  ```swift
  engine.onInflightTick = { [weak store] inflight in
      store?.setInflight(inflight)
  }
  engine.onInflightClear = { [weak store] in
      store?.clearInflight()
  }
  ```
- O contador `todayFocusSeconds` (linha 228) **não precisa mudar para isso** — a fonte de verdade visual continua sendo `engine.effectiveElapsed` ao vivo. O `inflight.json` é apenas seguro de persistência. Após relançar o app pós-crash, a soma de `store.sessions` já incluirá o que foi recuperado.

---

## Feature 2 — Cronômetro contabiliza foco em tempo real

Já temos:
- `todayFocusSeconds` soma todas as sessões de hoje **sem filtrar por kind** → cronômetro **finalizado** já conta. ✅

Falta:
- Contador ao vivo durante cronômetro rodando.

### Mudança em `TimerView.swift` (linha 233)
```swift
// ANTES
let current = (engine.phase == .focus && engine.isRunning) ? engine.effectiveElapsed : 0

// DEPOIS
let isLiveFocusable = engine.isRunning && (engine.phase == .focus || engine.phase == .stopwatchRunning)
let current = isLiveFocusable ? engine.effectiveElapsed : 0
```

Resultado: ao iniciar o cronômetro, o "Xmin hoje" abaixo do display começa a incrementar imediatamente, igual ao Pomodoro.

---

## Feature 3 — Modo Relógio (terceira opção do segmented control)

### Adição em `TimerEngine.swift`
```swift
enum TimerMode: String, CaseIterable {
    case pomodoro = "Pomodoro"
    case stopwatch = "Cronômetro"
    case clock = "Relógio"
}
```

Em `switchMode(to:)`: ao trocar para `.clock`, garantir `phase = .idle` (já é o caso). Nenhuma lógica de tick precisa ser alterada — o relógio é puramente visual.

Em `phaseLabel`: adicionar `case .idle where mode == .clock: return "AGORA"` (ou "RELÓGIO" — escolha estética; vou usar "AGORA" por ser mais elegante).

### Adição em `TimerView.swift`

Estender `ClockDisplay` (ou criar variante `ClockDisplayHHMMSS`) que recebe `hours`, `minutes`, `seconds` e renderiza três `DigitCard` separados por dois colons. Mantém o mesmo estilo visual (cor, corner radius, fonte monospaced, sizing proporcional ao `containerWidth`).

Abordagem mais limpa: generalizar `ClockDisplay` para aceitar `[Int]` de componentes em vez de `totalSeconds`, e o `TimerView` decide o que passar:
- Pomodoro/Stopwatch: `[mm, ss]`
- Clock: `[hh, mm, ss]`

No `body` da `TimerView`, dentro do `Group` do display (linhas 113-142), bifurcar:

```swift
if engine.mode == .clock {
    TimelineView(.periodic(from: .now, by: 1.0)) { context in
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: context.date)
        ClockDisplay(components: [comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0],
                     containerWidth: clockWidth)
    }
} else {
    ClockDisplay(components: [displaySeconds / 60, displaySeconds % 60],
                 containerWidth: clockWidth, sessionMaxSeconds: ...)
}
```

`TimelineView(.periodic)` é o mecanismo idiomático SwiftUI para atualização periódica e só "tica" quando a view está visível.

### Esconder elementos no modo Relógio
- Indicadores de ciclo (linha 126-135): já tem `.opacity(engine.mode == .pomodoro ? 1 : 0)` — manter.
- Texto `todayFocusLabel` (linha 137): manter visível também no Relógio (mostra o foco do dia, útil).
- HStack de botões (linha 151-181): envolver com `if engine.mode != .clock { ... }` para esconder completamente. O `Spacer` superior/inferior cuidará do recentralização visual.

### Picker
Já usa `ForEach(TimerMode.allCases)` — adicionar a nova case automaticamente popula o segmented control com três opções.

---

## Arquivos a modificar

| Arquivo | Mudança |
|---|---|
| `Sources/Pomo/Models/Session.swift` | Adicionar struct `InflightSession` |
| `Sources/Pomo/Core/PersistenceStore.swift` | `inflight` property, `setInflight`, `clearInflight`, `finalizeInflight`, recovery em `load()` |
| `Sources/Pomo/Core/TimerEngine.swift` | Callbacks `onInflightTick`/`onInflightClear`, hook em tick (a cada 60 s) e em pause; `flushPartialSessionIfAny()` em reset/skip; nova case `.clock` em `TimerMode`; case `.clock` em `phaseLabel` |
| `Sources/Pomo/Views/TimerView.swift` | Conectar callbacks de inflight; ajustar `todayFocusSeconds` para incluir cronômetro ao vivo; bifurcar display entre ClockDisplay normal e modo Relógio com `TimelineView`; generalizar `ClockDisplay` para aceitar componentes; esconder botões quando `mode == .clock` |

Nenhuma mudança em `MainView.swift`, `HistoryView.swift`, `PomoApp.swift`, `Tasks*`, `Settings*`.

---

## Verificação (teste manual end-to-end)

1. **Build & run**: `swift build` na raiz e abrir o app.
2. **Real-time persistence**:
   - Iniciar Pomodoro de 60 min, deixar rodando ~3 min.
   - `Cmd+Q` no app (ou `kill -9` para simular crash).
   - Verificar `~/Library/Application Support/Pomo/inflight.json` existe.
   - Reabrir o app → ir em Histórico → confirmar que aparece uma sessão de foco de ~3 min para hoje.
   - Confirmar que `inflight.json` foi removido pós-recovery.
   - "Xmin hoje" abaixo do timer deve mostrar ~3min.
3. **Reset preserva tempo**:
   - Iniciar Pomodoro, esperar 2 min, clicar "encerrar".
   - Confirmar em Histórico que a sessão de 2 min foi salva.
4. **Skip preserva tempo**:
   - Iniciar Pomodoro, esperar 1 min, clicar "pular".
   - Confirmar sessão de 1 min em Histórico.
5. **Cronômetro contagem ao vivo**:
   - Trocar para "Cronômetro" → iniciar.
   - Verificar que "Xmin hoje" começa a incrementar a cada minuto durante o cronômetro rodando.
6. **Cronômetro persistido**:
   - Cronômetro rodando ~2 min, fechar app.
   - Reabrir → verificar sessão de 2 min em Histórico.
7. **Modo Relógio**:
   - Trocar segmented control para "Relógio".
   - Confirmar exibição HH:MM:SS atualizando a cada segundo.
   - Confirmar que botões play/pause/stop **não aparecem**.
   - Confirmar que indicadores de ciclo não aparecem.
   - Confirmar que "Xmin hoje" continua sendo exibido.
   - Voltar para Pomodoro/Cronômetro e verificar que tudo segue funcional.
8. **Sem regressão**: rodar Pomodoro completo de teste (reduzir foco para 1 min em Ajustes) → confirmar que sessão completa ainda salva normalmente, alarme dispara, etc.

---

## Notas de implementação

- O `effectiveElapsed % 60 == 0` para snapshot de minuto: o tick é a cada 1 s e `effectiveElapsed` é incrementado a cada tick (linha 164 de TimerEngine), então isso dispara exatamente uma vez por minuto.
- Em `pause()`, salvar imediatamente garante que pausar + fechar não perca o último intervalo parcial < 60 s.
- A recuperação na inicialização usa `inflight.lastTickAt` como `endedAt` da sessão final — isso é mais conservador que `Date()` (não infla a duração com tempo offline).
- `InflightSession.id` é reusado como `Session.id` quando finalizada, garantindo que múltiplas finalizações na mesma sessão idempotentemente referenciem o mesmo registro (evita duplicação se o usuário reabrir e fechar rápido).
