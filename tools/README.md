# Herramientas de validación

Los tres scripts analizan el **AST real** de GDScript (con `gdtoolkit`) y detectan errores
que `gdparse` no ve, porque son errores de *compilación* (ámbitos), no de sintaxis.

## Instalación

```bash
python3 -m venv .venv-gdt
.venv-gdt/bin/pip install "gdtoolkit==4.*"
```

## Uso (desde la raíz del proyecto)

```bash
.venv-gdt/bin/python tools/check_godot44.py      # analizador completo contra extension_api.json de Godot 4.4
.venv-gdt/bin/python tools/check_scope.py        # identificadores usados fuera de su ámbito
.venv-gdt/bin/python tools/check_members.py      # miembros/métodos que no existen en el tipo
.venv-gdt/bin/python tools/check_weak_types.py   # métodos de proyecto sobre vars tipadas Node
.venv-gdt/bin/python tools/check_inference.py    # "var x := ..." que infieren Variant
.venv-gdt/bin/python tools/check_scope_strict.py # igual que check_scope pero más agresivo
```

Todos deben terminar en `TOTAL 0`. Si aparece algo:

| Archivo | Qué significa |
|---|---|
| `check_scope.py` | Un nombre (`profile`, `player`, …) se usa en una función donde no existe: ni variable local, ni parámetro, ni miembro de la clase, ni autoload, ni global de Godot. **Es el error `Identifier "x" not declared in the current scope` que lanza Godot al compilar.** |
| `check_members.py` | Un acceso a miembro (`player.alivee`) no existe en el tipo declarado del receptor. |
| `check_weak_types.py` | Llama a un método del proyecto sobre una variable declarada `Node`/`Control` (`game.explode(...)`): Godot no lo resuelve al compilar. Se arregla con `game.call("explode", ...)` o tipando la variable con la clase real. |
| `check_inference.py` | `var x := algo.get(...)` infiere `Variant` y Godot falla con "Cannot infer the type". Se arregla anotando el tipo. |
| `check_scope_strict.py` | Variante que además marca cualquier token suelto desconocido; ruidosa, para revisión manual. |

## Por qué existen

Godot compila los scripts en cadena: si `menu.gd` no compila, `app.gd` deja de cargar y el
juego entero falla con "Failed to load script ... Parse error". Estos chequeos atrapan ese
tipo de fallo antes de abrir el editor.
