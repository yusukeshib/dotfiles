roaming () {
	rule="$1"
	rule=${rule:-"$USER-allow-ssh"}
	ipv4_address=$(curl -4 ifconfig.me 2>/dev/null)
	gcloud compute firewall-rules update $rule --source-ranges $ipv4_address/32
}

update-mydev-image () {
	local cid ids
	ids=$(docker ps -q 2>&1) || {
		echo "docker ps failed: $ids" >&2
		return 1
	}
	if [[ -z "$ids" ]]; then
		echo "No running containers found" >&2
		return 1
	fi
	cid=$(echo "$ids" | xargs docker inspect --format '{{.ID}} {{index .Config.Entrypoint 0}}' | awk '/bash$/{print $1; exit}')
	if [[ -z "$cid" ]]; then
		echo "No running container with entrypoint=bash found" >&2
		return 1
	fi
	docker commit "$cid" mydev:latest
}
