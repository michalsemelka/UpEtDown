# Migrační plán: UpEtDown → PHP 8.4 Web Aplikace

> **Projekt:** Simulátor výtahových systémů ve výškových budovách
> **Původní technologie:** MATLAB (2015a, 2016b)
> **Cílové technologie:** PHP 8.4, Symfony, Vanilla JS/Stimulus JS

---

## 📋 Obsah

1. [Analýza současného stavu](#1-analýza-současného-stavu)
2. [Architektura cílového řešení](#2-architektura-cílového-řešení)
3. [Backend - PHP 8.4](#3-backend---php-84)
4. [Frontend - Modern Lightweight Stack](#4-frontend---modern-lightweight-stack)
5. [Databáze a persistence](#5-databáze-a-persistence)
6. [DevOps a deployment](#6-devops-a-deployment)
7. [Migrační kroky](#7-migrační-kroky)
8. [Testování](#8-testování)
9. [Dokumentace](#9-dokumentace)

---

## 1. Analýza současného stavu

### 1.1 Současná struktura projektu

```
UpEtDown/
├── source/
│   ├── index.m (entrypoint)
│   └── app/
│       ├── Building.m      → Model budovy s patry
│       ├── Lift.m          → Model výtahu (fronta, stavy, události)
│       ├── Human.m         → Model návštěvníka (cesta, čekání)
│       ├── Simulation.m    → Hlavní simulační engine
│       ├── StateSpace.m    → Stavový prostor pro pathfinding
│       ├── Controller.m    → Řízení simulace
│       ├── View.m          → Vizualizace
│       ├── GUI.m           → MATLAB GUI
│       ├── States.m        → Enumerace stavů
│       └── assets/         → HTML templates, obrázky
└── test_cases/             → Testovací konfigurace (.mat, .txt)
```

### 1.2 Klíčové funkce

- **Diskrétní simulace** výtahového systému (časové kroky)
- **Dva řídicí algoritmy:**
  - Random (náhodný výběr výtahu)
  - Dijkstra Scheduler (optimální výběr podle nákladů)
- **Event-driven architektura:**
  - `liftOnFloor` - výtah dorazil na patro
  - `humanFinished` - návštěvník dokončil cestu
  - `finished` - simulace skončila
- **Vizualizace v reálném čase** pohybu výtahů
- **Generování reportů:**
  - Histogramy příchodů návštěvníků
  - Grafy čekacích dob
  - Statistiky (průměr, max, min, směrodatná odchylka)
  - HTML výstup s embedding grafů

### 1.3 Datové modely

**Building:**
- Počet pater
- Kolekce výtahů
- Mapování výtahů na patra

**Lift:**
- ID, baseFloor, finalFloor, actualFloor
- deniedFloors (zakázaná patra)
- capacity (kapacita), speed (rychlost)
- queueUp, queueDown (fronty požadavků)
- state (idle/moving/stop), direction (up/down/free)
- humansInLift (návštěvníci ve výtahu)

**Human:**
- ID, startFloor, desiredFloor, actualFloor
- path (cesta s přestupy)
- state (floor/waiting/lift/finished)
- timeStart, timeStop, timeQueue, timeTravel

**Simulation:**
- Orchestruje Building, Lifts, Humans
- Spravuje waitingList, floorList
- Timestamp (iterace simulace)
- SystemBehavior (random/dijkstra)

---

## 2. Architektura cílového řešení

### 2.1 Celkový stack

```
┌─────────────────────────────────────────────────────┐
│                    FRONTEND                          │
│  Vanilla JS / Stimulus JS + Modern CSS              │
│  ├─ Canvas/SVG vizualizace výtahů                   │
│  ├─ Chart.js pro grafy                              │
│  ├─ WebSocket klient (pro real-time update)         │
│  └─ Form handling (konfigurace budovy)              │
└─────────────────────────────────────────────────────┘
                        ↕ HTTP/WebSocket
┌─────────────────────────────────────────────────────┐
│                 WEB SERVER                           │
│  Nginx + PHP-FPM 8.4                                │
└─────────────────────────────────────────────────────┘
                        ↕
┌─────────────────────────────────────────────────────┐
│              BACKEND - PHP 8.4                       │
│  Symfony 7.x Components                             │
│  ├─ HTTP Layer (HttpFoundation, Routing)            │
│  ├─ Domain Layer (Simulation Engine)                │
│  ├─ Application Layer (Commands, Queries)           │
│  ├─ Infrastructure Layer (Persistence, WebSocket)   │
│  └─ EventDispatcher (pro event-driven simulaci)     │
└─────────────────────────────────────────────────────┘
                        ↕
┌─────────────────────────────────────────────────────┐
│                   DATABASE                           │
│  PostgreSQL 16+ / SQLite (pro jednoduchost)         │
│  ├─ Konfigurace simulací                            │
│  ├─ Historie simulací                               │
│  └─ Statistiky                                      │
└─────────────────────────────────────────────────────┘
```

### 2.2 Hexagonální architektura (Ports & Adapters)

```
src/
├── Domain/                          # Business logika (čisté PHP)
│   ├── Model/
│   │   ├── Building.php
│   │   ├── Lift.php
│   │   ├── Human.php
│   │   ├── Simulation.php
│   │   └── StateSpace.php
│   ├── Enum/
│   │   ├── LiftState.php          # PHP 8.4 enum
│   │   ├── Direction.php
│   │   └── HumanState.php
│   ├── Event/
│   │   ├── LiftOnFloor.php
│   │   ├── HumanFinished.php
│   │   └── SimulationFinished.php
│   ├── Service/
│   │   ├── SimulationEngine.php
│   │   ├── PathFinder.php          # Dijkstra, Random
│   │   └── StatisticsCalculator.php
│   └── Exception/
│       └── SimulationException.php
│
├── Application/                     # Use cases
│   ├── Command/
│   │   ├── CreateSimulation.php
│   │   ├── RunSimulation.php
│   │   └── GenerateReport.php
│   ├── Query/
│   │   ├── GetSimulationStatus.php
│   │   └── GetStatistics.php
│   └── Handler/
│       ├── CreateSimulationHandler.php
│       └── RunSimulationHandler.php
│
├── Infrastructure/                  # Framework, třetí strany
│   ├── Persistence/
│   │   ├── Doctrine/
│   │   │   ├── Entity/            # Doctrine entity pro DB
│   │   │   └── Repository/
│   │   └── Redis/                 # Cache pro běžící simulace
│   ├── WebSocket/
│   │   └── RatchetServer.php     # Real-time komunikace
│   ├── Http/
│   │   ├── Controller/
│   │   │   ├── SimulationController.php
│   │   │   └── ReportController.php
│   │   └── Middleware/
│   └── EventListener/
│       └── SimulationEventSubscriber.php
│
└── Presentation/                    # Templates, Assets
    ├── templates/
    │   ├── simulation/
    │   │   ├── configure.html.twig
    │   │   ├── visualize.html.twig
    │   │   └── report.html.twig
    │   └── base.html.twig
    └── assets/
        ├── js/
        │   ├── controllers/        # Stimulus controllers
        │   │   ├── simulation_controller.js
        │   │   └── visualization_controller.js
        │   └── utils/
        │       ├── websocket.js
        │       └── canvas-renderer.js
        └── css/
            ├── app.css
            └── components/
```

---

## 3. Backend - PHP 8.4

### 3.1 Využití PHP 8.4+ features

#### **Readonly classes & properties**
```php
<?php

declare(strict_types=1);

namespace App\Domain\Model;

readonly class BuildingConfiguration
{
    public function __construct(
        public int $numberOfFloors,
        public array $lifts,  // PHP 8.4: typed array hints plánované
        public string $name,
    ) {}
}
```

#### **Enums pro stavy**
```php
<?php

namespace App\Domain\Enum;

enum LiftState: string
{
    case IDLE = 'idle';
    case MOVING = 'moving';
    case STOP = 'stop';
    case DNS = 'dns';  // Do Not Stop

    public function isMoving(): bool
    {
        return $this === self::MOVING;
    }
}

enum Direction: string
{
    case UP = 'up';
    case DOWN = 'down';
    case FREE = 'free';

    public function opposite(): self
    {
        return match($this) {
            self::UP => self::DOWN,
            self::DOWN => self::UP,
            self::FREE => self::FREE,
        };
    }
}
```

#### **Constructor Property Promotion + Typed Properties**
```php
<?php

namespace App\Domain\Model;

class Lift
{
    private array $queueUp = [];
    private array $queueDown = [];
    private array $humansInLift = [];

    public function __construct(
        private readonly int $id,
        private readonly int $baseFloor,
        private readonly int $finalFloor,
        private readonly array $deniedFloors,
        private readonly int $capacity,
        private readonly float $speed,
        private int $actualFloor,
        private LiftState $state = LiftState::IDLE,
        private Direction $direction = Direction::FREE,
    ) {
        $this->actualFloor = $baseFloor;
    }

    public function addToQueue(int $floor, Direction $direction, bool $fromInside): void
    {
        // Implementace fronty
        match($direction) {
            Direction::UP => $this->queueUp[] = $floor,
            Direction::DOWN => $this->queueDown[] = $floor,
            Direction::FREE => null,
        };

        $this->queueUp = array_unique($this->queueUp);
        sort($this->queueUp);
    }

    public function isFull(): bool
    {
        return count($this->humansInLift) >= $this->capacity;
    }
}
```

#### **First-class Callable Syntax**
```php
<?php

// PHP 8.1+
$pathFinders = [
    'random' => $this->findRandomPath(...),
    'dijkstra' => $this->findDijkstraPath(...),
];

$path = $pathFinders[$algorithm]($start, $end);
```

#### **Attributes pro validaci**
```php
<?php

use Symfony\Component\Validator\Constraints as Assert;

class SimulationRequest
{
    #[Assert\Range(min: 2, max: 100)]
    public int $numberOfFloors;

    #[Assert\Count(min: 1, max: 10)]
    #[Assert\Valid]
    public array $lifts;

    #[Assert\Choice(['random', 'dijkstra'])]
    public string $algorithm;
}
```

### 3.2 Symfony komponenty (standalone)

**Místo celého Symfony frameworku použijeme pouze potřebné komponenty:**

```json
{
  "require": {
    "php": "^8.4",
    "symfony/http-foundation": "^7.1",
    "symfony/routing": "^7.1",
    "symfony/event-dispatcher": "^7.1",
    "symfony/serializer": "^7.1",
    "symfony/validator": "^7.1",
    "symfony/console": "^7.1",
    "symfony/cache": "^7.1",
    "doctrine/orm": "^3.0",
    "cboden/ratchet": "^0.4",  // WebSocket server
    "ramsey/uuid": "^4.7"
  },
  "require-dev": {
    "phpunit/phpunit": "^11.0",
    "phpstan/phpstan": "^1.10",
    "friendsofphp/php-cs-fixer": "^3.50"
  }
}
```

#### **EventDispatcher pro event-driven simulaci**
```php
<?php

namespace App\Domain\Event;

use Symfony\Contracts\EventDispatcher\Event;

class LiftOnFloorEvent extends Event
{
    public function __construct(
        public readonly int $liftId,
        public readonly int $floor,
        public readonly int $timestamp,
    ) {}
}

// Listener
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class LiftEventSubscriber implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            LiftOnFloorEvent::class => 'onLiftOnFloor',
            HumanFinishedEvent::class => 'onHumanFinished',
        ];
    }

    public function onLiftOnFloor(LiftOnFloorEvent $event): void
    {
        // Zpracování události: vysazení lidí z výtahu
        // Broadcast přes WebSocket pro vizualizaci
    }
}
```

### 3.3 Simulační engine

**Hlavní simulační smyčka:**
```php
<?php

namespace App\Domain\Service;

use App\Domain\Model\Simulation;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;

class SimulationEngine
{
    public function __construct(
        private readonly EventDispatcherInterface $eventDispatcher,
        private readonly PathFinderInterface $pathFinder,
    ) {}

    public function run(Simulation $simulation): SimulationResult
    {
        while (!$simulation->isFinished()) {
            $simulation->incrementTimestamp();

            // 1. Zkontrolovat nové návštěvníky
            $this->checkForNewHumans($simulation);

            // 2. Pohyb výtahů
            $this->moveLifts($simulation);

            // 3. Simulace čekajících návštěvníků
            $this->checkHumansWaiting($simulation);

            // 4. Výběr dalšího patra pro výtahy
            $this->selectNextFloors($simulation);

            // Events jsou dispatchovány během simulace

            // Yield pro async/streaming výstupy
            yield [
                'timestamp' => $simulation->getTimestamp(),
                'lifts' => $simulation->getLiftsState(),
                'waitingHumans' => $simulation->getWaitingCount(),
            ];
        }

        return $this->generateStatistics($simulation);
    }

    private function moveLifts(Simulation $simulation): void
    {
        foreach ($simulation->getBuilding()->getLifts() as $lift) {
            $previousFloor = $lift->getActualFloor();
            $lift->move();

            if ($previousFloor !== $lift->getActualFloor()) {
                $this->eventDispatcher->dispatch(
                    new LiftOnFloorEvent(
                        $lift->getId(),
                        $lift->getActualFloor(),
                        $simulation->getTimestamp()
                    )
                );
            }
        }
    }
}
```

### 3.4 Pathfinding algoritmy

```php
<?php

namespace App\Domain\Service;

interface PathFinderInterface
{
    public function findPath(
        int $startFloor,
        int $desiredFloor,
        array $availableLifts
    ): Path;
}

class RandomPathFinder implements PathFinderInterface
{
    public function findPath(
        int $startFloor,
        int $desiredFloor,
        array $availableLifts
    ): Path {
        // Náhodný výběr dostupného výtahu
        $lift = $availableLifts[array_rand($availableLifts)];

        return new Path(
            floor: $startFloor,
            lift: $lift->getId(),
            finalFloor: $desiredFloor,
        );
    }
}

class DijkstraPathFinder implements PathFinderInterface
{
    public function findPath(
        int $startFloor,
        int $desiredFloor,
        array $availableLifts
    ): Path {
        // Výpočet nákladů pro každý výtah
        $costs = [];
        foreach ($availableLifts as $lift) {
            $costs[$lift->getId()] = $this->calculateCost(
                $lift,
                $startFloor,
                $desiredFloor
            );
        }

        // Výběr s minimální náklady
        $bestLiftId = array_search(min($costs), $costs);

        return new Path(
            floor: $startFloor,
            lift: $bestLiftId,
            finalFloor: $desiredFloor,
        );
    }

    private function calculateCost(Lift $lift, int $humanFloor, int $desiredFloor): float
    {
        // Implementace z MATLAB kódu (řádky 254-265)
        $direction = $desiredFloor > $humanFloor ? Direction::UP : Direction::DOWN;

        if ($humanFloor === $lift->getActualFloor()
            && !$lift->isFull()
            && ($lift->getState()->isIdle() || $lift->getState() === LiftState::STOP)
        ) {
            return 2.0;
        }

        $y = -$lift->getSpeed() + 0.7;
        $d = abs($lift->getActualFloor() - $humanFloor) * 0.1;

        if ($lift->getState()->isIdle() && !$lift->isFull()) {
            return 3.0 + $y + $d;
        }

        return 10.0 + $y + $d;
    }
}
```

---

## 4. Frontend - Modern Lightweight Stack

### 4.1 Technologie

- **Pure CSS** (bez frameworků)
  - CSS Grid & Flexbox
  - CSS Variables pro theming
  - CSS Animations pro smooth transitions
  - Container Queries (moderní responsive design)

- **Vanilla JavaScript** + **Stimulus JS** (od tvůrců Rails)
  - Malá footprint (~35KB)
  - HTML-centric approach
  - Perfektní pro interaktivní komponenty

- **Chart.js** pro grafy
- **WebSocket API** pro real-time updates

### 4.2 Struktura frontend assets

```
assets/
├── css/
│   ├── app.css                    # Globální styly
│   ├── components/
│   │   ├── building.css           # Vizualizace budovy
│   │   ├── lift.css               # Styly výtahu
│   │   ├── forms.css              # Formuláře konfigurace
│   │   └── stats.css              # Statistiky
│   └── utilities.css              # Helper classes
│
├── js/
│   ├── app.js                     # Bootstrap
│   ├── controllers/               # Stimulus controllers
│   │   ├── simulation_controller.js
│   │   ├── building_controller.js
│   │   ├── lift_controller.js
│   │   └── chart_controller.js
│   ├── services/
│   │   ├── websocket-client.js
│   │   └── api-client.js
│   └── lib/
│       ├── stimulus.js
│       └── chart.esm.js
│
└── templates/
    ├── base.html.twig
    ├── simulation/
    │   ├── configure.html.twig
    │   ├── running.html.twig
    │   └── report.html.twig
    └── components/
        ├── building-canvas.html.twig
        └── stats-panel.html.twig
```

### 4.3 Stimulus controller příklady

#### **Simulation Controller**
```javascript
// assets/js/controllers/simulation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "timestamp", "progress"]
  static values = {
    url: String,
    simulationId: String
  }

  connect() {
    this.initializeWebSocket()
  }

  disconnect() {
    this.closeWebSocket()
  }

  start() {
    fetch(this.urlValue, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: this.simulationIdValue })
    })
      .then(response => response.json())
      .then(data => {
        this.statusTarget.textContent = "Running..."
        this.statusTarget.classList.add("status--running")
      })
  }

  pause() {
    this.ws?.send(JSON.stringify({ action: 'pause' }))
  }

  stop() {
    this.ws?.send(JSON.stringify({ action: 'stop' }))
    this.statusTarget.textContent = "Stopped"
    this.statusTarget.classList.remove("status--running")
  }

  initializeWebSocket() {
    this.ws = new WebSocket(`ws://localhost:8080/simulation/${this.simulationIdValue}`)

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      this.handleSimulationUpdate(data)
    }

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error)
    }
  }

  handleSimulationUpdate(data) {
    // Update timestamp
    if (this.hasTimestampTarget) {
      this.timestampTarget.textContent = data.timestamp
    }

    // Update progress
    if (this.hasProgressTarget && data.progress) {
      this.progressTarget.style.width = `${data.progress}%`
    }

    // Dispatch custom event pro ostatní controllery
    this.dispatch("update", { detail: data })
  }

  closeWebSocket() {
    this.ws?.close()
  }
}
```

#### **Building Visualization Controller**
```javascript
// assets/js/controllers/building_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    floors: Number,
    lifts: Array
  }

  connect() {
    this.canvas = this.canvasTarget
    this.ctx = this.canvas.getContext('2d')
    this.resizeCanvas()
    this.initializeBuilding()

    // Listen to simulation updates
    this.element.addEventListener('simulation:update', this.handleUpdate.bind(this))
  }

  resizeCanvas() {
    const rect = this.canvas.parentElement.getBoundingClientRect()
    this.canvas.width = rect.width
    this.canvas.height = rect.height
  }

  initializeBuilding() {
    this.floorHeight = this.canvas.height / this.floorsValue
    this.liftWidth = 40
    this.liftSpacing = 60

    this.drawBuilding()
  }

  drawBuilding() {
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

    // Draw floors
    for (let i = 0; i < this.floorsValue; i++) {
      const y = this.canvas.height - (i + 1) * this.floorHeight

      // Floor line
      this.ctx.strokeStyle = '#333'
      this.ctx.lineWidth = 2
      this.ctx.beginPath()
      this.ctx.moveTo(0, y)
      this.ctx.lineTo(this.canvas.width, y)
      this.ctx.stroke()

      // Floor number
      this.ctx.fillStyle = '#666'
      this.ctx.font = '14px sans-serif'
      this.ctx.fillText(`Floor ${i + 1}`, 10, y + 20)
    }
  }

  drawLifts() {
    this.liftsValue.forEach((lift, index) => {
      const x = 100 + index * this.liftSpacing
      const y = this.canvas.height - (lift.actualFloor * this.floorHeight) - this.floorHeight / 2

      // Lift cabin
      this.ctx.fillStyle = this.getLiftColor(lift.state)
      this.ctx.fillRect(x, y - 20, this.liftWidth, 40)

      // Lift border
      this.ctx.strokeStyle = '#000'
      this.ctx.lineWidth = 2
      this.ctx.strokeRect(x, y - 20, this.liftWidth, 40)

      // Direction indicator
      this.drawDirectionArrow(x + this.liftWidth / 2, y, lift.direction)

      // Occupancy
      this.ctx.fillStyle = '#fff'
      this.ctx.font = '12px sans-serif'
      this.ctx.textAlign = 'center'
      this.ctx.fillText(`${lift.occupancy}/${lift.capacity}`, x + this.liftWidth / 2, y + 5)
    })
  }

  getLiftColor(state) {
    return {
      'idle': '#cccccc',
      'moving': '#4CAF50',
      'stop': '#FFC107',
      'dns': '#F44336'
    }[state] || '#cccccc'
  }

  drawDirectionArrow(x, y, direction) {
    this.ctx.fillStyle = '#000'
    this.ctx.beginPath()

    if (direction === 'up') {
      this.ctx.moveTo(x, y - 30)
      this.ctx.lineTo(x - 5, y - 25)
      this.ctx.lineTo(x + 5, y - 25)
    } else if (direction === 'down') {
      this.ctx.moveTo(x, y + 30)
      this.ctx.lineTo(x - 5, y + 25)
      this.ctx.lineTo(x + 5, y + 25)
    }

    this.ctx.fill()
  }

  handleUpdate(event) {
    const data = event.detail
    this.liftsValue = data.lifts
    this.drawBuilding()
    this.drawLifts()
  }
}
```

### 4.4 CSS příklad (moderní přístup)

```css
/* assets/css/app.css */
:root {
  /* Color palette */
  --color-primary: #2563eb;
  --color-secondary: #64748b;
  --color-success: #10b981;
  --color-warning: #f59e0b;
  --color-danger: #ef4444;

  /* Spacing */
  --space-xs: 0.25rem;
  --space-sm: 0.5rem;
  --space-md: 1rem;
  --space-lg: 1.5rem;
  --space-xl: 2rem;

  /* Typography */
  --font-sans: system-ui, -apple-system, sans-serif;
  --font-mono: 'Courier New', monospace;
}

/* Modern reset */
*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  font-family: var(--font-sans);
  line-height: 1.6;
  color: #1f2937;
  background-color: #f9fafb;
}

/* Layout - CSS Grid */
.app-layout {
  display: grid;
  grid-template-areas:
    "header header"
    "sidebar main"
    "footer footer";
  grid-template-columns: 250px 1fr;
  grid-template-rows: auto 1fr auto;
  min-height: 100vh;
}

.app-header { grid-area: header; }
.app-sidebar { grid-area: sidebar; }
.app-main { grid-area: main; }
.app-footer { grid-area: footer; }

/* Container Queries (moderní!) */
.simulation-panel {
  container-type: inline-size;
}

@container (min-width: 600px) {
  .simulation-controls {
    display: flex;
    gap: var(--space-md);
  }
}

/* Components */
.lift-card {
  background: white;
  border-radius: 8px;
  padding: var(--space-lg);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  transition: transform 0.2s, box-shadow 0.2s;
}

.lift-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

/* Status indicators */
.status {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  border-radius: 9999px;
  font-size: 0.875rem;
  font-weight: 600;
}

.status::before {
  content: '';
  display: block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  animation: pulse 2s infinite;
}

.status--running {
  background-color: #dcfce7;
  color: #166534;
}

.status--running::before {
  background-color: #22c55e;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

/* Building visualization */
.building-canvas {
  width: 100%;
  height: 600px;
  border: 2px solid #e5e7eb;
  border-radius: 8px;
  background: linear-gradient(to bottom, #f9fafb 0%, #f3f4f6 100%);
}

/* Charts */
.chart-container {
  position: relative;
  height: 400px;
  padding: var(--space-lg);
  background: white;
  border-radius: 8px;
}

/* Utility classes */
.flex { display: flex; }
.flex-col { flex-direction: column; }
.gap-md { gap: var(--space-md); }
.p-lg { padding: var(--space-lg); }
.text-center { text-align: center; }

/* Dark mode support */
@media (prefers-color-scheme: dark) {
  :root {
    --color-bg: #1f2937;
    --color-text: #f9fafb;
  }

  body {
    background-color: var(--color-bg);
    color: var(--color-text);
  }
}
```

---

## 5. Databáze a persistence

### 5.1 Schema (PostgreSQL)

```sql
-- Konfigurace simulací
CREATE TABLE simulations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    number_of_floors INT NOT NULL CHECK (number_of_floors > 0),
    algorithm VARCHAR(50) NOT NULL CHECK (algorithm IN ('random', 'dijkstra')),
    status VARCHAR(50) NOT NULL DEFAULT 'configured',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    CONSTRAINT valid_status CHECK (status IN ('configured', 'running', 'paused', 'finished'))
);

-- Konfigurace výtahů
CREATE TABLE lifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    simulation_id UUID NOT NULL REFERENCES simulations(id) ON DELETE CASCADE,
    lift_number INT NOT NULL,
    base_floor INT NOT NULL,
    final_floor INT NOT NULL,
    denied_floors INT[] DEFAULT '{}',
    capacity INT NOT NULL CHECK (capacity > 0),
    speed DECIMAL(3,2) NOT NULL CHECK (speed > 0 AND speed <= 1.0),
    idle_to_base BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT unique_lift_per_simulation UNIQUE (simulation_id, lift_number)
);

-- Seznam návštěvníků
CREATE TABLE humans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    simulation_id UUID NOT NULL REFERENCES simulations(id) ON DELETE CASCADE,
    arrival_time INT NOT NULL,
    start_floor INT NOT NULL,
    desired_floor INT NOT NULL,
    CHECK (start_floor != desired_floor)
);

