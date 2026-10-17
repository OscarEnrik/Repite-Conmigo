# TODO

## Listo (base del proyecto)

- [x] Estructura de carpetas con colocación escena + script
- [x] 6 autoloads: `Events`, `Settings`, `Save`, `Audio`, `SceneLoader`, `Game`
- [x] Escenas base: `boot`, `main`, `main_menu`, `hud`, `dialogue_box`, `pause_menu`,
      `settings_menu`, `ending`, `day_01` … `day_07`
- [x] Recursos de datos: `DialogueDB` (lee `assets/data/days.json`) y `GameData` (guardado)
- [x] Tema global en `resources/themes/main_theme.tres`
- [x] Mapa de entrada mínimo: `ui_accept` (built-in) y `pause`
- [x] Flujo menú → semana de 4 días → final, con fundido
- [x] Guardado y ajustes en `user://`
- [x] Documentación: `README.md`, `docs/GDD.md`, `docs/CREDITS.md`, `docs/IMPLEMENTATION_PLAN.md`

## Prototipo jugable (MVP)

- [x] Semana completa lunes → jueves de principio a fin
- [x] Sistema de diálogo: 2 turnos por día, 3 salidas por turno
- [x] Barra de ánimo 0..100 con dificultad creciente por día
- [x] 3 finales según el promedio de la semana
- [x] Menú principal con Nueva partida / Continuar
- [x] Pausa con Continuar / Reiniciar / Volver al menú

## Siguiente

- [ ] Audio: elegir e integrar SFX y música (`Audio.register_sfx` / `register_music`)
- [ ] Definir el estilo de arte y aplicarlo (los 4 ajustes de resolución/paleta)
- [ ] Animación o expresión de Richard por tipo de frase (`choke` / `motivate` / `sound`)
- [ ] Indicador de "cómo viene la semana" (racha, mejor día)
- [ ] Pantalla de título con arte real (hoy `boot.tscn` es un splash con label)
- [ ] Localización (es/en) si la jam lo pide

## Antes de entregar

- [ ] Probar el export (Windows y web si aplica)
- [ ] Revisar que no quede código muerto ni escenas huérfanas
- [ ] Completar `docs/CREDITS.md` con todos los assets de terceros
- [ ] Verificar la licencia de cada asset
- [ ] Subir la build y el código
- [ ] Página de la jam: capturas, descripción, controles

## Deuda técnica conocida

- [ ] No hay tests automatizados (`tests/` está vacío)
- [ ] `Audio` crea los buses `Music` y `SFX` en tiempo de ejecución; se pueden promover a
      un `default_bus_layout.tres` si hace falta
- [ ] `Game.restart_run()` reinicia la semana sin confirmación
- [ ] No hay arte: todo es UI con el tema por defecto
- [ ] Los 3 finales comparten plantilla; solo cambia el título (`TITLES` en `ending.gd`)
