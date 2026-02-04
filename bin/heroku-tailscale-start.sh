#!/usr/bin/env bash

set -e

function log() {
  echo "-----> $*"
}

function indent() {
  sed -e 's/^/       /'
}

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  log "Skipping Tailscale"

else
  log "Starting Tailscale"

  if [ -z "$TAILSCALE_HOSTNAME" ]; then
    if [ -z "$HEROKU_APP_NAME" ]; then
      tailscale_hostname=$(hostname)
    else
      # Only use the first 8 characters of the commit sha.
      # Swap the . and _ in the dyno with a - since tailscale doesn't
      # allow for periods.
      DYNO=${DYNO//./-}
      DYNO=${DYNO//_/-}
      tailscale_hostname=${HEROKU_SLUG_COMMIT:0:8}"-$DYNO-$HEROKU_APP_NAME"
    fi
  else
    tailscale_hostname="$TAILSCALE_HOSTNAME"
  fi
  log "Using Tailscale hostname=$tailscale_hostname"

  # Build proxy flags based on environment variables
  proxy_flags=""
  socks5_port="${TAILSCALE_SOCKS5_PORT:-1055}"
  http_proxy_port="${TAILSCALE_HTTP_PROXY_PORT:-}"

  if [ -n "$socks5_port" ]; then
    proxy_flags="$proxy_flags --socks5-server=localhost:$socks5_port"
  fi
  if [ -n "$http_proxy_port" ]; then
    proxy_flags="$proxy_flags --outbound-http-proxy-listen=localhost:$http_proxy_port"
  fi

  tailscaled -verbose ${TAILSCALED_VERBOSE:-0} --tun=userspace-networking $proxy_flags &
  until tailscale up \
    --authkey=${TAILSCALE_AUTH_KEY} \
    --hostname="$tailscale_hostname" \
    --accept-dns=${TAILSCALE_ACCEPT_DNS:-true} \
    --accept-routes=${TAILSCALE_ACCEPT_ROUTES:-true} \
    --advertise-exit-node=${TAILSCALE_ADVERTISE_EXIT_NODE:-false} \
    --shields-up=${TAILSCALE_SHIELDS_UP:-false}
  do
    log "Waiting for 5s for Tailscale to start"
    sleep 5
  done

  # Set proxy environment variables based on what's configured
  if [ -n "$http_proxy_port" ]; then
    export HTTP_PROXY=http://localhost:$http_proxy_port/
    export HTTPS_PROXY=http://localhost:$http_proxy_port/
  fi
  if [ -n "$socks5_port" ]; then
    export ALL_PROXY=socks5://localhost:$socks5_port/
  fi
  log "Tailscale started"
fi
