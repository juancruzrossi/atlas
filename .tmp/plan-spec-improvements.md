# Plan: Mejoras a Atlas basadas en "How to Write a Good Spec"

## Resumen

Implementar mejoras al sistema de especificaciones de Atlas siguiendo los principios del artículo de Addy Osmani sobre specs para agentes AI.

**Fuente:** https://addyosmani.com/blog/good-spec/

---

## Cambios Propuestos

### 1. Sistema de Boundaries (Always/Ask/Never)

**Archivos a modificar:**
- `templates/guardrails.md`
- `PLAN_PROMPT.md` (para que genere boundaries en specs)

**Cambio:**
Agregar sección de Boundaries al template de guardrails con 3 niveles:

```markdown
## Boundaries

### ✅ Always
- Run tests before commits
- Read files before editing
- Follow naming conventions from CLAUDE.md

### ⚠️ Ask First
- Database schema changes
- Adding new dependencies
- Changes to CI/CD configuration
- Modifying authentication/authorization logic

### 🚫 Never
- Commit secrets or API keys
- Edit node_modules/, vendor/, or generated files
- Force push to main/master
- Remove failing tests without explicit approval
- Skip quality gates
```

---

### 2. Sección Commands en Specs

**Archivos a modificar:**
- `PLAN_PROMPT.md` (template de spec)

**Cambio:**
Agregar sección `## Commands` obligatoria en specs generadas:

```markdown
## Commands

| Action | Command |
|--------|---------|
| Build | `npm run build` |
| Test | `npm test` |
| Lint | `npm run lint` |
| Type check | `npx tsc --noEmit` |
| Dev server | `npm run dev` |
```

---

### 3. Acceptance Criteria Ejecutables

**Archivos a modificar:**
- `PLAN_PROMPT.md` (sección Acceptance Criteria)

**Cambio:**
Transformar acceptance criteria de texto descriptivo a comandos verificables:

```markdown
## Acceptance Criteria

### Verificación manual
- [ ] AC-1: Usuario puede hacer login con credenciales válidas

### Verificación automática
```bash
# AC-1: API responde 200 en /health
curl -sf http://localhost:3000/health

# AC-2: Tests pasan con coverage > 80%
npm test -- --coverage --coverageThreshold='{"global":{"lines":80}}'

# AC-3: Build exitoso sin errores
npm run build
```
```

---

### 4. Self-Review Step en Prompt

**Archivos a modificar:**
- `prompt.md` (algoritmo principal)

**Cambio:**
Agregar paso de self-review entre implementación y quality gates:

```
3. Implement task completely

4. Self-review:
   - Re-read the spec (if exists)
   - Verify EACH requirement is addressed
   - Check boundaries from guardrails.md

5. Run quality gates (from CLAUDE.md or project's build/test)
```

---

### 5. Project Structure en Specs

**Archivos a modificar:**
- `PLAN_PROMPT.md` (template de spec)

**Cambio:**
Agregar sección opcional de estructura de proyecto:

```markdown
## Project Structure

```
src/
├── components/     # React components
├── services/       # API calls and business logic
├── hooks/          # Custom React hooks
└── utils/          # Helper functions

tests/
├── unit/           # Unit tests (*.test.ts)
└── e2e/            # End-to-end tests
```
```

---

### 6. Simplificar Task Format (Opcional)

**Archivos a modificar:**
- `PLAN_PROMPT.md` (task decomposition)
- `templates/backlog.md` (ejemplo)

**Cambio:**
Permitir formato compacto cuando spec tiene todo el detalle:

```markdown
### MED-005: Implement user CRUD endpoints
- **Spec:** .atlas/specs/spec-20260117.md#technical-design
- **Acceptance:** All CRUD operations return correct status codes
```

vs formato actual más verboso (mantener como opción para tasks sin spec).

---

## Archivos a Modificar

| Archivo | Tipo de cambio |
|---------|----------------|
| `templates/guardrails.md` | Agregar sección Boundaries |
| `PLAN_PROMPT.md` | Agregar Commands, Project Structure, AC ejecutables |
| `prompt.md` | Agregar paso self-review |
| `templates/backlog.md` | Actualizar ejemplo con formato compacto |

---

## Verificación

1. **Test manual de `atlas init`:**
   ```bash
   cd /tmp/test-project
   atlas init
   cat .atlas/guardrails.md  # Verificar boundaries
   ```

2. **Test manual de `atlas plan`:**
   ```bash
   atlas plan "Add user authentication"
   cat .atlas/specs/spec-*.md  # Verificar Commands, Project Structure, AC ejecutables
   ```

3. **Test de iteración:**
   ```bash
   # Crear task manual y correr
   atlas 1
   # Verificar que self-review aparece en logs
   ```

---

## Lo que NO se implementa (y por qué)

| Feature del artículo | Razón para no incluir |
|---------------------|----------------------|
| Multi-agent paralelo | Complejidad alta, Atlas prioriza simplicidad |
| RAG/Vector DB | Over-engineering para el scope actual |
| Spec summaries | Solo útil para specs muy largos, agregar si se necesita |
| Eliminar progress.txt | Bajo impacto, mantener por compatibilidad |

---

## Orden de Implementación

1. **Boundaries en guardrails.md** (impacto alto, esfuerzo bajo)
2. **Commands en PLAN_PROMPT.md** (impacto alto, esfuerzo bajo)
3. **Self-review en prompt.md** (impacto medio, esfuerzo bajo)
4. **AC ejecutables en PLAN_PROMPT.md** (impacto medio, esfuerzo medio)
5. **Project Structure en PLAN_PROMPT.md** (impacto bajo, esfuerzo bajo)
6. **Task format compacto** (impacto bajo, esfuerzo bajo)
