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

# Allow SSH only from the current public IPv4 address. The address becomes a
# firewall rule, so fetch it over HTTPS only and accept nothing but a valid
# dotted-quad.
roaming () {
	local rule ipv4_address octet
	rule="${1:-$USER-allow-ssh}"
	ipv4_address=$(curl -4 -fsS --max-time 10 --proto '=https' --tlsv1.2 https://ifconfig.me/ip 2>/dev/null)
	if [[ ! $ipv4_address =~ '^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$' ]]; then
		echo "roaming: failed to determine public IPv4 address" >&2
		return 1
	fi
	for octet in "${match[@]}"; do
		if (( 10#$octet > 255 )); then
			echo "roaming: invalid IPv4 address: $ipv4_address" >&2
			return 1
		fi
	done
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
