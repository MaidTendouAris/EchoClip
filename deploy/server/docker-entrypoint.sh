#!/bin/sh
set -eu

config_file="${ECHOCLIP_CONFIG:-/etc/echoclip/server.toml}"

exec echoclip serve --config "$config_file"
