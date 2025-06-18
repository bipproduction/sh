const miniMist = (function () {
  "use strict";

  function parseArgs(args = []) {
    const result = { _: [] };
    let i = 0;

    // Lewati nama runtime dan skrip jika ada
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
      const arg = args[i];

      // Tangani penanda akhir opsi
      if (arg === "--") {
        result._.push(...args.slice(i + 1));
        break;
      }

      // Tangani flag dan pasangan kunci-nilai
      if (arg.startsWith("--")) {
        const key = arg.slice(2);
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
        const flags = arg.slice(1).split("");
        for (let j = 0; j < flags.length; j++) {
          const flag = flags[j];
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

  return parseArgs;
})();

export default miniMist;
