/* eslint-disable @typescript-eslint/no-explicit-any */
import fs from "fs/promises";
const globalThisWithWindow = globalThis as any;
globalThisWithWindow.window = globalThisWithWindow;

interface ParsedArgs {
  [key: string]: string | boolean | string[];
  _: string[];
}

function miniMist(args: string[] = []): ParsedArgs {
  const result: ParsedArgs = { _: [] };
  let i: number = 0;

  // Skip runtime and script name if present
  if (args.length > 0) {
    if (
      args[0].endsWith("bun") ||
      args[0].endsWith("node") ||
      args[0].endsWith("node.exe")
    ) {
      i += 2;
    } else if (args[0].endsWith(".js") || args[0].endsWith(".ts")) {
      i += 1;
    }
  }

  while (i < args.length) {
    const arg: string = args[i];

    // Handle end of options marker
    if (arg === "--") {
      result._.push(...args.slice(i + 1));
      break;
    }

    // Handle flags and key-value pairs
    if (arg.startsWith("--")) {
      const key: string = arg.slice(2);
      if (key.includes("=")) {
        const [k, v] = key.split("=", 2);
        result[k] = v;
      } else if (i + 1 < args.length && !args[i + 1].startsWith("-")) {
        result[key] = args[i + 1];
        i++;
      } else {
        result[key] = true;
      }
    } else if (arg.startsWith("-")) {
      const flags: string[] = arg.slice(1).split("");
      for (let j = 0; j < flags.length; j++) {
        const flag: string = flags[j];
        if (
          j === flags.length - 1 &&
          i + 1 < args.length &&
          !args[i + 1].startsWith("-")
        ) {
          result[flag] = args[i + 1];
          i++;
        } else {
          result[flag] = true;
        }
      }
    } else {
      result._.push(arg);
    }

    i++;
  }

  return result;
}

(async () => {
  const args = miniMist(process.argv);

  const argEncrypt = args.e || args.encrypt;
  const argDecrypt = args.d || args.decrypt;

  if (!argEncrypt && !argDecrypt) {
    console.log("[ARGS]", args);
    console.log("[PROCESSARGV]", process.argv);
    return console.error("Please specify --encrypt or --decrypt");
  }

  const key = await fs.readFile("key.txt", "utf-8");
  if (!key) return console.error("Key file not found");

  const resCryptoJs = await fetch(
    "https://cdn.jsdelivr.net/npm/crypto-js@4.2.0/crypto-js.min.js"
  );
  if (!resCryptoJs.ok)
    return console.error(`Failed to fetch CryptoJS: ${resCryptoJs.status}`);
  const dataCryptoJs = await resCryptoJs.text();
  new Function("window", dataCryptoJs)(globalThisWithWindow);
  if (!globalThisWithWindow.CryptoJS)
    return console.error("CryptoJS failed to load");
  const CryptoJS = globalThisWithWindow.CryptoJS;

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

export {};
