# Analýza simulační logiky - MATLAB UpEtDown

> **Cíl:** Identifikovat problematické části současné simulace a navrhnout vylepšení pro PHP 8.4 implementaci

---

## 📊 1. Hlavní simulační smyčka (Controller.run)

### 1.1 Současný stav (MATLAB)

```matlab
% Controller.m, řádky 51-83
function run(this)
    if (this.isModelForSim)
        % create visualization window
        this.view.createGUIWindow(true);

        while (this.loop)
            % while there are some humans unfinished

            tic;
            this.model.setTimeStamp();              % increase simulation step value
            this.model.moveLifts();                 % move all lifts
            this.model.checkHumansWaiting();        % simulate all waiting Humans
            this.model.checkForNewHumanBatch();     % create instances of new Humans
            this.model.selectLiftsNextFloor();      % handle calls for lifts

            % wait 0.1s before refreshing visualization
            while (toc < 0.1)
                pause(0.0001);
            end

            this.view.showHumansWaitingInGUI();     % refresh Humans count in visualization
            this.view.moveLiftsInGUI();             % move lifts in visualization
        end

        % create report after end of simulation
        this.view.showFinalStats();
    else
        msgbox('Instance was created only for visualization, simulation is not possible!');
    end
end
```

### 1.2 ❌ Problémy

#### **P1: Tight Coupling - Simulace vs. Vizualizace**
```matlab
this.view.createGUIWindow(true);           // Blokuje spuštění bez GUI
while (this.loop) {
    // ... simulace ...
    this.view.showHumansWaitingInGUI();    // Vizualizace vmíchaná do logiky
    this.view.moveLiftsInGUI();
}
```

**Problém:**
- Simulace NEMŮŽE běžet bez GUI
- Nelze spustit simulaci v CLI/na serveru
- Nelze testovat logiku nezávisle
- Nelze paralelizovat simulace

#### **P2: Hardcoded Timing (Magic Numbers)**
```matlab
while (toc < 0.1)     // Pevných 100ms pro každý krok
    pause(0.0001);
end
```

**Problém:**
- Nemožnost zrychlení/zpomalení simulace
- Na výkonných strojích zbytečné čekání
- Pro API/batch processing nesmyslné

#### **P3: Synchronní Blokující Smyčka**
```matlab
while (this.loop)
    // Celá aplikace zamrzlá během simulace
    // Nelze pozastavit/obnovit
    // Nelze získat průběžný status
end
```

**Problém:**
- GUI freezing
- Nelze implementovat pause/resume
- Nelze streamovat průběžné výsledky
- Nelze implementovat WebSocket updates

#### **P4: Boolean Flag pro Ukončení**
```matlab
this.loop = true;
// ...
function endOfSim(this, src, evtdata)
    this.loop = false;  // Jediný způsob ukončení
end
```

**Problém:**
- Nemožnost force stop
- Nelze timeout
- Risk infinite loop při buggu

---

## 🏗️ 2. Orchestrace simulace (Simulation.m)

### 2.1 Problém: God Object Anti-Pattern

**Simulation.m má 1095 řádků a dělá VŠECHNO:**

```matlab
classdef Simulation < handle
    properties
        b;                      % Building management
        h;                      % Human management
        humansList;             % Data loading
        waitingList;            % Queue management
        floorList;              % Queue management
        systemBehavior;         % Algorithm selection
        ss;                     % Pathfinding
        timeStamp;              % Time management
        showDebugInfo;          % Logging
    end

    methods
        % Lifecycle
        Simulation(...)         % Constructor

        % Lift operations
        callLiftsOnFloor(...)
        callOneLift(...)
        findLiftsOnFloor(...)
        moveLifts(...)
        selectLiftsNextFloor(...)
        getAllLiftsActualFloor(...)

        % Human operations
        findHumansOnFloorWaiting(...)
        findAvailableLifts(...)
        simulateOneHuman(...)
        humanEnterLift(...)
        humanLeaveLift(...)
        canCallLift(...)
        checkFloorPeople(...)
        checkHumansWaiting(...)
        checkForNewHumanBatch(...)
        runNextHumanBatch(...)
        addToWaitingList(...)
        removeFromWaitingList(...)

        % Statistics & reporting
        getFinalStats(...)
        makeGraphs(...)

        % Events
        liftOnFloor(...)

        % Utilities
        checkAllFloorsCovered(...)
        deleteWrongHumans(...)  % Static
        getTime(...)            % Static
    end
end
```

**❌ Porušuje Single Responsibility Principle**

---

### 2.2 Problém: Duplicitní Logika (DRY Violation)

```matlab
% Simulation.m, řádky 349-433
case States.random
    % Random behavior
    planFloor = this.h(ID).actualPath.Floor;
    actualFloor = this.h(ID).getActualFloor;

    if (planFloor == actualFloor)
        liftID = this.h(ID).actualPath.Lift;
        // ... 40 řádků logiky ...
    end

case States.dijkstra_e
    % Scheduler behavior
    planFloor = this.h(ID).actualPath.Floor;  // STEJNÉ
    actualFloor = this.h(ID).getActualFloor;  // STEJNÉ

    if (planFloor == actualFloor)            // STEJNÉ
        liftID = this.h(ID).actualPath.Lift; // STEJNÉ
        // ... ÚPLNĚ STEJNÝCH 40 řádků ...
    end
```