CREATE INDEX idx_humans_arrival ON humans(simulation_id, arrival_time);

-- Statistiky simulace
CREATE TABLE simulation_statistics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    simulation_id UUID NOT NULL REFERENCES simulations(id) ON DELETE CASCADE UNIQUE,
    total_humans INT NOT NULL,
    average_waiting_time DECIMAL(10,2),
    max_waiting_time DECIMAL(10,2),
    min_waiting_time DECIMAL(10,2),
    average_travel_time DECIMAL(10,2),
    total_floors_traveled INT,
    most_busy_lift_id UUID REFERENCES lifts(id),
    report_generated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Historie pohybu výtahů (pro replay)
CREATE TABLE lift_history (
    id BIGSERIAL PRIMARY KEY,
    simulation_id UUID NOT NULL REFERENCES simulations(id) ON DELETE CASCADE,
    lift_id UUID NOT NULL REFERENCES lifts(id) ON DELETE CASCADE,
    timestamp INT NOT NULL,
    floor INT NOT NULL,
    state VARCHAR(20) NOT NULL,
    direction VARCHAR(20) NOT NULL,
    occupancy INT NOT NULL
);

CREATE INDEX idx_lift_history ON lift_history(simulation_id, timestamp);
```

### 5.2 Doctrine Entity příklady

```php
<?php

