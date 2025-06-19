/* eslint-disable @typescript-eslint/no-explicit-any */
import fs from "fs/promises";

const comot = async (url: string) => (
  new Function("window", await (await fetch(url)).text())(globalThis),
  globalThis as any
);

const { minimist } = await comot(
  "https://cdn.jsdelivr.net/gh/bipproduction/sh/minimist/index.js"
);

const { dedent } = await comot(
  "https://cdn.jsdelivr.net/gh/bipproduction/sh/dedent/index.js"
);

const { CryptoJS } = await comot(
  "https://cdn.jsdelivr.net/npm/crypto-js@4.2.0/crypto-js.min.js"
);

await comot("https://cdn.jsdelivr.net/gh/bipproduction/sh/colors/v1.0.1.js");

(async () => {
  const args = minimist(process.argv.slice(2));

  const argEncrypt = args.e || args.encrypt;
  const argDecrypt = args.d || args.decrypt;

  if (!argEncrypt && !argDecrypt) {
    console.info(
      dedent`
      Usage: x [options]

      Options:
        --encrypt, -e  Encrypt file
        --decrypt, -d  Decrypt file

      Example:
        x -e
        
      File Required Encrypt:
        key.txt
        source.txt

      File Generated Encrypt:
        encrypted.txt

      File Required Decrypt:
        key.txt
        encrypted.txt

      File Generated Decrypt:
        decrypted.txt
    `.green
    );
    return console.error("Please specify --encrypt or --decrypt");
  }

  const key = await fs.readFile("key.txt", "utf-8");
  if (!key) return console.error("Key file not found");

  if (argEncrypt) {
    const source = await fs.readFile("source.txt", "utf-8");
    if (!source) return console.error("Source file not found");
    const encrypted = CryptoJS.AES.encrypt(source, key).toString();
    await fs.writeFile("encrypted.txt", encrypted);
    console.info("Encrypted");
    return;
  }

  if (argDecrypt) {
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
