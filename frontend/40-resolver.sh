#!/bin/sh
# Inyecta el resolver DNS activo del contenedor (Docker embedded DNS o CoreDNS en k8s)
# en default.conf, para que el proxy_pass a "backend" se resuelva dinamicamente
# en vez de fallar si el host no existe al momento de arrancar nginx.
set -e

RESOLVER=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)

if [ -n "$RESOLVER" ]; then
  sed -i "s/RESOLVER_PLACEHOLDER/$RESOLVER/" /etc/nginx/conf.d/default.conf
fi
