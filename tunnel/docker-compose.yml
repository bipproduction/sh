services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    restart: unless-stopped
    volumes:
      - ./cloudflared:/root/.cloudflared
    networks:
      - cloudflared-network
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    healthcheck:
      test: ["CMD", "cloudflared", "--version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  ssh-server:
    image: linuxserver/openssh-server:latest
    container_name: ssh-server
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Makasar
      - PUBLIC_KEY=${SSH_PUBLIC_KEY}
      - USER_NAME=makuro
      - SUDO_ACCESS=false
    volumes:
      - ./ssh-config:/config
    networks:
      - cloudflared-network
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "2222"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

networks:
  cloudflared-network:
    external: true
