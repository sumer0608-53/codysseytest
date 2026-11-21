FROM nginx:alpine
LABEL org.opencontainers.image.title="Development Workstation Mission"
COPY app/index.html /usr/share/nginx/html/index.html
