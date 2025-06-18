/* eslint-disable @typescript-eslint/no-explicit-any */
import fs from "fs/promises";

(async () => {
  console.log(process.argv)
  const [type] = process.argv.slice(2);
  console.log(type)

  if (type !== "encrypt" && type !== "decrypt") {
    console.error("Invalid type encrypt or decrypt");
    return;
  }

  const key = await fs.readFile("key.txt", "utf-8");
  if (!key) return console.error("Key file not found");

  const globalThisWithWindow = globalThis as any;
  globalThisWithWindow.window = globalThisWithWindow;

  const res = await fetch(
    "https://cdn.jsdelivr.net/npm/crypto-js@4.2.0/crypto-js.min.js"
  );
  if (!res.ok) return console.error(`Failed to fetch CryptoJS: ${res.status}`);
  const data = await res.text();
  new Function("window", data)(globalThis);
  if (!globalThis.CryptoJS) return console.error("CryptoJS failed to load");
  const CryptoJS = globalThis.CryptoJS;

  if (type === "encrypt") {
    const source = await fs.readFile("source.txt", "utf-8");
    if (!source) return console.error("Source file not found");
    const encrypted = CryptoJS.AES.encrypt(source, key).toString();
    await fs.writeFile("encrypted.txt", encrypted);
    console.info("Encrypted");
    return;
  }

  if (type === "decrypt") {
    const fileEncrypted = await fs.readFile("encrypted.txt", "utf-8");
    if (!fileEncrypted) return console.error("Encrypted file not found");
    const decrypted = CryptoJS.AES.decrypt(fileEncrypted, key).toString(
      CryptoJS.enc.Utf8
    );
    await fs.writeFile("decrypted.txt", decrypted);
    console.info("Decrypted");
    return;
  }
})();

export {};
