#!/usr/bin/env bash
# Print a JSON array of {name, image} for each service in the compose file.
# build: services use balena's local tag <project>_<service>:<tag>; image: services keep their reference.
#
# Usage: compose-images.sh <project-name> <tag>
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 <project-name> <tag>" >&2
	exit 2
fi

docker compose config --format json |
	jq -c --arg project "$1" --arg tag "$2" '
		[.services | to_entries[]
		 | {name: .key,
		    image: (if .value.build then "\($project)_\(.key):\($tag)" else .value.image end)}]'
