# Use a lightweight, pre-configured NGINX web server
FROM nginx:alpine

# Copy our custom HTML file into the server
COPY index.html /usr/share/nginx/html/index.html

# Expose port 80 so the load balancer can talk to it
EXPOSE 80