**Komentář v kódu:**
```matlab
% This is not obey DRY concept (Don't repeat yourself),
% because both cases are the same.
% Divided to demonstrate the implementation of other
% possible behaviors.
```

❌ **Autor SI UVĚDOMUJE problém, ale neřeší ho!**

---

### 2.3 Problém: Špatný State Management

**Human má příliš mnoho stavů:**
```matlab
classdef States
    enumeration
        % Human states
        lift;         % v výtahu
        floor;        % na patře
        floorHold;    // Čeká 1 iteraci po výstupu z výtahu
        waiting;      % čeká na výtah
        finished;     % dokončil
        newWaiting;   // Právě začal čekat
    end
end
```

**Problém `floorHold`:**
```matlab
% Simulation.m, řádek 522
this.h(ID).setState(States.floorHold);
this.addToWaitingList(ID, this.h(ID).getActualFloor, false);

% Simulation.m, řádky 555-561
if (States.floor.eq(this.h(humans(k)).getState))
    this.simulateOneHuman(humans(k));
else
    % change status, so human is going to be simulated in next step
    this.h(humans(k)).setState(States.floor);
end
```

❌ **Hack pro oddálení zpracování o 1 iteraci - špatný design!**

**Problém `newWaiting`:**
```matlab
% Simulation.m, řádky 383-388
if (States.waiting.ne(this.h(ID).getState))
    this.callOneLift(liftID, actualFloor, direction);
    if (States.newWaiting.ne(this.h(ID).getState))
        // Add to waiting list
    end
    this.h(ID).setState(States.waiting);
end
```

❌ **Stav `newWaiting` zabraňuje vícenásobnému přidání do fronty - špatný design!**

---

## 🎯 3. Pathfinding (StateSpace.m)

### 3.1 Problém: Neefektivní Dijkstra implementace

```matlab
% StateSpace.m, řádky 233-286
function [nodes, predecessors] = dijkstra(this, START)
    Q = [(1:1:numOfFloors+numOfStates)' zeros(1,numOfFloors+numOfStates)'];
    Q(:,2) = Inf;

    closed = [];

    while (~isempty(Q))
        [not, ind] = min(Q(:,2));     // O(n) pro každou iteraci!
        node = Q(ind,1);
        closed(end+1,1) = node;       // Dynamické rozšiřování pole - POMALÉ
        Q(ind,:) = [];                // Mazání z pole - O(n)

        descendants = findDescendants(Gm,node);
        for i=1:size(descendants,2)
            // ... aktualizace priorit ...
        end
    end
end
```

❌ **Problémy:**
- Nepoužívá priority queue → O(n²) místo O(n log n)
- Dynamické rozšiřování polí v MATLABu je VELMI pomalé
- Pro každou simulaci Human se přepočítává Dijkstra (`findOnePath`)

### 3.2 Problém: Random Path - zbytečná složitost

```matlab
% StateSpace.m, řádky 301-344
function path = findRandomPath(this, startFloor, desiredFloor, lifts, AvaLifts)
    // Priority to available lifts
    if (size(AvaLifts,2) > 0)
        lifts = AvaLifts;
    end

    ind = ceil(rand * size(lifts,2));  // Náhodný výběr
    lift = lifts(ind);

    // ... Vytvoření state space jen pro tento lift ...
    [this.G, ~] = this.createGMatrix();
    this.G(node,startFloor) = 0;
    this.G(startFloor,node) = 0;

    [this.nodes, this.predecessors] = this.dijkstra(node);
    pathSeq = this.findPath(desiredFloor);

    // ... hack if path is too short ...
    if (size(pathSeq,2) == 2)
        this.G(node,startFloor) = 1;
        this.G(startFloor,node) = 1;
        [this.nodes, this.predecessors] = this.dijkstra(node);
        // ... znovu výpočet ...
    end
end
```

❌ **Pro "random" výběr výtahu zbytečně spouští Dijkstra!**
- Stačilo by: `lift = lifts[rand()]; path = [startFloor -> lift -> desiredFloor]`

---

## 🚨 4. Event Handling - Race Conditions

### 4.1 Problém: Side Effects v Event Listenerech

```matlab
% Simulation.m, řádky 142-173
function liftOnFloor(this, src, evtdata)
    liftID = src.getID();
    liftActualFloor = src.getActualFloor();

    num = src.getNumOfHumansInLift();
    humans = src.getHumansInLift();

    if (num > 0)
        for i=1:num
            humanNextFloor = this.h(humans(i)).getNextFloor();

            if (liftActualFloor == humanNextFloor && ...)
                // Modifikuje stav během iterace!
                this.humanLeaveLift(humans(i), src.getID, true);
            elseif (liftActualFloor == humanNextFloor)
                this.humanLeaveLift(humans(i), src.getID, false);
            end
        end
    end
end
```

**Problém:**
```matlab
% humanLeaveLift volá:
this.b.l(lift).removeHumanFromLift(ID);  // Mění pole během iterace!
```