namespace App\Infrastructure\Persistence\Doctrine\Entity;

use Doctrine\ORM\Mapping as ORM;
use Ramsey\Uuid\Uuid;
use Ramsey\Uuid\UuidInterface;

#[ORM\Entity]
#[ORM\Table(name: 'simulations')]
class SimulationEntity
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid')]
    private UuidInterface $id;

    #[ORM\Column(type: 'string', length: 255)]
    private string $name;

    #[ORM\Column(type: 'integer')]
    private int $numberOfFloors;

    #[ORM\Column(type: 'string', length: 50)]
    private string $algorithm;

    #[ORM\Column(type: 'string', length: 50)]
    private string $status = 'configured';

    #[ORM\Column(type: 'datetime_immutable')]
    private \DateTimeImmutable $createdAt;

    #[ORM\OneToMany(mappedBy: 'simulation', targetEntity: LiftEntity::class, cascade: ['persist'])]
    private Collection $lifts;

    public function __construct(string $name, int $numberOfFloors, string $algorithm)
    {
        $this->id = Uuid::uuid4();
        $this->name = $name;
        $this->numberOfFloors = $numberOfFloors;
        $this->algorithm = $algorithm;
        $this->createdAt = new \DateTimeImmutable();
        $this->lifts = new ArrayCollection();
    }

    // Getters...
}
```

### 5.3 Redis pro běžící simulace (in-memory state)

```php
<?php

