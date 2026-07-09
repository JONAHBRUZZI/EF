FROM nginx:alpine

# Limpia contenido por defecto
RUN rm -rf /usr/share/nginx/html/*

# Copia los archivos del frontend
COPY index.html app.js /usr/share/nginx/html/

# Copia la configuración custom de Nginx
COPY default.conf /etc/nginx/conf.d/default.conf

# Scripts de arranque: resolver DNS activo y host del backend (ver los .sh)
COPY 40-resolver.sh /docker-entrypoint.d/40-resolver.sh
COPY 45-backend-host.sh /docker-entrypoint.d/45-backend-host.sh
RUN chmod +x /docker-entrypoint.d/40-resolver.sh /docker-entrypoint.d/45-backend-host.sh

EXPOSE 80