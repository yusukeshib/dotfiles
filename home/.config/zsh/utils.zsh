# Update all cloned zsh plugins and clear cached init/completion files.
zsh-plugins-update () {
	local dir
	for dir in "$HOME/.zsh/plugins"/*(/N); do
		echo "Updating ${dir:t}…"
		git -C "$dir" pull --ff-only || echo "  -> failed (skipped)" >&2
	done
	# Drop generated caches and their byte-compiled .zwc siblings.
	rm -f "${ZSH_CACHE_DIR:-$HOME/.cache/zsh}"/*.zsh(N) \
	      "${ZSH_CACHE_DIR:-$HOME/.cache/zsh}"/*.zwc(N) \
	      "$HOME/.zsh/plugins"/*/*.zwc(N) \
	      "${ZDOTDIR:-$HOME}/.zcompdump"(N) "${ZDOTDIR:-$HOME}/.zcompdump.zwc"(N)
	echo "Done. Restart your shell to pick up changes."
}

roaming () {
	local rule ipv4_address
	rule="${1:-$USER-allow-ssh}"
	ipv4_address=$(curl -4 -fsS ifconfig.me 2>/dev/null)
	if [[ -z "$ipv4_address" ]]; then
		echo "roaming: failed to determine public IPv4 address" >&2
		return 1
	fi
	gcloud compute firewall-rules update "$rule" --source-ranges "$ipv4_address/32"
}

update-mydev-image () {
	local cid ids inspected
	ids=$(docker ps -q 2>&1) || {
		echo "docker ps failed: $ids" >&2
		return 1
	}
	if [[ -z "$ids" ]]; then
		echo "No running containers found" >&2
		return 1
	fi
	inspected=$(docker inspect --format '{{.ID}} {{if .Config.Entrypoint}}{{index .Config.Entrypoint 0}}{{end}}' ${(f)ids} 2>&1) || {
		echo "docker inspect failed: $inspected" >&2
		return 1
	}
	cid=$(print -r -- "$inspected" | awk '/bash$/{print $1; exit}')
	if [[ -z "$cid" ]]; then
		echo "No running container with entrypoint=bash found" >&2
		return 1
	fi
	docker commit "$cid" mydev:latest
}