namespace App\Infrastructure\Persistence\Redis;

use Predis\Client;

class SimulationStateRepository
{
    public function __construct(
        private readonly Client $redis
    ) {}

    public function save(string $simulationId, array $state): void
    {
        $this->redis->setex(
            "simulation:$simulationId",
            3600, // TTL 1 hodina
            json_encode($state)
        );
    }

    public function get(string $simulationId): ?array
    {
        $data = $this->redis->get("simulation:$simulationId");
        return $data ? json_decode($data, true) : null;
    }

    public function delete(string $simulationId): void
    {
        $this->redis->del("simulation:$simulationId");
    }
}
```

---

## 6. DevOps a deployment

### 6.1 Docker setup

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./public:/var/www/html/public:ro
    depends_on:
      - php

  php:
    build:
      context: .
      dockerfile: docker/php/Dockerfile
    volumes:
      - .:/var/www/html
    environment:
      DATABASE_URL: "postgresql://user:pass@postgres:5432/upetdown"
      REDIS_URL: "redis://redis:6379"

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: upetdown
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  websocket:
    build:
      context: .
      dockerfile: docker/php/Dockerfile
    command: php bin/websocket-server.php
    ports:
      - "8080:8080"
    depends_on:
      - redis

volumes:
  postgres_data:
```

