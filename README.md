# Procedural Planet Generator

A procedural planet generator built with **Godot 4** and **Compute Shaders**.

Generates a full spherical world in three stages: **land / ocean**, **height**,
then **climate simulation** (temperature, pressure, wind, humidity, clouds,
precipitation, snow, rivers).

## Features

- **Sphere topology** — Goldberg polyhedron (icosahedron → geodesic subdivision → dual).
  No polar singularities, uniform cell distribution.
- **GPU-accelerated** — all physics (advection, diffusion, cloud, rain, rivers)
  runs in compute shaders via `RenderingDevice`.
- **Three-stage pipeline**
  1. **Land / Ocean** — noise-based continent mask with erosion.
  2. **Height** — layered terrain: continental rise + plateau + mountain belts + hills.
  3. **Climate** — solar radiation, pressure, wind, humidity, cloud, precipitation,
     snow, and river accumulation.
- **Full GPU map** — 2D equirectangular / Mollweide projections rendered on GPU,
  including temperature, precipitation, cloud, snow, soil water, and rivers.
- **Real-time parameters** — all tuning values live in three `Resource` files
  (`LandConfig`, `HeightConfig`, `ClimateConfig`) with `@export` sliders.

## Project Structure

```
scripts/
├── config/          Parameter Resources (single source of truth)
├── core/            GoldbergPolyhedron, PlanetData, DebugPanel
├── generation/      LandGenerator, HeightGenerator
├── climate/         ClimateSimulator, SolarModel
├── compute/
│   ├── gpu_climate.gd       GPU dispatch orchestrator
│   ├── map_baker_gpu.gd     GPU map baking
│   └── shaders/             GLSL shader sources (climate / water / river)
├── rendering/       GpuPlanetView, MapView, WindArrows, ...
└── ui/              ParameterPanel
```

## Requirements

- Godot **4.2** or later
- GPU with compute shader support (Vulkan / Metal)
- ~2 GB free RAM for `subdivision = 32`

## Getting Started

1. Clone the repository.
2. Open the project in Godot 4.
3. Run `main.tscn`.
4. Use the right-side panel:
   - **Step 1** — tune land / ocean ratio and shape.
   - **Step 2** — tune plateau and mountain parameters.
   - **Step 3** — watch the climate evolve; switch to **Map** view to inspect fields.

### Controls

| Action | Input |
|---|---|
| Toggle panel | `Tab` |
| Move panel | Drag the title |
| Orbit camera | Middle mouse drag |
| Zoom | Mouse wheel |
| Switch 3D / Map | Panel buttons |

## Configuration

All parameters live in `scripts/config/*.gd` as `@export` fields.
Change a default in **one place** — the generator, simulator, and UI all read from it.

## Shader Overview

| File | Purpose |
|---|---|
| `shaders_climate.gd` | Solar, pressure, wind, advection, diffusion, copy |
| `shaders_water.gd`   | Evaporation, orographic rainfall, cloud & precipitation |
| `shaders_river.gd`   | Flow direction, storage-based accumulation |

To modify cloud or rain behaviour, edit **`shaders_water.gd`** only.

## Known Limitations

- GP faces are ~78 km wide at `subdivision = 32` — rivers appear coarse.
- Climate is simplified (no Coriolis, no fronts, no monsoons).
- High-precision local terrain (chunks) is not yet implemented.
