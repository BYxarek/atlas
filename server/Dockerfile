FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates python3 libstdc++6 libfontconfig1 libx11-6 libxcursor1 \
    libxinerama1 libxi6 libxrandr2 libgl1 libasound2 \
    && rm -rf /var/lib/apt/lists/*

FROM runtime AS builder
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fL --retry 3 https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o /tmp/godot.zip \
    && echo 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4  /tmp/godot.zip' | sha256sum -c - \
    && unzip /tmp/godot.zip -d /tmp \
    && install /tmp/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
WORKDIR /project
COPY project.godot main.tscn export_presets.cfg ./
COPY src ./src
COPY assets/world.json assets/military.json assets/icon.svg ./assets/
COPY assets/i18n ./assets/i18n
COPY assets/legal ./assets/legal
RUN godot --headless --editor --import --quit \
    && mkdir /out \
    && godot --headless --export-pack 'VPS Server' /out/AtlasServer.pck

FROM runtime
RUN mkdir /data /app && chown 10001:10001 /data /app
COPY --from=builder /usr/local/bin/godot /usr/local/bin/godot
COPY --from=builder /out/AtlasServer.pck /app/AtlasServer.pck
COPY server/entrypoint.py /app/entrypoint.py
ENV ATLAS_PORT=24760 ATLAS_MAX_ROOMS=8 ATLAS_DATA_DIR=/data XDG_DATA_HOME=/tmp/godot HOME=/tmp
USER 10001:10001
WORKDIR /app
EXPOSE 24760/tcp
ENTRYPOINT ["python3", "/app/entrypoint.py"]