**docker/php/Dockerfile:**
```dockerfile
FROM php:8.4-fpm-alpine

# Install extensions
RUN apk add --no-cache \
    postgresql-dev \
    $PHPIZE_DEPS \
    && docker-php-ext-install pdo pdo_pgsql opcache \
    && pecl install redis \
    && docker-php-ext-enable redis

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# PHP config
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# OPcache config for production
RUN echo "opcache.enable=1" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.memory_consumption=256" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.max_accelerated_files=20000" >> /usr/local/etc/php/conf.d/opcache.ini

WORKDIR /var/www/html

USER www-data
```

### 6.2 CI/CD (GitHub Actions)

**.github/workflows/ci.yml:**
```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.4'
          extensions: pdo_pgsql, redis
          coverage: xdebug

      - name: Install dependencies
        run: composer install --prefer-dist --no-progress

      - name: Run PHPStan
        run: vendor/bin/phpstan analyse src tests

      - name: Run PHP CS Fixer
        run: vendor/bin/php-cs-fixer fix --dry-run --diff

      - name: Run PHPUnit
        run: vendor/bin/phpunit --coverage-text

      - name: Run frontend tests
        run: npm test

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t upetdown:latest .

      - name: Push to registry
        run: |
          echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin
          docker push upetdown:latest
```

