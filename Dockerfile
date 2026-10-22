FROM debian:13

# On installe ruby et les utilitaires système de base demandés
RUN apt-get update && apt-get install -y \
    ruby \
    iproute2 \
    procps \
    systemd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY audit.rb .
RUN chmod +x audit.rb

# On définit le point d'entrée pour que les arguments de 'docker run' soient passés au script
ENTRYPOINT ["ruby", "audit.rb"]
