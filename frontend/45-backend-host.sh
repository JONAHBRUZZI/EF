#!/bin/sh
# Sustituye el host del backend en default.conf. La directiva "resolver" de nginx
# no aplica el "search" de /etc/resolv.conf, asi que en Kubernetes hace falta el
# nombre completo del Service (backend.<namespace>.svc.cluster.local). En Docker
# Compose basta el nombre corto del servicio ("backend"), que es el default si no
# se define BACKEND_HOST.
set -e

BACKEND_HOST_VALUE="${BACKEND_HOST:-backend}"

sed -i "s/BACKEND_HOST_PLACEHOLDER/$BACKEND_HOST_VALUE/" /etc/nginx/conf.d/default.conf