---

## 7. Migrační kroky

### Fáze 1: Příprava (2 týdny)

- [ ] **Setup projektu**
  - [x] Inicializace Git repository
  - [ ] Vytvoření Docker environment
  - [ ] Setup Composer a závislostí
  - [ ] Setup npm pro frontend
  - [ ] CI/CD konfigurace

- [ ] **Analýza a design**
  - [ ] Detailní mapování MATLAB → PHP konverzí
  - [ ] Databázové schema design
  - [ ] API design (REST endpoints, WebSocket protokol)
  - [ ] UI/UX wireframes

### Fáze 2: Backend Core (4 týdny)

- [ ] **Domain layer**
  - [ ] Implementace `Building`, `Lift`, `Human` modelů
  - [ ] Enum třídy (`LiftState`, `Direction`, `HumanState`)
  - [ ] Value objects (`Path`, `Queue`, atd.)
  - [ ] Domain events (`LiftOnFloor`, `HumanFinished`, atd.)

- [ ] **Simulační engine**
  - [ ] `SimulationEngine` - hlavní smyčka
  - [ ] `PathFinder` interface a implementace (Random, Dijkstra)
  - [ ] `StatisticsCalculator`
  - [ ] Event handling s Symfony EventDispatcher

- [ ] **Application layer**
  - [ ] Commands: `CreateSimulation`, `RunSimulation`, `PauseSimulation`
  - [ ] Queries: `GetSimulationStatus`, `GetStatistics`
  - [ ] Handlery

- [ ] **Infrastructure**
  - [ ] Doctrine entities a repositories
  - [ ] Redis state management
  - [ ] HTTP controllers
  - [ ] WebSocket server (Ratchet)

- [ ] **Testing**
  - [ ] Unit testy pro modely
  - [ ] Integration testy pro simulační engine
  - [ ] Testy pro pathfinding algoritmy

### Fáze 3: Frontend (3 týdny)

- [ ] **HTML templates (Twig)**
  - [ ] Layout a base template
  - [ ] Konfigurace simulace (formulář)
  - [ ] Vizualizace běžící simulace
  - [ ] Report display

- [ ] **CSS**
  - [ ] Design system (variables, typography, colors)
  - [ ] Layout komponenty
  - [ ] Building visualization styles
  - [ ] Responsive design
  - [ ] Dark mode

- [ ] **JavaScript (Stimulus)**
  - [ ] `simulation_controller.js` - orchestrace
  - [ ] `building_controller.js` - canvas vizualizace
  - [ ] `chart_controller.js` - grafy (Chart.js)
  - [ ] WebSocket client
  - [ ] API client

- [ ] **Testing**
  - [ ] Jest testy pro JS logic
  - [ ] E2E testy (Playwright/Cypress)

### Fáze 4: Integrace a reporty (2 týdny)

- [ ] **Statistiky a reporty**
  - [ ] Výpočet statistik (average, max, min, stdev)
  - [ ] Generování HTML reportů
  - [ ] Chart.js grafy:
    - [ ] Histogram příchodů
    - [ ] Waiting times plot
  - [ ] PDF export (optional - TCPDF/Dompdf)

- [ ] **Import/Export dat**
  - [ ] Import konfigurace (JSON, CSV)
  - [ ] Import seznamu návštěvníků (CSV, TXT)
  - [ ] Export výsledků (JSON, CSV)

- [ ] **Real-time features**
  - [ ] WebSocket broadcasting
  - [ ] Live statistics update
  - [ ] Simulation replay

### Fáze 5: Optimalizace a deploy (1 týden)

- [ ] **Performance**
  - [ ] Profiling (Blackfire, Xdebug)
  - [ ] OPcache tuning
  - [ ] Redis optimalizace
  - [ ] Frontend bundling (Vite/esbuild)

- [ ] **Deployment**
  - [ ] Production Docker images
  - [ ] Database migrations
  - [ ] Environment configuration
  - [ ] Monitoring (Sentry, Prometheus)

- [ ] **Dokumentace**
  - [ ] API dokumentace (OpenAPI/Swagger)
  - [ ] User guide
  - [ ] Developer documentation
  - [ ] README, CONTRIBUTING.md

---

## 8. Testování

### 8.1 Backend tests (PHPUnit)

**tests/Unit/Domain/Model/LiftTest.php:**
```php
<?php

namespace App\Tests\Unit\Domain\Model;

use App\Domain\Enum\Direction;
use App\Domain\Enum\LiftState;
use App\Domain\Model\Lift;
use PHPUnit\Framework\TestCase;

class LiftTest extends TestCase
{
    public function testLiftCreation(): void
    {
        $lift = new Lift(
            id: 1,
            baseFloor: 1,
            finalFloor: 10,
            deniedFloors: [5, 6],
            capacity: 8,
            speed: 0.5,
            actualFloor: 1,
        );

        $this->assertSame(1, $lift->getActualFloor());
        $this->assertSame(LiftState::IDLE, $lift->getState());
        $this->assertFalse($lift->isFull());
    }

    public function testAddToQueue(): void
    {
        $lift = new Lift(/* ... */);

        $lift->addToQueue(5, Direction::UP, false);
        $lift->addToQueue(7, Direction::UP, false);

        $this->assertCount(2, $lift->getQueueUp());
    }

    public function testLiftMovement(): void
    {
        $lift = new Lift(/* ... */);
        $lift->addToQueue(5, Direction::UP, false);
        $lift->selectNextFloor();

        $this->assertSame(LiftState::MOVING, $lift->getState());
        $this->assertSame(Direction::UP, $lift->getDirection());

        // Simulate 4 moves
        for ($i = 0; $i < 4; $i++) {
            $lift->move();
        }

        $this->assertSame(5, $lift->getActualFloor());
        $this->assertSame(LiftState::STOP, $lift->getState());
    }
}
```