❌ **Iteruje přes `humans` pole a ZÁROVEŇ z něj odstraňuje prvky!**
- V MATLABu to funguje náhodou (kopie pole)
- V PHP/C++/Java by to byl BUG

---

## 🔄 5. Queue Management - Nepřehledné

### 5.1 Problém: Dvojí fronta (waitingList, floorList)

```matlab
% Simulation.m
properties
    waitingList;  // Humans čekající na výtah
    floorList;    // Humans právě vystoupili z výtahu nebo nově vytvořeni
end
```

**Použití:**
```matlab
% Různé funkce musí kontrolovat OBĚ fronty
function showHumansWaitingInGUI(this)
    waitingList = this.model.waitingList;
    floorList = this.model.floorList;

    if (~isempty(waitingList) || ~isempty(floorList))
        if (~isempty(waitingList))
            floors = [floors waitingList{:,1}];
        end
        if (~isempty(floorList))
            floors = [floors floorList{:,1}];
        end
        // ...
    end
end
```

❌ **Zbytečná složitost - jedno by stačilo s různými stavy**

### 5.2 Problém: Cell Array Structure

```matlab
% Formát: {floor, [human_IDs]}
waitingList = {
    1, [3, 7, 12];
    5, [1, 2];
    8, [9]
}
```

**Neefektivní operace:**
```matlab
% addToWaitingList - O(n) hledání
if (isempty(list))
    list{end+1,1} = floor;
    list{end,2} = ID;
else
    index = find([list{:,1}] == floor);  // Linearní vyhledávání
    if (isempty(index))
        list{end+1,1} = floor;
        list{end,2} = ID;
    else
        list{index,2} = [list{index,2} ID];
    end
end
```

❌ **Měla by být mapa/dictionary: `floor => [IDs]`**

---

## 📈 6. Statistics & Reporting - Smíchané Responsibility

### 6.1 Problém: Generování HTML přímo v doménové logice

```matlab
% Simulation.m, řádky 708-860
function getFinalStats(this)
    // ... výpočty statistik ...

    // Příprava HTML struktur pro výtahy
    liftStr = [];
    for i=1:liftsNum
        liftStr = strcat(liftStr,'<tr>');
        liftStr = strcat(liftStr,sprintf('<td>%s</td>', num2str(...)));
        liftStr = strcat(liftStr,sprintf('<td>%s</td>', num2str(...)));
        // ...
        liftStr = strcat(liftStr,'</tr>');
    end

    // HTML template replacement
    template = fileread('assets/output_template.html');
    output = strrep(template, '%%DATE%%', DATE);
    output = strrep(output, '%%BEHAVIOR%%', BEHAVIOR);
    output = strrep(output, '%%NUM_VISITORS%%', NUM_VISITORS);
    // ... 30+ replacements ...

    disp(output);  // Vypíše HTML do konzole!
end
```

❌ **Problémy:**
- Domain logika generuje HTML
- Používá `strrep` místo template engine
- `disp(output)` - vypíše HTML do CLI (wtf?)
- Nemožnost generovat jiné formáty (JSON, PDF)

### 6.2 Problém: Graph Generation v Simulační Logice

```matlab
% Simulation.m, řádky 862-974
function [figHistFullExt, figWaitFullExt] = makeGraphs(this)
    figHis = figure;
    set(figHis, 'Visible', 'Off');

    // ... MATLAB plotting kód ...

    print(figHis,'-dpng','-r200', figHistFull)
    close(figHis);

    // Vrací cesty k souborům
    figHistFullExt = strcat(figHistFile,'.png');
end
```

❌ **Simulace by neměla vědět o grafech!**

---

## 🎭 7. Lift Movement - Floating Point Issues

### 7.1 Problém: Kontinuální pohyb diskrétních pater

```matlab
% Lift.m, řádky 174-217
function [h] = move(this, humans)
    floorLift = this.getActualFloor();    // může být 3.5, 4.2, atd.
    nextstop = this.getNextStop();        // cílové patro (integer)

    if (nextstop > floorLift)
        floorLift = floorLift + this.getLiftSpeed;  // např. 3 + 0.5 = 3.5
        if (abs(nextstop - floorLift) < 1 && floorLift > nextstop)
            floorLift = nextstop;  // Snap to floor
        end
    end

    this.actualFloor = floorLift;
    for i=1:this.getNumOfHumansInLift
        humans(this.humansInLift(i)).actualFloor = floorLift;  // Humans na 3.7?
    end
end
```

❌ **Problémy:**
- `actualFloor` je floating point (3.5, 4.2) - matoucí!
- Humans mají `actualFloor = 3.7` - nejsou na žádném patře
- Floating point comparison bugs (`abs(nextstop - floorLift) < 1`)

**Lepší přístup:**
- `actualFloor` (integer) - diskrétní patro
- `position` (float) - pozice mezi patry pro animaci
- Nebo: `distanceToNextFloor` (float 0.0-1.0)

---

## 🔍 8. Access Control - Přílišné Sdílení

### 8.1 Problém: Friend Classes Everywhere

```matlab
classdef Simulation < handle
    properties (Access = {?View, ?Controller, ?GUI})
        b;
        h;
        humansList;
        // ...
    end
end

classdef Lift < handle
    properties (Access = {?Simulation, ?Controller, ?View, ?Building, ?StateSpace})
        baseFloor;
        finalFloor;
        // ...
    end
end
```

