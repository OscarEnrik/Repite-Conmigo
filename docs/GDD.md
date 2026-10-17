# Diseño — Repite Conmigo

> Documento corto a propósito: si algo no entra acá, probablemente no entra en el prototipo.

## Pitch (una frase)

Loretta quiere levantarle el ánimo a Richard mientras el día se le desarma encima; el
jugador elige qué decir, y cada palabra mueve una barra que a fin de semana decide si la
acompañó de verdad o si solo miró.

## Datos básicos

| | |
|---|---|
| Género | Narrativo / decisiones con estado (dialog-driven) |
| Plataforma | PC (Windows) · objetivo secundario: web |
| Sesión objetivo | 5–10 minutos (una semana completa) |
| Público | Jugadores de jams narrativas |
| Tema de la jam | Mujer Game Jam 2026 |
| Motor | Godot 4.8-dev6 · GL Compatibility · lienzo 1920×1080 |
| Estado | Prototipo jugable de principio a fin |

## Loop principal

1. Arranca el día: Richard **deambula solo** por el escenario y hay que **clickearlo** para que
   aparezca la **tarjeta de contexto** con la desgracia del día.
2. **2 turnos de diálogo**. En cada uno, Richard dice su parte (el `prompt`) y Loretta elige
   **1 de 3 frases**: un chiste que lo choca, una frase que lo motiva o un ruido.
3. Cada frase mueve la **barra de ánimo**; al cerrar el día se compara con el umbral del día
   → "Día superado" o "Se acumula la tristeza".
4. Al terminar el jueves, el **promedio** de los 4 cierres decide uno de los **3 finales**.

La dificultad no son reflejos ni enemigos: es **sostener el ánimo de alguien** cuando lo
que le pasa empeora.

## Capas de mecánicas

- **Core Loop:** 4 días (lunes a jueves). Cada día empieza con un evento de contexto (una
  desgracia distinta) que se revela clickeando a Richard, y le siguen **2 turnos** de diálogo.
- **Sistema de diálogo:** en cada turno Loretta tiene **3 salidas** — *golpes* (`choke`,
  bajan el ánimo), *frases motivadoras* (`motivate`, lo suben) o *sonidos/gestos* (`sound`,
  impacto pequeño, para bien o para mal). 4 × 2 × 3 = **24 salidas**.
- **Barra de ánimo:** va de **0 a 100**. Cada día arranca en `start_mood` (50 hoy) y el delta
  de cada frase se **escala por el día jugado**: más avanzada la semana, lo hiriente pega
  más fuerte y lo bueno rinde menos.
- **Finales:** 3, evaluados al cerrar el jueves sobre el **promedio** de los cierres diarios.

## Números

Viven todos en `Game` (`scripts/autoload/game_manager.gd`), no en las escenas:

| Constante | Valor | Qué hace |
|---|---|---|
| `DAY_COUNT` | 4 | Días de la semana |
| `TURNS_PER_DAY` | 2 | Turnos por día |
| `MOOD_MIN` / `MOOD_MAX` | 0 / 100 | Rango del ánimo |
| `MOOD_START` | 50 | Ánimo por defecto |
| `ENDING_BRIGHT_MIN` | 70 | Corte del final luminoso |
| `ENDING_NEUTRAL_MIN` | 40 | Corte del final agridulce |
| `PENALTY_GROWTH` | 0.12 | Cuánto crece el daño por día jugado |
| `REWARD_DECAY` | 0.06 | Cuánto se desgasta lo bueno por día jugado |

Escala de una frase: `delta < 0` → `roundi(delta * (1 + 0.12 * día))`; `delta > 0` →
`roundi(delta * (1 - 0.06 * día))`. Con eso **las mismas buenas elecciones** rinden cada vez
menos: en una partida de prueba el ánimo cerró en 69 el lunes y en 64 el jueves.

Umbrales por día (`pass_threshold` en `days.json`): 50, 52, 54, 56.

## Cómo se decide el final

Sobre `average_mood()` (el promedio de los cierres diarios):

| Promedio | `ending_id` | Título en pantalla |
|---|---|---|
| ≥ 70 | `ending_bright` | "Una semana distinta" |
| 40 – 69 | `ending_bittersweet` | "Se sostuvo, a duras penas" |
| < 40 | `ending_gloomy` | "La tristeza se acumuló" |

La pantalla de final además muestra **días superados** (`X/4`) y el **ánimo promedio**, y
ofrece "Jugar de nuevo" y "Volver al menú".

## Dónde vive cada cosa

| Pieza | Rol |
|---|---|
| `assets/data/days.json` | Todo el texto de la semana (única fuente de verdad; los 4 días de Lunes a Jueves) |
| `Game` | Ánimo, día, turno, umbrales, escala, finales y guardado |
| `DialogueBox` | Pinta el turno y las 3 opciones; cierra el día |
| `DayScene` (`day_scene.gd`) | El escenario del día y su tarjeta de contexto |
| `DayStage` (`day_stage.gd`) | Richard deambulando y el clic que revela la tarjeta |
| `HUD` | Día actual + barra de ánimo |
| `Ending` | Muestra el resultado de la semana (días superados: X/4) |

## Controles

Ver la tabla del `README.md`. Resumen: clic o `ui_accept` para elegir, `pause` (Esc/P) para
pausar.

## Alcance

### MVP — lo que TIENE que estar (hecho)

- [x] Semana completa de 4 días jugable de principio a fin
- [x] Sistema de diálogo con 3 salidas por turno y barra de ánimo
- [x] Dificultad creciente a lo largo de la semana
- [x] 3 finales según el promedio
- [x] Menú principal con Nueva partida / Continuar
- [x] Pausa, ajustes de volumen/pantalla y guardado en `user://`

### Stretch goals — solo si sobra tiempo

- [ ] Indicador de "cómo viene la semana" (racha, mejor día)
- [ ] Animación/expresión de Richard por tipo de frase
- [ ] Audio real: registrar SFX y música en `Audio`
- [ ] Localización (es/en)

### Fuera de alcance (decidido, no se negocia)

- [ ] Combate o plataformeo (el andamiaje viejo se borró)
- [ ] Guardado con múltiples slots
- [ ] Multijugador
- [ ] Arte definitivo (este prototipo prioriza mecánica, UI de elecciones y estado)

## Referencias

- *Reigns* — decisiones con estado; acá el "recurso" es el ánimo de una persona.
- *Sí, señor* / juegos de respuestas — el chiste como arma de doble filo.