**tests/Integration/Service/SimulationEngineTest.php:**
```php
<?php

namespace App\Tests\Integration\Service;

use App\Domain\Service\SimulationEngine;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;

class SimulationEngineTest extends KernelTestCase
{
    private SimulationEngine $engine;

    protected function setUp(): void
    {
        self::bootKernel();
        $this->engine = static::getContainer()->get(SimulationEngine::class);
    }

    public function testSimulationRunsToCompletion(): void
    {
        $simulation = $this->createTestSimulation();

        $result = $this->engine->run($simulation);

        $this->assertTrue($result->isFinished());
        $this->assertGreaterThan(0, $result->getTotalTime());
        $this->assertNotNull($result->getStatistics());
    }
}
```

### 8.2 Frontend tests (Jest)

**assets/js/controllers/__tests__/simulation_controller.test.js:**
```javascript
import { Application } from "@hotwired/stimulus"
import SimulationController from "../simulation_controller"

describe("SimulationController", () => {
  let application
  let controller

  beforeEach(() => {
    application = Application.start()
    application.register("simulation", SimulationController)

    document.body.innerHTML = `
      <div data-controller="simulation"
           data-simulation-url-value="/api/simulations"
           data-simulation-simulation-id-value="123">
        <span data-simulation-target="status">Idle</span>
        <span data-simulation-target="timestamp">0</span>
      </div>
    `

    controller = application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="simulation"]'),
      "simulation"
    )
  })

  afterEach(() => {
    application.stop()
  })

  test("connects successfully", () => {
    expect(controller).toBeDefined()
    expect(controller.statusTarget.textContent).toBe("Idle")
  })

  test("starts simulation", async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({
        json: () => Promise.resolve({ status: "running" }),
      })
    )

    await controller.start()

    expect(fetch).toHaveBeenCalledWith(
      "/api/simulations",
      expect.objectContaining({ method: "POST" })
    )
    expect(controller.statusTarget.classList.contains("status--running")).toBe(true)
  })
})
```

### 8.3 E2E tests (Playwright)

**tests/e2e/simulation.spec.ts:**
```typescript
import { test, expect } from '@playwright/test'

test.describe('Simulation workflow', () => {
  test('user can create and run simulation', async ({ page }) => {
    await page.goto('/')

    // Configure simulation
    await page.click('text=New Simulation')
    await page.fill('[name="name"]', 'Test Building')
    await page.fill('[name="numberOfFloors"]', '10')
    await page.selectOption('[name="algorithm"]', 'dijkstra')

    // Add lift
    await page.click('text=Add Lift')
    await page.fill('[name="lifts[0][baseFloor]"]', '1')
    await page.fill('[name="lifts[0][finalFloor]"]', '10')
    await page.fill('[name="lifts[0][capacity]"]', '8')

    // Upload humans list
    await page.setInputFiles('[name="humansFile"]', 'test_cases/VL_1.txt')

    // Create
    await page.click('button[type="submit"]')

    // Wait for redirect
    await expect(page).toHaveURL(/\/simulation\/[a-f0-9-]+/)

    // Start simulation
    await page.click('text=Start')

    // Check running status
    await expect(page.locator('.status')).toContainText('Running')

    // Wait for completion
    await page.waitForSelector('.status:has-text("Finished")', { timeout: 60000 })

    // Check report
    await expect(page.locator('text=Average Waiting Time')).toBeVisible()
  })
})
```

---

## 9. Dokumentace

### 9.1 README.md

```markdown
# UpEtDown - Elevator System Simulator

Modern web-based elevator system simulator built with PHP 8.4 and Vanilla JavaScript.

## Features

- Discrete simulation of elevator systems
- Multiple scheduling algorithms (Random, Dijkstra)
- Real-time visualization
- Statistical analysis and reports
- Configuration import/export

## Requirements

- PHP 8.4+
- PostgreSQL 16+ / SQLite
- Redis 7+
- Node.js 20+ (for asset building)
- Docker & Docker Compose (recommended)

## Quick Start

\`\`\`bash
# Clone repository
git clone https://github.com/yourusername/upetdown-php.git
cd upetdown-php

# Start with Docker
docker-compose up -d

# Install dependencies
docker-compose exec php composer install
docker-compose exec php npm install

# Run migrations
docker-compose exec php php bin/console doctrine:migrations:migrate

# Open in browser
open http://localhost
\`\`\`

## Documentation

- [User Guide](docs/user-guide.md)
- [API Documentation](docs/api.md)
- [Developer Guide](docs/developer-guide.md)
- [Architecture](docs/architecture.md)

## Testing

\`\`\`bash
# Backend tests
composer test

# Frontend tests
npm test

# E2E tests
npm run test:e2e
\`\`\`

## License

MIT
```

### 9.2 API dokumentace (OpenAPI)