❌ **Téměř všechno je accessible všem - porušuje encapsulation**

---

## 🎯 9. Navrhovaná Vylepšení pro PHP 8.4

### 9.1 ✅ Oddělení Simulace od Vizualizace

**PŘED (MATLAB):**
```matlab
class Controller {
    function run() {
        this.view.createGUIWindow();  // Musí být GUI
        while (this.loop) {
            // simulace
            this.view.updateGUI();    // Zamrzlé GUI
        }
    }
}
```

**PO (PHP 8.4):**
```php
// Domain - čistá logika
class SimulationEngine
{
    public function run(Simulation $simulation): Generator
    {
        while (!$simulation->isFinished()) {
            $simulation->tick();

            // Yield pro progress tracking
            yield new SimulationState(
                timestamp: $simulation->getTimestamp(),
                lifts: $simulation->getLiftsSnapshot(),
                waitingHumans: $simulation->getWaitingCount(),
            );
        }

        return $this->calculateStatistics($simulation);
    }
}

// Infrastructure - různé adaptéry
// 1. CLI Command
class RunSimulationCommand
{
    public function execute(string $configFile): void
    {
        $simulation = $this->loader->load($configFile);

        foreach ($this->engine->run($simulation) as $state) {
            $this->output->writeln("Progress: {$state->progress}%");
        }
    }
}

// 2. WebSocket Real-time
class SimulationWebSocketHandler
{
    public function handle(Connection $conn, RunSimulationMessage $msg): void
    {
        $simulation = $this->repository->get($msg->simulationId);

        foreach ($this->engine->run($simulation) as $state) {
            $conn->send(json_encode($state));  // Real-time updates
            usleep(100_000);  // 100ms delay for visualization
        }
    }
}

// 3. Background Job (bez vizualizace)
class ProcessSimulationJob
{
    public function execute(string $simulationId): void
    {
        $simulation = $this->repository->get($simulationId);

        // Rychlé zpracování bez delays
        foreach ($this->engine->run($simulation) as $state) {
            // Optional: save checkpoint
            if ($state->timestamp % 100 === 0) {
                $this->saveCheckpoint($simulation);
            }
        }

        $this->repository->markAsFinished($simulationId);
    }
}
```

**Výhody:**
- ✅ Simulace může běžet bez UI
- ✅ Testovatelná business logika
- ✅ Různé "konzumenty" výsledků
- ✅ Paralelní běh simulací

---

### 9.2 ✅ Rozdělit God Object (Simulation)

**PŘED:**
```matlab
class Simulation  // 1095 řádků
    % Dělá VŠECHNO
end
```

**PO:**
```php
// Domain/Model/Simulation.php - Agregační root
readonly class Simulation
{
    public function __construct(
        private SimulationId $id,
        private Building $building,
        private HumanQueue $humanQueue,
        private HumanCollection $activeHumans,
        private int $timestamp = 0,
    ) {}

    public function tick(): void
    {
        $this->timestamp++;
        // Orchestrace, ne implementace!
    }

    public function isFinished(): bool
    {
        return $this->humanQueue->isEmpty()
            && $this->activeHumans->allFinished();
    }
}

// Domain/Service/LiftOrchestrator.php
class LiftOrchestrator
{
    public function moveAllLifts(Building $building, HumanCollection $humans): void
    {
        foreach ($building->getLifts() as $lift) {
            $lift->move();

            if ($lift->hasArrived()) {
                $this->handleArrival($lift, $humans);
            }
        }
    }

    private function handleArrival(Lift $lift, HumanCollection $humans): void
    {
        foreach ($lift->getPassengers() as $humanId) {
            $human = $humans->get($humanId);

            if ($human->shouldExitAt($lift->getCurrentFloor())) {
                $this->exitHuman($human, $lift);
            }
        }
    }
}

// Domain/Service/HumanOrchestrator.php
class HumanOrchestrator
{
    public function __construct(
        private PathFinderInterface $pathFinder
    ) {}

    public function processWaitingHumans(
        HumanCollection $humans,
        Building $building
    ): void {
        foreach ($humans->getWaiting() as $human) {
            $this->tryEnterLift($human, $building);
        }
    }
}

// Domain/Collection/HumanQueue.php - Managed queue
class HumanQueue
{
    /** @var array<int, Human[]> floor => humans */
    private array $queue = [];

    public function addToFloor(int $floor, Human $human): void
    {
        $this->queue[$floor] ??= [];
        $this->queue[$floor][] = $human;
    }

    public function getWaitingOnFloor(int $floor): array
    {
        return $this->queue[$floor] ?? [];
    }

    public function remove(Human $human): void
    {
        foreach ($this->queue as $floor => $humans) {
            $this->queue[$floor] = array_filter(
                $humans,
                fn($h) => $h->getId() !== $human->getId()
            );
        }
    }
}
```

**Výhody:**
- ✅ Single Responsibility
- ✅ Testovatelné komponenty
- ✅ Jasné API
- ✅ Snadná údržba

---

### 9.3 ✅ Odstranit Duplicitní Logiku

