# Maze Pathing & Anti-Block Research

Research on TTW (Tropical Tower Wars), Wintermaul Wars, Element TD, Line Tower Wars, and Tower Wars competitive maze mechanics. Focused on pathing, anti-block rules, and implementation details for our game.

---

## 1. How Players Use Buildings to Create Mazes

### Core Concept
Players place towers/buildings on a grid to create winding paths that force enemy units to take longer routes from spawn to exit. The longer enemies spend in range of towers, the more damage they take.

### Maze Patterns (from TTW and others)

| Maze Type | Description | Efficiency |
|-----------|-------------|------------|
| **Diagonal** | Towers placed diagonally across the lane, forcing zig-zag paths | Very high — longest pathing time |
| **Spiral** | Towers spiral inward, forcing units to loop repeatedly | Very high — hard to build mid-game |
| **S-Maze / Serpentine** | Back-and-forth rows across the lane | Most common, easy to build |
| **Box Maze** | Half-box or full-box formations | Good for team play (2v2) |
| **Juggle Maze** | Special layout with sellable "plug" towers at entry/exit | Advanced — allows redirecting units back through the maze |

### Key Design Principles
- **Turns slow units down** — Units lose time pathfinding around corners, and bunch up at turns (creating splash damage value)
- **Diagonal paths > straight paths** — Creeps walk faster in straight lines; constant turns maximize travel time
- **Spatial compression matters** — A long path only helps if towers can shoot the whole time. Condense the maze so towers cover multiple path segments (Element TD "snail" = 4-pass spiral)
- **Build order matters** — In TTW, specific tower placement sequences are documented (numbered 01-35) because an incomplete maze mid-construction can leak

---

## 2. Anti-Block Rules (Preventing Complete Path Closure)

This is THE critical mechanic. Players must be able to maze but NEVER fully block the path.

### Approach A: Pre-Placement Path Check (RECOMMENDED)

Before a building is placed, run pathfinding (BFS/A*) on a virtual grid to verify a valid path still exists from spawn to exit.

**Algorithm:**
1. Player initiates tower placement at grid position (x, y)
2. Temporarily mark that cell as impassable in a virtual copy of the grid
3. Run BFS from spawn point to exit point on the virtual grid
4. If BFS finds a valid path → allow placement
5. If BFS returns no path → reject placement (show red highlight / "path blocked" message)
6. Reset virtual grid

**Implementation in Godot (from community discussion):**
- Use `Navigation2D.get_simple_path()` or `AStar2D` to check connectivity
- Check on hover (not on click) for responsive UX
- Maintain a boolean `is_current_coordinate_valid` flag
- Only allow placement if flag is true

**Performance note:** BFS on a grid is O(rows * cols) — fast enough to run every frame during placement preview.

### Approach B: Post-Placement Detection (WC3 Method)

Used in WC3 maps where pre-check was harder:
- Calculate pathing cost between spawn and exit after placement
- If cost equals max value (65536 in WC3), the path is blocked
- Instantly refund and remove the building
- Display warning message to player

### Approach C: Anti-Cheat NPCs (Teamline Tower Wars)

- Special invulnerable units patrol the map
- If they detect a complete block, they destroy the offending towers
- Crude but effective for older map editors

### Approach D: Creeps Attack Buildings When Blocked (WC3 Hardcoded)

- WC3 hardcoded behavior: when units can't path, they attack the nearest building
- Some maps deliberately used this as the anti-block (you block = your towers get destroyed)
- Less elegant but adds strategic risk to aggressive mazing

### Our Recommendation: Approach A (Pre-Placement Check)

**Why:** Clean UX, prevents frustration, deterministic. Use BFS on a virtual grid copy. Reject invalid placements before they happen.

---

## 3. What Happens When a Unit Gets Stuck

### Problem Scenarios
- Player builds around an existing unit, trapping it
- Multiple units spawn at same point and collision-block each other
- Dynamic maze changes during a wave isolate units

### Solutions from Existing Games