**docs/openapi.yaml:**
```yaml
openapi: 3.0.0
info:
  title: UpEtDown API
  version: 1.0.0
  description: Elevator Simulation System API

servers:
  - url: http://localhost
    description: Development server

paths:
  /api/simulations:
    post:
      summary: Create new simulation
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateSimulationRequest'
      responses:
        '201':
          description: Simulation created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Simulation'

  /api/simulations/{id}/start:
    post:
      summary: Start simulation
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Simulation started

  /api/simulations/{id}/status:
    get:
      summary: Get simulation status
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Current status
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/SimulationStatus'

components:
  schemas:
    CreateSimulationRequest:
      type: object
      required:
        - name
        - numberOfFloors
        - algorithm
        - lifts
      properties:
        name:
          type: string
        numberOfFloors:
          type: integer
          minimum: 2
          maximum: 100
        algorithm:
          type: string
          enum: [random, dijkstra]
        lifts:
          type: array
          items:
            $ref: '#/components/schemas/LiftConfiguration'

    LiftConfiguration:
      type: object
      required:
        - baseFloor
        - finalFloor
        - capacity
        - speed
      properties:
        baseFloor:
          type: integer
        finalFloor:
          type: integer
        deniedFloors:
          type: array
          items:
            type: integer
        capacity:
          type: integer
        speed:
          type: number
          format: float

    Simulation:
      type: object
      properties:
        id:
          type: string
          format: uuid
        name:
          type: string
        status:
          type: string
          enum: [configured, running, paused, finished]
        createdAt:
          type: string
          format: date-time

    SimulationStatus:
      type: object
      properties:
        timestamp:
          type: integer
        progress:
          type: number
          format: float
        humansLeft:
          type: integer
        lifts:
          type: array
          items:
            $ref: '#/components/schemas/LiftStatus'

    LiftStatus:
      type: object
      properties:
        id:
          type: integer
        actualFloor:
          type: integer
        state:
          type: string
        direction:
          type: string
        occupancy:
          type: integer
```

---

## 10. Srovnání před/po

### 10.1 Klíčová vylepšení

| Aspekt | MATLAB (před) | PHP 8.4 (po) |
|--------|---------------|--------------|
| **Platformní závislost** | Vyžaduje MATLAB licenci | Open-source, běží všude |
| **GUI** | Desktop MATLAB GUI | Moderní web UI, responzivní |
| **Přístupnost** | Lokální instalace | Web browser, multi-user |
| **Real-time update** | MATLAB events | WebSocket, sub-second latency |
| **Škálovatelnost** | Single machine | Horizontálně škálovatelné |
| **Deployment** | Manual | Docker, CI/CD automatizace |
| **Persistence** | .mat files | PostgreSQL, profesionální DB |
| **Vizualizace** | MATLAB plots | Canvas/SVG, interaktivní |
| **API** | N/A | REST API, dokumentované |
| **Testing** | Manual | Automated (PHPUnit, Jest, E2E) |
| **Maintenance** | Proprietární | Modern PHP ekosystém |

### 10.2 Zachované funkce

✅ Diskrétní simulace
✅ Random a Dijkstra algoritmy
✅ Event-driven architektura
✅ Statistické výpočty
✅ Vizualizace pohybu výtahů
✅ Generování reportů
✅ Import konfigurace

### 10.3 Nové funkce

🆕 Multi-user podpora
🆕 Real-time kolaborace
🆕 Historie simulací
🆕 REST API pro integraci
🆕 Export do různých formátů
🆕 Dark mode
🆕 Responsive design
🆕 WebSocket streaming
🆕 Docker deployment
🆕 Automatizované testování

---

## 11. Časový odhad a náklady

### 11.1 Časová osa

| Fáze | Trvání | Popis |
|------|--------|-------|
| Fáze 1 | 2 týdny | Příprava, setup, analýza |
| Fáze 2 | 4 týdny | Backend core development |
| Fáze 3 | 3 týdny | Frontend development |
| Fáze 4 | 2 týdny | Integrace, reporty |
| Fáze 5 | 1 týden | Optimalizace, deploy |
| **Celkem** | **12 týdnů** | **3 měsíce** |

### 11.2 Tým

**Minimální tým (1 full-stack developer):**
- Senior PHP/JS developer: 12 týdnů

**Optimální tým:**
- 1x Senior Backend Developer (PHP): 8 týdnů
- 1x Frontend Developer (JS/CSS): 6 týdnů
- 1x DevOps Engineer: 2 týdny

### 11.3 Infrastruktura

**Development:**
- Docker Desktop (zdarma)
- GitHub (zdarma pro open-source)

**Production (měsíční náklady):**
- DigitalOcean Droplet (4GB RAM): $24/měsíc
- Managed PostgreSQL: $15/měsíc
- Redis: $10/měsíc
- **Celkem: ~$50/měsíc**

---

## 12. Rizika a mitigace

| Riziko | Pravděpodobnost | Dopad | Mitigace |
|--------|-----------------|-------|----------|
| Komplexita MATLAB → PHP konverze | Střední | Vysoký | Postupná migrace, testování proti MATLAB výstupům |
| Performance simulace | Nízká | Střední | Profiling, optimalizace, Redis cache |
| WebSocket stabilita | Nízká | Střední | Fallback na polling, monitoring |
| Scope creep | Vysoká | Střední | Striktní MVP definice, iterativní vývoj |
| Browser kompatibilita | Nízká | Nízká | Použití standardních API, polyfills |

---

## 13. Další kroky

### 13.1 Priorita 1 (MVP)

1. Setup projektu a Docker environment
2. Implementace core domain modelů (Building, Lift, Human)
3. Základní simulační engine s Random algoritmem
4. Jednoduchá vizualizace (Canvas)
5. Basic report generation

### 13.2 Priorita 2

6. Dijkstra algoritmus
7. WebSocket real-time updates
8. Kompletní UI/UX
9. Statistiky a grafy
10. Import/export

### 13.3 Priorita 3

11. Advanced features (pause/resume, replay)
12. Multi-user support
13. API pro třetí strany
14. Performance optimalizace
15. Production deployment

---

## Závěr

Migrace UpEtDown z MATLAB do PHP 8.4 představuje významný upgrade v oblasti:

- **Přístupnosti:** Z desktop aplikace na web
- **Škálovatelnosti:** Single-user → multi-user
- **Modernosti:** Starý tech stack → moderní ekosystém
- **Nákladů:** Proprietární licence → open-source

Využitím PHP 8.4 features (readonly, enums, property promotion), Symfony komponent a moderního lightweight frontendu (Vanilla JS/Stimulus) vytvoříme profesionální, maintainable a performantní aplikaci.

**Projekt je technicky realizovatelný v rámci 3 měsíců s minimálními náklady.**

---

**Připravil:** Claude
**Datum:** 2025-11-05
**Verze:** 1.0