**PŘED:**
```matlab
case States.random
    // 40 řádků logiky
case States.dijkstra_e
    // STEJNÝCH 40 řádků
```

**PO:**
```php
// Domain/Service/HumanBehavior.php
interface HumanBehaviorStrategy
{
    public function calculatePath(
        Human $human,
        Building $building
    ): Path;
}

class RandomBehavior implements HumanBehaviorStrategy
{
    public function calculatePath(Human $human, Building $building): Path
    {
        $availableLifts = $building->getLiftsOnFloor($human->getFloor());
        $lift = $availableLifts[array_rand($availableLifts)];

        return new Path(
            lift: $lift,
            targetFloor: $human->getDestination()
        );
    }
}

class DijkstraBehavior implements HumanBehaviorStrategy
{
    public function calculatePath(Human $human, Building $building): Path
    {
        $costs = [];
        foreach ($building->getLifts() as $lift) {
            $costs[$lift->getId()] = $this->calculateCost($lift, $human);
        }

        $bestLiftId = array_search(min($costs), $costs);

        return new Path(
            lift: $building->getLift($bestLiftId),
            targetFloor: $human->getDestination()
        );
    }
}

// Použití - Stratégy Pattern
class HumanOrchestrator
{
    public function __construct(
        private HumanBehaviorStrategy $strategy  // Injected!
    ) {}

    public function simulateHuman(Human $human, Building $building): void
    {
        // SPOLEČNÁ logika (bez duplicity)
        if (!$human->hasPath()) {
            $path = $this->strategy->calculatePath($human, $building);
            $human->setPath($path);
        }

        $lift = $building->getLift($human->getPath()->getLiftId());

        if ($lift->isAvailable() && !$lift->isFull()) {
            $this->boardHuman($human, $lift);
        } else {
            $human->startWaiting();
            $lift->addToQueue($human->getFloor(), $human->getDirection());
        }
    }
}
```

**Výhody:**
- ✅ Zero duplicity
- ✅ Snadné přidání nových algoritmů
- ✅ Strategy pattern
- ✅ Testovatelné strategie

---

### 9.4 ✅ Zjednodušit State Management

**PŘED:**
```matlab
enum States
    floor;
    floorHold;    // Hack pro oddálení o 1 iteraci
    waiting;
    newWaiting;   // Hack proti vícenásobnému přidání
    lift;
    finished;
end
```

**PO:**
```php
enum HumanState: string
{
    case ON_FLOOR = 'on_floor';
    case WAITING = 'waiting';
    case IN_LIFT = 'in_lift';
    case FINISHED = 'finished';
}

class Human
{
    private HumanState $state = HumanState::ON_FLOOR;
    private bool $justExited = false;  // Místo floorHold
    private bool $isInWaitingQueue = false;  // Místo newWaiting

    public function startWaiting(): void
    {
        if ($this->isInWaitingQueue) {
            return;  // Already waiting
        }

        $this->state = HumanState::WAITING;
        $this->isInWaitingQueue = true;
    }

    public function exitLift(): void
    {
        $this->state = HumanState::ON_FLOOR;
        $this->justExited = true;
    }

    public function canBeProcessed(): bool
    {
        // Místo kontroly floorHold state
        if ($this->justExited) {
            $this->justExited = false;
            return false;  // Skip this iteration
        }

        return true;
    }
}
```

**Výhody:**
- ✅ Méně stavů = jednodušší logika
- ✅ Explicitní flags místo hacků
- ✅ Čitelnější kód

---

### 9.5 ✅ Efektivní Pathfinding

**PŘED:**
```matlab
% Pro RANDOM výběr spouští Dijkstra (wtf?)
function path = findRandomPath(...)
    lift = lifts(ceil(rand * size(lifts,2)));
    [this.nodes, this.predecessors] = this.dijkstra(node);  // ZBYTEČNÉ
    pathSeq = this.findPath(desiredFloor);
end
```

**PO:**
```php
class RandomPathFinder implements PathFinderInterface
{
    public function findPath(
        int $startFloor,
        int $targetFloor,
        array $availableLifts
    ): Path {
        // Jednoduchý random výběr
        $lift = $availableLifts[array_rand($availableLifts)];

        return new Path(
            segments: [
                new PathSegment($startFloor, $lift, $targetFloor)
            ]
        );
    }
}

class DijkstraPathFinder implements PathFinderInterface
{
    private array $graphCache = [];

    public function findPath(
        int $startFloor,
        int $targetFloor,
        array $availableLifts
    ): Path {
        // Cachování grafu - nepřepočítává se pokaždé
        $cacheKey = $this->getCacheKey($availableLifts);

        if (!isset($this->graphCache[$cacheKey])) {
            $this->graphCache[$cacheKey] = $this->buildGraph($availableLifts);
        }

        $graph = $this->graphCache[$cacheKey];

        // Efektivní Dijkstra s priority queue
        $result = $this->dijkstra($graph, $startFloor, $targetFloor);

        return $this->buildPath($result);
    }

    private function dijkstra(Graph $graph, int $start, int $end): array
    {
        // PHP 8.4 - SplPriorityQueue
        $queue = new \SplPriorityQueue();
        $queue->insert($start, 0);

        $distances = [$start => 0];
        $previous = [];

        while (!$queue->isEmpty()) {
            $current = $queue->extract();

            if ($current === $end) {
                break;
            }

            foreach ($graph->getNeighbors($current) as $neighbor) {
                $alt = $distances[$current] + $graph->getWeight($current, $neighbor);

                if ($alt < ($distances[$neighbor] ?? INF)) {
                    $distances[$neighbor] = $alt;
                    $previous[$neighbor] = $current;
                    $queue->insert($neighbor, -$alt);  // Negative pro min-heap
                }
            }
        }

        return ['distances' => $distances, 'previous' => $previous];
    }
}
```

