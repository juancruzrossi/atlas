# Atlas

Atlas convierte un backlog en cambios verificados y un PR listo para revisar.
Funciona con Claude Code, OpenCode y Codex, y también en proyectos sin Git.

El agente implementa. Atlas selecciona una tarea, ejecuta las verificaciones,
registra el resultado y prepara la entrega. Los PRs quedan abiertos para revisión.

## Instalar

Requisitos: Node.js 18 o superior, Bash y un proveedor instalado y autenticado.
Para publicar PRs: Git, un remoto `origin` y GitHub CLI (`gh`) autenticado.

```bash
npm install -g @jxtools/atlas
cd mi-proyecto
atlas init
```

`atlas init` crea archivos locales sin sobrescribir tu backlog ni instalar skills
en tu directorio personal. La instalación npm mantiene las skills de los
proveedores disponibles, preservando personalizaciones como archivos `.new`.

## Primer uso

Define las verificaciones reales del proyecto en `.atlas/config.json`:

```json
{
  "provider": "codex",
  "iterations": 25,
  "timeout": 1200,
  "gateTimeout": 1200,
  "gates": ["npm test", "npm run build"]
}
```

Usa los comandos que correspondan a tu proyecto. Atlas exige al menos una
verificación explícita y la ejecuta por su cuenta después de cada implementación.
Los comandos de `gates` se ejecutan con `/bin/sh` desde la raíz del proyecto.

Planifica en una terminal interactiva o escribe tareas a mano:

```bash
atlas plan "Agregar autenticación"
# En proyectos Git, guarda la configuración y el backlog antes de empezar:
git add .atlas/
git commit -m "chore: configure Atlas tasks"
git push
atlas 5
```

En proyectos sin Git, omite los comandos Git. Claude Code sigue siendo el proveedor
predeterminado. Puedes cambiarlo con `--cli claudecode|opencode|codex`.

## Backlog

`.atlas/backlog.md` sigue siendo la fuente de verdad de las tareas:

```markdown
## TODO

### AUTH-001: Crear inicio de sesión
- **Spec:** .atlas/specs/auth.md
- **Description:** Autenticar usuarios existentes.
- **Acceptance:** Credenciales válidas abren una sesión; las inválidas se rechazan.

## IN_PROGRESS

## DONE

## DELAYED
```

Cada sección debe aparecer una vez y los IDs deben ser únicos. `Spec` es opcional;
cuando se usa, debe existir dentro del proyecto. Se ignoran ejemplos dentro de
bloques de código y comentarios HTML. Se admite el encabezado antiguo `IN PROGRESS`.

Atlas retoma primero la tarea en curso. Si no hay ninguna, toma la primera de TODO.
No mueve tareas a DONE por una frase del agente: exige un resultado JSON válido,
un proceso que termine correctamente y todas las verificaciones aprobadas.
La calidad de esa evidencia depende de las verificaciones que configures.

## Comandos

| Comando | Resultado |
| --- | --- |
| `atlas init` | Crea configuración y estado; conserva archivos existentes |
| `atlas plan "..."` | Entrevista interactiva, especificación y tareas |
| `atlas [run] [N]` | Implementa y verifica hasta N tareas |
| `atlas resume [N]` | Retoma una sesión local o Git interrumpida |
| `atlas status [--json]` | Muestra tareas, sesión y bloqueo |
| `atlas logs [--tail N]` | Resume ejecuciones recientes |
| `atlas logs --failed` | Filtra errores registrados por el programa |
| `atlas logs --search "texto"` | Busca texto literal en los logs |
| `atlas review [--dry-run]` | Diagnóstico de solo lectura, sin invocar un modelo |
| `atlas doctor [--json]` | Comprueba configuración, proveedor y recuperación |
| `atlas clean [--all]` | Limpia logs de sesiones terminadas; conserva la sesión |
| `atlas update` | Muestra el comando de actualización npm |

`status`, `logs`, `doctor` y `review` permiten `--json` para automatización.
`clean --all` también vacía el historial de actividad y errores. Ninguna limpieza
elimina un backlog ni los datos necesarios para recuperar una sesión pendiente.

## Ejecución y entrega

1. Valida configuración y backlog, y bloquea ejecuciones simultáneas en el proyecto.
2. En Git, exige un árbol limpio y crea una rama `integration/atlas-...` desde la
   rama base. Si hay `origin`, comprueba que la base local y remota coincidan.
3. Marca una tarea IN_PROGRESS y le entrega al agente el trabajo y su especificación.
4. Guarda la salida en vivo, respeta el timeout y comprueba el resultado JSON.
5. Ejecuta cada verificación configurada. Si todas pasan, registra DONE y progreso.
6. En Git, crea un commit por tarea. Al terminar o alcanzar el límite, publica los
   commits verificados en un único PR. Nunca fusiona PRs automáticamente.

La rama base se toma de `ATLAS_DEFAULT_BRANCH`, `defaultBranch` en configuración,
`origin/HEAD` o la rama actual, en ese orden. Los repositorios Git sin `origin`
reciben commits locales sin publicación. Se reconocen los worktrees de Git.
Ejecuta Atlas desde la raíz del repositorio.