**Collision Size Zero (WC3 standard):**
- When a creep attacks a tower (meaning it's stuck), set its collision size to 0
- Order it to move to the next waypoint/exit
- With 0 collision, it walks through buildings to find a valid path
- Once back on a valid path, restore collision

**Timeout Teleport:**
- If a unit hasn't moved more than X distance in Y seconds, teleport it:
  - Option 1: Teleport to the nearest valid path tile
  - Option 2: Teleport to the next waypoint
  - Option 3: Teleport to the exit (counts as a leak)
- Common in modern TD games

**Stagger Spawns:**
- Don't spawn all units at once at one point
- Spread spawn points or stagger by 0.1-0.5 seconds
- Prevents initial collision jams

**Our Recommendation:**
1. Primary: BFS anti-block should prevent most stuck scenarios
2. Fallback: If unit hasn't progressed toward exit in 5 seconds, remove collision and re-issue move order
3. Emergency: If still stuck after 10 seconds, teleport to nearest valid path tile

---

## 4. Pathfinding Around Player-Placed Obstacles

### Flow Field / BFS (RECOMMENDED for our game)

**Why flow fields beat A* for maze TD:**
- A* computes one path for one unit. With 50+ units, that's 50 A* calls.
- Flow field (BFS from exit) computes ONE field that ALL units use.
- Result: a direction vector at every grid cell pointing toward the exit.
- When a tower is placed, recalculate the entire flow field once. All units instantly use the new paths.

**Implementation (from Red Blob Games):**

```
1. Start BFS at the EXIT tile (not spawn)
2. Expand outward, marking each cell with:
   - distance to exit
   - direction toward exit (negative gradient of distance)
3. Store as two grids:
   - distance_field[x][y] = integer distance
   - flow_field[x][y] = Vector2 direction
4. Units simply look up flow_field[their_tile] and move that direction
5. On tower placement/removal: recalculate entire field
```

**Performance:** BFS is O(N) where N = total grid cells. For a 50x50 grid = 2,500 cells. Trivial to recalculate every time a building is placed.

### Repathing Behavior (from TTW)
- Creeps repath immediately when a maze change is detected
- Pathing is independent per player region
- The system detects juggling attempts and reacts immediately to find shortest route
- Units will NOT attack towers unless they have first attempted to repath

---

## 5. Strategic Elements of Maze Building

### Forcing Longer Paths
- **Serpentine/S-maze:** Forces units to traverse the full width of the lane multiple times
- **Spiral inward:** Units walk to the center and back out
- **Diagonal zigzag:** Maximum path length with minimum towers

### Chokepoints
- Narrow 1-tile-wide paths at corners where units bunch up
- Place splash/AOE towers at these points
- Slow towers at chokepoints cause massive unit stacking

### Kill Zones
- The "loop" concept from Tower Wars: create a section where the path doubles back on itself so the same towers can hit units on both the forward and return pass
- Element TD "multi-pass" design: units pass the same tower cluster 3-4 times
- Place your strongest towers where they cover the most path segments

### Juggling (Advanced)
- Build a "plug" tower at maze exit
- Units repath through the longer alternate route
- When they approach the alternate exit, sell the plug and block the alternate
- Units reverse direction and walk back through the entire maze
- **TTW allows this** with dedicated juggle maze designs
- **Many games prevent this** via: no selling during waves, sell cooldowns, or "ghost" buildings that persist after selling

### Tower Synergy in Mazes
- Melee towers at corners (units must walk past them)
- Ranged towers along straight segments (maximum uptime)
- Slow towers at entry points to bunch units for splash damage later
- Poison/DOT towers along the longest segments

---

## 6. Walls / Cheap Blocking Buildings vs Expensive Towers

### The Two-Tier Building System

Almost every maze TD has this distinction:

| Type | Cost | Purpose | Attacks? |
|------|------|---------|----------|
| **Wall / Barricade** | Very cheap (1-5 gold) | Path shaping only | No |
| **Tower** | Moderate-expensive (10-100+ gold) | Damage dealing | Yes |

### How It Works in Specific Games

**Line Tower Wars:**
- Cheap "barricade" building for maze structure
- Can be upgraded into any basic tower later
- Lets players shape the maze early when gold is tight
- Key rule: barricades are cheap enough that maze shape is an early-game decision, not a late-game luxury

**Wintermaul Wars:**
- Cheap race towers (1-3 gold) used for maze walls
- Expensive towers placed at key positions for damage
- Strategy: "cheap race for 1v1 — no 10+ gold towers early, focus on maze shape"

**Element TD:**
- "Mazing rocks" are free/cheap blocking elements
- Towers are separate and placed for damage
- Rocks + tower combinations create the full defense

### Design Implications for Our Game
- **Must have a cheap wall/fence building** (1-2 gold) that blocks pathing but does no damage
- Towers should be significantly more expensive and provide the actual defense
- Allow upgrading walls into towers (wall becomes the foundation)
- This creates a skill curve: beginners just build towers; advanced players maze with walls then add towers at key positions

---

## 7. Leak Mechanics

### What "Leaking" Means
When an enemy unit reaches the exit point of your maze without being killed.

### Consequences in Different Games

**Lives System (most common):**
- Each team starts with N lives (typically 20)
- Each leaked unit = -1 life for defender
- Bosses may cost more lives when leaked
- At 0 lives, you lose

**Competitive Send/Leak (Tower Wars, TTW, Line Tower Wars):**
- Leaked units from YOUR lane damage the NEXT player
- Units you SEND to opponents that leak through THEIR defense = you GAIN a life, they LOSE a life
- This creates dual economy: income from sending + defense from building
- "Leaking is sometimes strategic" — accept some leaks to invest in income/sending

**Income Connection:**
- Sending units costs gold but permanently increases your income per tick
- More expensive sends = more income = but weaker defense
- Balance: over-sending = you leak and die; under-sending = opponent out-economies you

### TTW Specific
- Each team has a "ship" (castle equivalent) that must be protected
- Two defenders per team + one goalie (last line of defense)
- Creeps that pass defenders reach the goalie area
- Creeps that pass the goalie damage the ship

---

## 8. Comparison Across Games

| Feature | TTW | Wintermaul | Line Tower Wars | Element TD | Tower Wars (Steam) |
|---------|-----|------------|-----------------|------------|---------------------|
| Maze building | Yes | Yes | Yes | Yes | Yes |
| Anti-block | Repath + attack | BFS virtual copy | Anti-cheat NPC | Can't block waypoints | Pre-check |
| Juggling | Allowed (designed for) | Prevented (anti-juggle) | N/A | N/A | N/A |
| Cheap walls | Tower-based | Cheap race towers | Barricades | Mazing rocks | Tower-based |
| Leak mechanic | Ship damage | Lives | Lives + income | Lives | Lives exchange |
| Send to opponent | Yes | Sometimes | Yes | No | Yes |
| Pathing type | Per-region independent | BFS virtual grid | Waypoint-based | Waypoint-based | Lane-based |

---

## 9. Implementation Plan for Our Game

### Required Systems

1. **Grid System**
   - Tile-based grid for building placement
   - Each cell: empty, wall, tower, spawn, exit, or terrain
   - Buildings snap to grid

2. **Flow Field Pathfinding**
   - BFS from exit point
   - Generates distance_field and flow_field arrays
   - Recalculated on every building placement/removal
   - Units read flow_field[current_tile] for movement direction

3. **Anti-Block Validation**
   - On building placement preview: temporarily mark cell as blocked
   - Run BFS on virtual grid
   - If no path exists: reject placement (red highlight)
   - If path exists: allow placement (green highlight)
   - Must check for ALL spawn points, not just one

4. **Stuck Unit Recovery**
   - Timer per unit: if not progressing toward exit, trigger recovery
   - Step 1 (5s): Remove collision, re-issue move order
   - Step 2 (10s): Teleport to nearest valid path tile
   - Step 3 (15s): Teleport to exit (counts as leak)

5. **Wall Building**
   - Cheap wall structure (1-2 gold) — no attack, just blocks path
   - Upgrade path: wall → basic tower → advanced tower
   - Visual distinction: wall = fence/palisade, tower = actual structure

6. **Leak System**
   - Units that reach exit: remove from play
   - Defender loses 1 life per leaked unit
   - In competitive mode: attacker gains 1 life per leak
   - At 0 lives: castle destroyed, game over

### Pseudocode: Core Anti-Block + Flow Field

```
# On building placement attempt:
func try_place_building(grid_pos, building_type):
    # 1. Check if cell is empty
    if grid[grid_pos] != EMPTY:
        return false
    
    # 2. Temporarily block the cell
    grid[grid_pos] = BLOCKED
    
    # 3. Run BFS from exit
    path_exists = bfs_check_path(spawn_pos, exit_pos, grid)
    
    # 4. If path blocked, reject
    if not path_exists:
        grid[grid_pos] = EMPTY  # restore
        show_error("Cannot block the path!")
        return false
    
    # 5. Place building and recalculate flow field
    grid[grid_pos] = building_type
    recalculate_flow_field()
    return true

# BFS path check:
func bfs_check_path(start, end, grid):
    queue = [start]
    visited = {start}
    while queue not empty:
        current = queue.pop_front()
        if current == end:
            return true
        for neighbor in get_neighbors(current):
            if neighbor not in visited and grid[neighbor] != BLOCKED:
                visited.add(neighbor)
                queue.append(neighbor)
    return false

# Flow field generation:
func recalculate_flow_field():
    # BFS from EXIT (reverse direction)
    queue = [exit_pos]
    distance_field = {} # pos -> int
    distance_field[exit_pos] = 0
    
    while queue not empty:
        current = queue.pop_front()
        for neighbor in get_neighbors(current):
            if neighbor not in distance_field and grid[neighbor] != BLOCKED:
                distance_field[neighbor] = distance_field[current] + 1
                queue.append(neighbor)
    
    # Generate flow vectors (direction of steepest descent)
    for pos in distance_field:
        best_neighbor = null
        best_dist = INF
        for neighbor in get_neighbors(pos):
            if neighbor in distance_field and distance_field[neighbor] < best_dist:
                best_dist = distance_field[neighbor]
                best_neighbor = neighbor
        if best_neighbor:
            flow_field[pos] = (best_neighbor - pos).normalized()

# Unit movement:
func move_unit(unit, delta):
    grid_pos = world_to_grid(unit.position)
    if grid_pos in flow_field:
        direction = flow_field[grid_pos]
        unit.position += direction * unit.speed * delta
    else:
        # Unit is off-grid or stuck — trigger recovery
        trigger_stuck_recovery(unit)
```

---

## Sources

- [Tropical Tower Wars Official Forum](https://tropicaltowerwars.forumotion.com/)
- [TTW Maze Advice Thread](https://tropicaltowerwars.forumotion.com/t149-need-some-advice)
- [TTW Website (mazes)](https://tropicaltowerwars.com/mazes)
- [Red Blob Games: Flow Field Pathfinding for Tower Defense](https://www.redblobgames.com/pathfinding/tower-defense/)
- [Hive Workshop: How Do Maze TD Maps Work](https://www.hiveworkshop.com/threads/how-do-maze-tower-defense-maps-work.292075/)
- [TheHelper: Tower Defense Anti Block](https://www.thehelper.net/threads/tower-defense-anti-block.138531/)
- [Wintermaul Wars Guide](http://wmwl.weebly.com/wmw-guide.html)
- [Warcraft Maul Reimagined (BFS anti-block)](https://www.hiveworkshop.com/threads/warcraft-maul-reimagined-v4-3-2.318846/)
- [Godot Forum: TD Path Check Before Placement](https://forum.godotengine.org/t/td-checking-path-before-placing-building-to-avoid-blocking/17780)
- [Element TD Mazing Guide](https://forums.eletd.com/topic/2973-mazing-guide/)
- [TLTW Blog Post (Teamline Tower Wars)](https://postmasterinterest.blogspot.com/2013/06/warcraft-3-reminiscence-teamline-tower.html)
- [Hypixel Tower Wars Guide](https://hypixel.net/threads/guide-complete-guide-to-tower-wars.1932850/)
- [Line Tower Wars Guide (Blizzard Forums)](https://us.forums.blizzard.com/en/warcraft3/t/complete-line-tower-wars-guide/21972)
- [GameFAQs WC3 Tower Defense FAQ](https://gamefaqs.gamespot.com/pc/256222-warcraft-iii-reign-of-chaos/faqs/23533)