**Výhody:**
- ✅ Random je skutečně jednoduchý (bez Dijkstra)
- ✅ Dijkstra s priority queue O(E log V) místo O(V²)
- ✅ Cachování grafu - nepřepočítává se
- ✅ SplPriorityQueue (built-in PHP)

---

### 9.6 ✅ Bezpečný Event Handling

**PŘED:**
```matlab
% Iteruje a modifikuje zároveň
for i=1:num
    if (condition)
        this.humanLeaveLift(humans(i), ...);  // Mění pole během iterace
    end
end
```

**PO:**
```php
class LiftOrchestrator
{
    public function handleLiftArrival(Lift $lift, HumanCollection $humans): void
    {
        $currentFloor = $lift->getCurrentFloor();

        // 1. Collect humans to exit (immutable)
        $humansToExit = [];
        foreach ($lift->getPassengers() as $humanId) {
            $human = $humans->get($humanId);

            if ($human->shouldExitAt($currentFloor)) {
                $humansToExit[] = $human;
            }
        }

        // 2. Then modify (separate phase)
        foreach ($humansToExit as $human) {
            $this->exitHuman($human, $lift);

            // Event dispatch
            $this->eventDispatcher->dispatch(
                new HumanExitedLiftEvent($human, $lift, $currentFloor)
            );
        }
    }

    private function exitHuman(Human $human, Lift $lift): void
    {
        $lift->removePassenger($human->getId());
        $human->exitLift();

        if ($human->isAtDestination()) {
            $human->finish();
        }
    }
}
```

**Výhody:**
- ✅ Collect-then-modify pattern
- ✅ Žádné race conditions
- ✅ Immutable iteration
- ✅ Event dispatch oddělený

---

### 9.7 ✅ Type-Safe Queue Management

**PŘED:**
```matlab
% Cell array: {floor, [IDs]}
waitingList = {
    1, [3, 7, 12];
    5, [1, 2];
}

% Linearní vyhledávání O(n)
index = find([list{:,1}] == floor);
```

**PO:**
```php
class HumanQueue
{
    /** @var array<int, Human[]> */
    private array $byFloor = [];

    /** @var array<string, int> Human ID => floor */
    private array $humanToFloor = [];

    public function addToFloor(int $floor, Human $human): void
    {
        // O(1) insertion
        $this->byFloor[$floor] ??= [];
        $this->byFloor[$floor][] = $human;
        $this->humanToFloor[$human->getId()] = $floor;
    }

    public function getWaitingOnFloor(int $floor): array
    {
        // O(1) retrieval
        return $this->byFloor[$floor] ?? [];
    }

    public function remove(Human $human): void
    {
        // O(1) lookup + O(n) removal where n = humans on that floor
        $floor = $this->humanToFloor[$human->getId()] ?? null;

        if ($floor !== null) {
            $this->byFloor[$floor] = array_filter(
                $this->byFloor[$floor],
                fn($h) => $h->getId() !== $human->getId()
            );
            unset($this->humanToFloor[$human->getId()]);
        }
    }

    public function getAllWaitingCount(): int
    {
        return count($this->humanToFloor);
    }

    public function getFloorsWithWaiting(): array
    {
        return array_keys(array_filter(
            $this->byFloor,
            fn($humans) => !empty($humans)
        ));
    }
}
```

**Výhody:**
- ✅ O(1) vyhledávání místo O(n)
- ✅ Type-safe (PHP 8.4 typed arrays hint)
- ✅ Jasné API
- ✅ Dual indexing pro rychlé operace

---

### 9.8 ✅ Oddělení Reportingu od Domény

**PŘED:**
```matlab
% Simulation.m - generuje HTML, ukládá soubory, volá disp()
function getFinalStats(this)
    // ... výpočty ...
    liftStr = strcat(liftStr,'<tr><td>...</td></tr>');  // WTF
    template = fileread('assets/output_template.html');
    output = strrep(template, '%%DATE%%', DATE);
    disp(output);  // Vypíše HTML do CLI
end
```

