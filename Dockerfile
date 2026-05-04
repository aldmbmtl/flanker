# Flanker Python authority server
# Build:  docker build -t flanker-server .
# Run:    docker run --rm -p 7890:7890 flanker-server

FROM python:3.12-slim

WORKDIR /app

# Install dependencies before copying source so the layer is cached
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the server package (no Godot assets needed at runtime)
COPY server/ ./server/

# Bind on 0.0.0.0 inside the container so the port mapping works
ENV SERVER_HOST=0.0.0.0
ENV SERVER_PORT=7890

EXPOSE 7890

CMD ["python", "-m", "server.main"]
