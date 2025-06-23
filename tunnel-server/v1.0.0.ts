/**
 * # DOCKER TUNNEL SERVER
 * ---
 * 
 * ### ENCRYPT KEY
 * encrypt key 2x
 * buat key baru
 * file:
 *  1. key.txt
 *  2. source.txt
 * jalankan crypto : curl -s https://cdn.jsdelivr.net/gh/bipproduction/sh/crypto/v1.0.0.ts | bun run - --decrypt
 * akan menghasilkan file encrypted.txt
 * cp encrypted.txt ke key.txt
 * cp .env.encrypted ke source.txt
 * jalankan crypto lagi : curl -s https://cdn.jsdelivr.net/gh/bipproduction/sh/crypto/v1.0.0.ts | bun run - --decrypt
 * akan menghasilkan file encrypted.txt
 * cp encrypted.txt ke .env
 *
 * ### INFO
 * - setelah key dibuat dan instalasi selesai, jalankan perintah `docker-compose up -d` untuk memulai server
 */


import fs from "fs/promises";
export {};

const configText = `module.exports = {
    apps: [
      {
        name: 'health-check',
        script: 'echo',
        args: '"health-check"',
        instances: 1,
        autorestart: true,
        watch: false,
        max_memory_restart: '300M'
      }
    ]
}
`;

console.log("[INFO]", "creating directories ...")
await fs.mkdir("apps", { recursive: true }).catch(() => {});
console.log("[INFO]", "apps created ...")
await fs.mkdir("cloudflared", { recursive: true }).catch(() => {});
console.log("[INFO]", "cloudflared created ...")
await fs.mkdir("postgres-data", { recursive: true }).catch(() => {});
console.log("[INFO]", "postgres-data created ...")
await fs.writeFile("apps/ecosystem.config.js", configText).catch(() => {});
console.log("[INFO]", "ecosystem.config.js created ...")

const dockerComposeText = await fetch(
  "https://raw.githubusercontent.com/bipproduction/sh/refs/heads/main/tunnel-server/docker-compose.yml"
).then((res) => res.text());
await fs.writeFile("docker-compose.yml", dockerComposeText).catch(() => {});
console.log("[INFO]", "docker-compose.yml created ...")

const dockerFileText = await fetch(
  "https://cdn.jsdelivr.net/gh/bipproduction/sh/tunnel-server/Dockerfile"
).then((res) => res.text());
await fs.writeFile("Dockerfile", dockerFileText).catch(() => {});
console.log("[INFO]", "Dockerfile created ...")

const envEncryptedMakuroStudioText = await fetch(
  "https://cdn.jsdelivr.net/gh/bipproduction/sh/tunnel-server/.env.encrypted.makuro-studio"
).then((res) => res.text());
await fs.writeFile(".env.encrypted", envEncryptedMakuroStudioText).catch(() => {});
console.log("[INFO]", ".env.encrypted makuro-studio created ...")

const envEncryptedBipOfficeText = await fetch(
  "https://cdn.jsdelivr.net/gh/bipproduction/sh/tunnel-server/.env.encrypted.bip-office"
).then((res) => res.text());
await fs.writeFile(".env.encrypted", envEncryptedBipOfficeText).catch(() => {});
console.log("[INFO]", ".env.encrypted bip-office created ...")