**PO:**
```php
// Domain/Service/StatisticsCalculator.php - POUZE výpočty
class StatisticsCalculator
{
    public function calculate(Simulation $simulation): SimulationStatistics
    {
        $humans = $simulation->getHumans();
        $lifts = $simulation->getBuilding()->getLifts();

        return new SimulationStatistics(
            totalHumans: count($humans),
            waitingTimes: new WaitingTimeStats(
                average: $this->calculateAverageWaitTime($humans),
                max: $this->calculateMaxWaitTime($humans),
                min: $this->calculateMinWaitTime($humans),
                stdDev: $this->calculateStdDev($humans, 'waitTime'),
            ),
            travelTimes: new TravelTimeStats(
                average: $this->calculateAverageTravelTime($humans),
                max: $this->calculateMaxTravelTime($humans),
                min: $this->calculateMinTravelTime($humans),
                stdDev: $this->calculateStdDev($humans, 'travelTime'),
            ),
            liftStats: new LiftStatistics(
                totalFloorsTraveled: $this->calculateTotalFloors($lifts),
                busiestLift: $this->findBusiestLift($lifts),
                leastBusyLift: $this->findLeastBusyLift($lifts),
            )
        );
    }
}

// Application/Service/ReportGenerator.php - Generování výstupů
interface ReportGeneratorInterface
{
    public function generate(SimulationStatistics $stats): string;
}

class HtmlReportGenerator implements ReportGeneratorInterface
{
    public function __construct(
        private TwigEnvironment $twig,
        private ChartGenerator $chartGenerator
    ) {}

    public function generate(SimulationStatistics $stats): string
    {
        // Generování grafů
        $histogramPath = $this->chartGenerator->generateHistogram($stats);
        $waitTimesPath = $this->chartGenerator->generateWaitTimes($stats);

        // Renderování template
        return $this->twig->render('report.html.twig', [
            'stats' => $stats,
            'histogramUrl' => $histogramPath,
            'waitTimesUrl' => $waitTimesPath,
            'generatedAt' => new \DateTimeImmutable(),
        ]);
    }
}

class JsonReportGenerator implements ReportGeneratorInterface
{
    public function generate(SimulationStatistics $stats): string
    {
        return json_encode($stats, JSON_PRETTY_PRINT);
    }
}

class PdfReportGenerator implements ReportGeneratorInterface
{
    // Using TCPDF or Dompdf
}

// Infrastructure/Http/Controller/ReportController.php
class ReportController
{
    public function show(string $simulationId, string $format = 'html'): Response
    {
        $simulation = $this->repository->get($simulationId);
        $stats = $this->statsCalculator->calculate($simulation);

        $generator = match($format) {
            'json' => $this->jsonGenerator,
            'pdf' => $this->pdfGenerator,
            default => $this->htmlGenerator,
        };

        $content = $generator->generate($stats);

        return new Response($content, headers: [
            'Content-Type' => $this->getContentType($format)
        ]);
    }
}
```

**Výhody:**
- ✅ Separation of Concerns
- ✅ Domain vrstva neví o HTML/PDF/JSON
- ✅ Snadno přidat nové formáty
- ✅ Testovatelné výpočty
- ✅ Moderní template engine (Twig)

---

### 9.9 ✅ Fix Floating Point Floors

**PŘED:**
```matlab
% actualFloor je float: 3.5, 4.7, ...
floorLift = floorLift + this.getLiftSpeed;  // 3 + 0.5 = 3.5
this.actualFloor = floorLift;
humans(ID).actualFloor = floorLift;  // Human na patře 3.7?
```

**PO:**
```php
class Lift
{
    private int $currentFloor;          // Diskrétní patro (1, 2, 3, ...)
    private ?int $targetFloor = null;
    private float $progress = 0.0;      // 0.0 = na patře, 1.0 = téměř na dalším
    private float $speed;                // Pater za tick (0.1 - 1.0)

    public function move(): void
    {
        if ($this->targetFloor === null) {
            return;  // Idle
        }

        $direction = $this->targetFloor > $this->currentFloor ? 1 : -1;

        // Pohyb
        $this->progress += $this->speed;

        // Dosažení patra
        if ($this->progress >= 1.0) {
            $this->currentFloor += $direction;
            $this->progress = 0.0;

            if ($this->currentFloor === $this->targetFloor) {
                $this->handleArrival();
            }
        }
    }

    public function getCurrentFloor(): int
    {
        return $this->currentFloor;  // Vždy integer!
    }

    public function getPosition(): float
    {
        // Pro vizualizaci: pozice mezi patry
        $direction = $this->targetFloor > $this->currentFloor ? 1 : -1;
        return $this->currentFloor + ($this->progress * $direction);
    }
}

class Human
{
    private int $currentFloor;  // Vždy na konkrétním patře (integer)
    private ?Lift $inLift = null;

    public function getCurrentFloor(): int
    {
        if ($this->inLift !== null) {
            return $this->inLift->getCurrentFloor();  // Patro výtahu
        }

        return $this->currentFloor;
    }
}
```

**Výhody:**
- ✅ `currentFloor` vždy integer - žádná ambiguita
- ✅ `progress` pro smooth animaci
- ✅ Žádné floating point comparison issues
- ✅ Human je vždy na konkrétním patře

---

### 9.10 ✅ Proper Encapsulation

**PŘED:**
```matlab
% Téměř všechno accessible všem pomocí friend classes
properties (Access = {?View, ?Controller, ?GUI, ?Simulation, ?StateSpace})
```

