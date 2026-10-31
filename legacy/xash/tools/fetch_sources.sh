#!/usr/bin/env bash
# Trae el codigo fuente de las dependencias (motor, cliente y game dll) a .src/.
# Todo queda en revisiones fijas: dos personas obtienen exactamente lo mismo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${PAPITA_SRC:-$ROOT/.src}"
PINS="$ROOT/engine/pins.lock"
SHALLOW="${PAPITA_SHALLOW:-1}"

log()  { printf '\033[1;36m[fetch]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fetch]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fetch]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null || die "hace falta git"

leer_pin() { # $1 = slug
	awk -v s="$1" '$1 == s { print $2, $3 }' "$PINS"
}

clonar_fijado() { # $1 = slug  $2 = destino
	local slug="$1" dir="$2" url sha
	read -r url sha <<<"$(leer_pin "$slug")"
	[ -n "${url:-}" ] || die "no hay pin para '$slug' en engine/pins.lock"

	if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ]; then
		log "$slug ya esta en ${sha:0:10}"
		return 0
	fi

	log "clonando $slug -> ${dir#"$ROOT"/}"
	rm -rf "$dir"
	mkdir -p "$dir"
	git init -q "$dir"
	git -C "$dir" remote add origin "$url"
	if [ "$SHALLOW" = "1" ]; then
		git -C "$dir" fetch -q --depth 1 origin "$sha" 2>/dev/null \
			|| git -C "$dir" fetch -q origin 2>/dev/null
	else
		git -C "$dir" fetch -q origin
	fi
	git -C "$dir" checkout -q "$sha" 2>/dev/null \
		|| die "$slug: no se pudo hacer checkout de $sha (¿commit privado o borrado?)"
	log "$slug listo en ${sha:0:10}"
}

clonar_submodulo() { # $1 = ruta destino relativa a .src  $2 = url
	local dir="$SRC/$1" url="$2"
	if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
		log "submodulo ${1} ya presente"
		return 0
	fi
	log "submodulo ${1}"
	rm -rf "$dir"
	git clone -q ${SHALLOW:+--depth 1} "$url" "$dir" \
		|| die "no se pudo clonar $url (¿sin red hacia ese host?)"
}

mkdir -p "$SRC"

while read -r slug url sha; do
	[ -n "${slug:-}" ] || continue
	[ "${slug:0:1}" = "#" ] && continue
	clonar_fijado "$slug" "$SRC/$slug"
done < <(grep -vE '^\s*(#|submodule|$)' "$PINS")

# Submodulos del motor que el build necesita. Se clonan a mano porque
# `git submodule update` arrastra bzip2 desde gitlab.com (inalcanzable en
# algunas redes); aqui usamos el espejo de GitHub declarado en pins.lock.
while read -r _ engine relpath url; do
	[ -n "${relpath:-}" ] || continue
	clonar_submodulo "$engine/$relpath" "$url"
done < <(grep -E '^submodule ' "$PINS")

# xash-extras trae los recursos libres que GoldSrc espera fuera del gamedir
# (fuentes .fnt, gfx/shell, gamecontrollerdb, cacert.pem).
EXTRAS="$SRC/xash3d-fwgs/3rdparty/extras/xash-extras"
if [ -d "$EXTRAS" ]; then
	log "extras en ${EXTRAS#"$ROOT"/}"
else
	warn "no se encontro xash-extras: el cliente no tendra fuentes ni menu"
fi

log "listo. Fuentes en ${SRC#"$ROOT"/}"
