package fluid_simulation

import "core:fmt"
import "core:math"
import "core:math/rand"

import rl "vendor:raylib"


// Simulation {{{

Vector2 :: [2]f32

Particle :: struct {
  position: Vector2,
  velocity: Vector2,
  color: rl.Color,
}

vector2_len :: proc(v: Vector2) -> f32 {
  return math.sqrt(v.x * v.x + v.y * v.y)
}

vector2_normalize :: proc(v: Vector2) -> Vector2 {
  length := vector2_len(v)
  if length == 0 do return v
  return { v.x, v.y } / length
}

// NOTE: não acredito que essa função retorne a normal de um vetor
vector2_get_normal :: proc(v: Vector2) -> Vector2 {
  return { v.y, -v.x }
}

// }}}

get_screen_sizes :: proc() -> Vector2 {
  return { f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
}

PARTICLE_AMMOUNT :: 1000
VELOCITY_DAMPING :: 1
simulation : struct {
  particles: []Particle
} = {
  particles = make([]Particle, PARTICLE_AMMOUNT)
}

// TODO: refatorar cellmap e hashgrid

GridCell :: [dynamic]^Particle

delete_cell_map :: proc(c: map[u32]GridCell) {
  for slot, item in c {
    delete(item)
  }
  delete(c)
}

HashGrid :: struct {
  cell_size : u32,
  cell_map:  map[u32]GridCell,
  cell_map_size: u32,
  primes: [3]u64,
}

init_hash_grid :: proc(cell_size : u32) -> HashGrid {
  h := HashGrid {
    cell_size = cell_size,
    cell_map = make(map[u32]GridCell),
    cell_map_size = 100_000,
    primes = {
      6614058611,
      7528850467,
      0, // NOTE: já que a simulação não é 3d decidi não colocar o terceiro número primo
    }
  }
  return h
}

delete_hash_grid :: proc(hash_grid : HashGrid) {
  delete_cell_map(hash_grid.cell_map)
}

grid_pos_to_index :: proc(h: HashGrid, pos: Vector2) -> [2]i32 {
  return {
    i32(pos.x) / i32(h.cell_size),
    i32(pos.y) / i32(h.cell_size),
  }
}

grid_index_to_hash :: proc(using h: HashGrid, id: [2]i32) -> u32 {
  part_x := u64(id.x) * primes.x
  part_y := u64(id.y) * primes.y
  hash := u32(part_x ~ part_y  % u64(cell_map_size))
  return hash
}

grid_cell_hash_from_position :: proc(h: HashGrid, pos: Vector2) -> u32 {
  return grid_index_to_hash(h, grid_pos_to_index(h, pos))
}

grid_map_particle_to_cell :: proc(using h: ^HashGrid, particles: ^[]Particle) {
  for &p, i in particles {
    // if position.x < 0 || position.y < 0 do panic("boa pergunta")
    hash := grid_cell_hash_from_position(h^, p.position)
    if hash not_in cell_map do cell_map[hash] = make(GridCell)
    append(&cell_map[hash], &p)
  }
}

grid_get_content_of_hash :: proc(h: HashGrid, hash: u32) -> []^Particle {
  contents := h.cell_map[hash] or_else {}
  return contents[:]
}

grid_get_content_of_cell :: proc(h: HashGrid, id: [2]i32) -> []^Particle {
  return grid_get_content_of_hash(h, grid_index_to_hash(h, id))
}


simulate :: proc(dt: f32) {
  if dt == 0 do return

  GRID_SIZE :: 100 // px
  hash_grid := init_hash_grid(GRID_SIZE)
  defer delete_hash_grid(hash_grid)


  prev_positions : []Vector2 = make([]Vector2, len(simulation.particles))
  defer delete(prev_positions)

  grid_map_particle_to_cell(&hash_grid, &simulation.particles)

  for &p, i in simulation.particles {
    using p
    prev_positions[i] = position
    position += velocity * dt * VELOCITY_DAMPING
  }

  for &p in simulation.particles {
    if p.color != rl.BLUE do p.color = rl.BLUE
  }

  mouse_pos := rl.GetMousePosition()
  cell_pos := grid_pos_to_index(hash_grid, mouse_pos)
  for p in grid_get_content_of_cell(hash_grid, cell_pos) {
      p.color = rl.ORANGE
  }

  for &p, i in simulation.particles {
    using p


    cell_pos := grid_pos_to_index(hash_grid, position)

    // using hash grid {{{
    neighbours : GridCell = {}
    for x in -1..=1 {
      for y in -1..=1 {
        append_elems(&neighbours, ..grid_get_content_of_cell(hash_grid, cell_pos))
      }
    }
    // }}}


    // compute next velocity {{{
    velocity = (position - prev_positions[i]) / dt
    // }}}

    // world boundary {{{
    screen_sizes := get_screen_sizes()
    if position.x < 0 || position.x > screen_sizes.x {
      velocity.x *= -1
    }
    if position.y < 0 || position.y > screen_sizes.y {
      velocity.y *= -1
    }
    //}}}

  }
}

draw_simulation :: proc() {
  for p in simulation.particles {
    rl.DrawCircleV(p.position, 5, p.color)
  }
}

init_simulation :: proc() {
  // instantiate particles {{{

  offset_between_particles :: 10
  offset_all_particles :: Vector2 { 750, 100 }

  x_particles := math.sqrt_f32(PARTICLE_AMMOUNT)
  y_particles := x_particles

  for &p, i in simulation.particles {
    p.position = {f32(i % int(x_particles)), f32(i / int(x_particles))} * offset_between_particles + offset_all_particles
    p.velocity = { -0.5 + rand.float32(), -0.5 + rand.float32() } * 100
    p.color = rl.BLUE
  }

  // }}}
}

main :: proc() {
  rl.InitWindow(640 * 2, 360 * 2, "fluid simulation")
  defer rl.CloseWindow()

  init_simulation()


  // TODO: adicionar isso à struct simulation
  running := true
  simulating := true
  stepping := false

  rl.SetTargetFPS(60)
  for running && !rl.WindowShouldClose() {
    dt := rl.GetFrameTime()

    // input {{{
    if rl.IsKeyDown(.Q) do running = false
    if rl.IsKeyDown(.N) do simulating = true
    if rl.IsKeyDown(.P) do stepping = !stepping
    //}}}

    // update {{{
    if simulating {
      simulate(dt)
    }
    if stepping do simulating = false
    // }}}

    // render {{{
    rl.BeginDrawing()
      rl.ClearBackground(rl.DARKGRAY)
      draw_simulation()
    rl.EndDrawing()

    //}}}
  }
}
