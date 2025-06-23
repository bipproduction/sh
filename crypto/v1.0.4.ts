/* eslint-disable @typescript-eslint/no-explicit-any */
import fs from "fs/promises";
import path from "path";

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
        crp-ky key
        crp-so source

      File Generated Encrypt:
        crp-en encrypted

      File Required Decrypt:
        crp-ky key
        crp-en encrypted

      File Generated Decrypt:
        crp-dec decrypted
    `.green
    );
    return console.error("Please specify --encrypt or --decrypt");
  }

  const key = await fs.readFile(path.join(__dirname, "crp-ky"));
  if (!key) return console.error("Ky file not found");

  if (argEncrypt) {
    const source = await fs.readFile(path.join(__dirname, "crp-so"));
    if (!source) return console.error("so file not found");

    console.info("Encrypting ...")
    const encrypted = CryptoJS.AES.encrypt(source, key).toString(CryptoJS.enc.Utf8);
    await fs.writeFile(path.join(__dirname, "crp-en"), encrypted);
    console.info("Encrypted !");
    return;
  }

  if (argDecrypt) {
    const fileEncrypted = await fs.readFile(path.join(__dirname, "crp-en"));
    if (!fileEncrypted) return console.error("Encrypted file not found");
    console.info("Decrypting ...")
    const decrypted = CryptoJS.AES.decrypt(fileEncrypted, key).toString(CryptoJS.enc.Utf8);
    await fs.writeFile(path.join(__dirname, "crp-de"), decrypted);
    console.info("Decrypted !");
    return;
  }
})();