El programa deja la rama de trabajo activa al terminar o fallar. No hace reset,
stash, borrado de ramas ni cambio automático a la rama principal. Revisa el PR,\fusiónalo mediante tu flujo habitual y vuelve a sincronizar tu rama base antes
de iniciar otra sesión.

## Fallos y recuperación

```bash
atlas status
atlas logs --failed
atlas resume 5
```

Un error detiene la ejecución, conserva los cambios y deja la tarea en curso.
No hay reintentos automáticos que puedan duplicar acciones del agente. Después
de corregir el problema, `resume` obtiene un resultado nuevo y vuelve a verificar.
Si solo falló la publicación, retoma la entrega sin ejecutar otra vez las tareas
ya completadas. Un registro de commit permite recuperar interrupciones alrededor
de `git commit` sin duplicarlo.

Ctrl+C y SIGTERM detienen al proveedor y sus procesos hijos. El timeout devuelve
un error y también termina ese grupo de procesos. Los proveedores no deben lanzar
servicios independientes. Un SIGKILL o apagado abrupto puede dejar el bloqueo:
`atlas doctor` muestra el PID y host. Confirma que el dueño haya terminado antes
de eliminar `.atlas/runtime.lock`.

| Código de salida | Significado |
| --- | --- |
| `0` | No quedan tareas ejecutables; DELAYED se informa por separado |
| `1` | Configuración, estado, resultado o entrega inválidos |
| `2` | Se alcanzó el límite y quedan tareas pendientes |
| `124` | Timeout |
| `130` | Interrupción |
| Otro código no cero | Error devuelto por el proveedor o una verificación |

Los códigos de error del proveedor y las verificaciones se conservan. `status` y
los metadatos de `logs` distinguen un fallo de una pausa por límite.

## Archivos

```text
.atlas/
  config.json       Proveedor, límites y verificaciones
  backlog.md        Tareas editables
  guardrails.md     Reglas aprendidas
  progress.txt      Resultados de tareas verificadas
  specs/            Especificaciones
  session.json      Recuperación local de la sesión y publicación
  runtime.lock      Dueño de la ejecución activa
  activity.log      Eventos JSON por línea
  errors.log        Resumen de fallos
  runs/             Salida, resultados y metadatos por ejecución
```

El backlog, configuración, reglas, progreso y specs se versionan. Los archivos de
sesión, bloqueo y ejecución se excluyen mediante `.atlas/.gitignore`.

Los flags tienen prioridad sobre variables de entorno, y estas sobre el archivo:
`ATLAS_CLI`, `ATLAS_MAX_ITERATIONS`, `ATLAS_TIMEOUT` y `ATLAS_DEFAULT_BRANCH`.
Las notificaciones Telegram requieren `ATLAS_NOTIFY_TELEGRAM=true`,
`ATLAS_TELEGRAM_BOT` y `ATLAS_TELEGRAM_CHAT`. Se envían al finalizar la sesión.

La ejecución autónoma de los proveedores usa permisos amplios, como en Atlas 3.
Ejecuta Atlas en proyectos y entornos que consideres confiables. El bloqueo y las
comprobaciones de estado evitan errores de coordinación; no aíslan a un agente
malicioso. El modo de planificación conserva los permisos interactivos del proveedor.

## Migrar desde Atlas 3

Atlas 4 cambia el control de tareas y Git; no convierte sesiones activas en silencio.

1. Termina o archiva el trabajo de tu sesión 3.x y su PR de integración.
2. Conserva fuera de `.atlas/` una copia de `integration-session.json` si necesitas
   el historial y retira ese archivo del estado activo.
3. Ejecuta `atlas init` para agregar configuración y exclusiones de archivos runtime.
   Tu backlog, reglas y progreso se conservan.
4. Configura `gates`, revisa los IDs y secciones del backlog y guarda los cambios en Git.
5. Ejecuta `atlas doctor`, luego `atlas`.

Cambios deliberados: ya no hay PRs por tarea ni merges automáticos a integración;
`review` diagnostica sin reparaciones de un modelo; no se reinician tareas por edad;
las notificaciones son opt-in; alcanzar el límite con tareas pendientes devuelve 2.
`ATLAS_STALE_SECONDS` y `ATLAS_SLEEP_BETWEEN` ya no se usan. Las verificaciones no se
extraen de prosa en CLAUDE.md: se configuran explícitamente, y el agente sigue leyendo
AGENTS.md y CLAUDE.md para las reglas del proyecto.

## Desarrollo

El runtime usa módulos CommonJS y la biblioteca estándar de Node, sin dependencias
de producción ni compilación. `atlas.sh` conserva el punto de entrada npm y resuelve
symlinks. Los módulos de `lib/` separan CLI, configuración, backlog, procesos,
proveedores, Git y ejecución.

```bash
npm ci --ignore-scripts
npm test
npm run check
npm pack --dry-run
```

Las pruebas usan proveedores simulados y repositorios locales temporales. Cubren
la ejecución del CLI, errores, timeout, señales, recuperación y entrega de PRs.
No usan credenciales, mensajes reales ni proveedores pagos.

Licencia ISC.