**PO:**
```php
// Strict encapsulation
class Lift
{
    // Private properties
    private int $currentFloor;
    private LiftState $state;
    private array $passengers = [];

    // Public API pouze pro nutné operace
    public function getCurrentFloor(): int
    {
        return $this->currentFloor;
    }

    public function getState(): LiftState
    {
        return $this->state;
    }

    public function getOccupancy(): int
    {
        return count($this->passengers);
    }

    // Pro vizualizaci - read-only snapshot
    public function toSnapshot(): LiftSnapshot
    {
        return new LiftSnapshot(
            id: $this->id,
            currentFloor: $this->currentFloor,
            state: $this->state,
            direction: $this->direction,
            occupancy: count($this->passengers),
            capacity: $this->capacity,
        );
    }
}

// Read-only DTO pro external consumption
readonly class LiftSnapshot
{
    public function __construct(
        public int $id,
        public int $currentFloor,
        public LiftState $state,
        public Direction $direction,
        public int $occupancy,
        public int $capacity,
    ) {}
}
```

**Výhody:**
- ✅ True encapsulation
- ✅ Immutable snapshots pro reading
- ✅ Clear API boundaries
- ✅ Nemožnost přímé modifikace

---

## 📊 10. Srovnání: Před vs. Po

| Aspekt | MATLAB (Před) | PHP 8.4 (Po) | Zlepšení |
|--------|---------------|--------------|----------|
| **Architektura** | God objects, tight coupling | Hexagonal, SOLID | ⭐⭐⭐⭐⭐ |
| **Separace concerns** | Simulace + GUI mixed | Domain oddělený od infra | ⭐⭐⭐⭐⭐ |
| **State management** | 7 stavů s hacky | 4 stavy + explicit flags | ⭐⭐⭐⭐ |
| **Pathfinding** | O(V²), zbytečná Dijkstra pro random | O(E log V), efektivní | ⭐⭐⭐⭐⭐ |
| **Queue ops** | O(n) linear search | O(1) hash map | ⭐⭐⭐⭐⭐ |
| **Event handling** | Modify-during-iteration | Collect-then-modify | ⭐⭐⭐⭐ |
| **Duplicity** | 40+ řádků 2x | Zero duplicity (Strategy) | ⭐⭐⭐⭐⭐ |
| **Reporting** | Mixed in domain | Separate generators | ⭐⭐⭐⭐⭐ |
| **Type safety** | MATLAB dynamic | PHP 8.4 strict types | ⭐⭐⭐⭐ |
| **Testability** | Těžké (GUI required) | Snadné (unit tests) | ⭐⭐⭐⭐⭐ |
| **Async support** | Blocking loop | Generator/WebSocket | ⭐⭐⭐⭐⭐ |
| **Encapsulation** | Friend classes everywhere | Proper private + snapshots | ⭐⭐⭐⭐ |

---

## 🎯 11. Priority pro Implementaci

### Kritické (Must Have)
1. ✅ **Oddělení simulace od vizualizace** - základ architektury
2. ✅ **Rozbití God object** - nutné pro maintainability
3. ✅ **Odstranění duplicity** - Strategy pattern
4. ✅ **Fix floating point floors** - prevence bugů

### Vysoká (Should Have)
5. ✅ **Efektivní queue management** - performance
6. ✅ **Proper state management** - méně stavů, čistší logika
7. ✅ **Oddělení reportingu** - flexibility

### Střední (Nice to Have)
8. ✅ **Optimalizace Dijkstra** - performance pro velké budovy
9. ✅ **Event handling fix** - prevence edge cases
10. ✅ **Encapsulation** - better API

---

## 🚀 12. Další Kroky

### Fáze 1: Core Architecture
```bash
1. Setup PHP 8.4 projektu
2. Implementovat základní domain modely (Building, Lift, Human)
3. SimulationEngine s Generator pattern
4. Testy pro core logiku
```

### Fáze 2: Algorithms
```bash
5. PathFinder interface + Random/Dijkstra implementace
6. Queue management (HumanQueue, LiftQueue)
7. Orchestrátory (LiftOrchestrator, HumanOrchestrator)
```

### Fáze 3: Infrastructure
```bash
8. Persistence (Doctrine entities)
9. HTTP API endpoints
10. WebSocket real-time server
```

### Fáze 4: Reporting
```bash
11. StatisticsCalculator
12. Report generators (HTML/JSON/PDF)
13. Chart generation (Chart.js integration)
```

---

## ✅ Závěr

Současná MATLAB implementace má **významné architektonické problémy**:

1. 🔴 **Tight coupling** simulace s GUI
2. 🔴 **God objects** (Simulation 1095 řádků)
3. 🔴 **Duplicitní kód** (2x stejné switch cases)
4. 🔴 **Inefficient algorithms** (O(V²) Dijkstra, O(n) queues)
5. 🔴 **State management hacky** (floorHold, newWaiting)
6. 🔴 **Mixed concerns** (domain generuje HTML)
7. 🔴 **Floating point floors** (confusing)

**Navrhovaná PHP 8.4 implementace tyto problémy řeší:**

✅ Hexagonal architektura
✅ SOLID principles
✅ Efficient data structures (O(1) operations)
✅ Clean state management
✅ Strategy pattern pro algoritmy
✅ Separation of Concerns
✅ Type safety
✅ Testability
✅ Real-time capability

**Kód bude čistější, rychlejší, maintainovější a škálovatelný.** 🚀
