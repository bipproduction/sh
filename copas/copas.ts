import { writeFileSync, readFileSync, existsSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { execSync, spawn } from "child_process";

// Lokasi file clipboard fallback
const clipboardPath = join(tmpdir(), "copas-clipboard.txt");

// Deteksi lingkungan
function detectEnvironment() {
  const hasDisplay = !!process.env.DISPLAY || !!process.env.WAYLAND_DISPLAY;
  const isWSL =
    !!process.env.WSL_DISTRO_NAME ||
    (existsSync("/proc/version") &&
      readFileSync("/proc/version", "utf8")
        .toLowerCase()
        .includes("microsoft"));
  const isMacOS = process.platform === "darwin";
  const isWindows = process.platform === "win32";
  const isLinux = process.platform === "linux";
  const isSSH =
    !!process.env.SSH_CLIENT ||
    !!process.env.SSH_TTY ||
    !!process.env.SSH_CONNECTION;

  return {
    hasGUI: hasDisplay && !isSSH,
    isServer: isSSH || (!hasDisplay && !isMacOS && !isWindows),
    platform: process.platform,
    isWSL,
    isMacOS,
    isWindows,
    isLinux,
    isSSH,
  };
}

// Fungsi untuk mengakses clipboard sistem
async function writeToSystemClipboard(text: string): Promise<boolean> {
  const env = detectEnvironment();

  try {
    if (env.isMacOS) {
      // macOS - menggunakan pbcopy
      const proc = spawn("pbcopy", [], { stdio: "pipe" });
      proc.stdin.write(text);
      proc.stdin.end();
      return new Promise((resolve) => {
        proc.on("close", (code) => resolve(code === 0));
      });
    } else if (env.isWindows || env.isWSL) {
      // Windows atau WSL - menggunakan clip.exe
      const clipCmd = env.isWSL ? "clip.exe" : "clip";
      const proc = spawn(clipCmd, [], { stdio: "pipe" });
      proc.stdin.write(text);
      proc.stdin.end();
      return new Promise((resolve) => {
        proc.on("close", (code) => resolve(code === 0));
      });
    } else if (env.isLinux && env.hasGUI) {
      // Linux dengan GUI - coba xclip atau xsel
      let clipboardCmd = null;

      // Cek ketersediaan xclip
      try {
        execSync("which xclip", { stdio: "ignore" });
        clipboardCmd = ["xclip", "-selection", "clipboard"];
      } catch {
        // Jika xclip tidak ada, coba xsel
        try {
          execSync("which xsel", { stdio: "ignore" });
          clipboardCmd = ["xsel", "--clipboard", "--input"];
        } catch {
          return false; // Tidak ada clipboard tool yang tersedia
        }
      }

      if (clipboardCmd) {
        const proc = spawn(clipboardCmd[0], clipboardCmd.slice(1), {
          stdio: "pipe",
        });
        proc.stdin.write(text);
        proc.stdin.end();
        return new Promise((resolve) => {
          proc.on("close", (code) => resolve(code === 0));
        });
      }
    }

    return false; // Tidak didukung di platform ini
  } catch (error) {
    console.error("❌ Error writing to clipboard:", error);
    return false;
  }
}

async function readFromSystemClipboard(): Promise<string | null> {
  const env = detectEnvironment();

  try {
    if (env.isMacOS) {
      // macOS - menggunakan pbpaste
      const result = execSync("pbpaste", { encoding: "utf8" });
      return result;
    } else if (env.isWindows) {
      // Windows - menggunakan PowerShell
      const result = execSync('powershell.exe -command "Get-Clipboard"', {
        encoding: "utf8",
      });
      return result.replace(/\r\n/g, "\n").trim();
    } else if (env.isWSL) {
      // WSL - menggunakan powershell.exe
      const result = execSync('powershell.exe -command "Get-Clipboard"', {
        encoding: "utf8",
      });
      return result.replace(/\r\n/g, "\n").trim();
    } else if (env.isLinux && env.hasGUI) {
      // Linux dengan GUI - coba xclip atau xsel
      try {
        execSync("which xclip", { stdio: "ignore" });
        const result = execSync("xclip -selection clipboard -o", {
          encoding: "utf8",
        });
        return result;
      } catch {
        try {
          execSync("which xsel", { stdio: "ignore" });
          const result = execSync("xsel --clipboard --output", {
            encoding: "utf8",
          });
          return result;
        } catch {
          return null;
        }
      }
    }

    return null; // Tidak didukung di platform ini
  } catch (error) {
    console.error("❌ Error reading from clipboard:", error);
    return null;
  }
}

// Fungsi untuk menulis ke clipboard (sistem atau fallback)
async function writeClipboard(text: string): Promise<void> {
  const env = detectEnvironment();

  // Coba tulis ke clipboard sistem terlebih dahulu
  const systemSuccess = await writeToSystemClipboard(text);

  if (systemSuccess) {
    console.error(`✅ Tersalin ke clipboard sistem (${env.platform})`);
  } else {
    // Fallback ke file clipboard
    writeFileSync(clipboardPath, text, "utf8");
    if (env.isServer) {
      console.error("📋 Tersimpan ke clipboard fallback (lingkungan server)");
    } else {
      console.error(
        "📋 Tersimpan ke clipboard fallback (clipboard sistem tidak tersedia)"
      );
    }
  }
}

// Fungsi untuk membaca dari clipboard (sistem atau fallback)
async function readClipboard(): Promise<string | null> {
  const env = detectEnvironment();

  // Coba baca dari clipboard sistem terlebih dahulu
  const systemClipboard = await readFromSystemClipboard();

  if (systemClipboard !== null) {
    return systemClipboard;
  } else if (existsSync(clipboardPath)) {
    // Fallback ke file clipboard
    if (env.isServer) {
      console.error("📋 Dibaca dari clipboard fallback (lingkungan server)");
    } else {
      console.error(
        "📋 Dibaca dari clipboard fallback (clipboard sistem tidak tersedia)"
      );
    }
    return readFileSync(clipboardPath, "utf8");
  }

  return null;
}

// Fungsi untuk menampilkan info lingkungan
function showEnvironmentInfo(): void {
  const env = detectEnvironment();

  console.log("🔍 Informasi Lingkungan:");
  console.log(`   Platform: ${env.platform}`);
  console.log(`   GUI: ${env.hasGUI ? "✅" : "❌"}`);
  console.log(`   Server: ${env.isServer ? "✅" : "❌"}`);
  console.log(`   SSH: ${env.isSSH ? "✅" : "❌"}`);

  if (env.isWSL) console.log("   WSL: ✅");
  if (env.hasGUI) {
    console.log(
      `   Display: ${
        process.env.DISPLAY || process.env.WAYLAND_DISPLAY || "unknown"
      }`
    );
  }
  console.log();
}

// Main logic
async function main() {
  const isInputTTY = process.stdin.isTTY;
  const isOutputTTY = process.stdout.isTTY;
  const args = process.argv.slice(2);

  // Handle command line arguments
  if (args.includes("--info") || args.includes("-i")) {
    showEnvironmentInfo();
    return;
  }

  if (args.includes("--help") || args.includes("-h")) {
    console.log(`📋 Clipboard Manager v2.0

Usage:
  bun copas.ts < file.txt     # Salin isi file ke clipboard
  bun copas.ts > file.txt     # Tempel isi clipboard ke file
  bun copas.ts --info         # Tampilkan info lingkungan
  bun copas.ts --test         # Test clipboard functionality
  bun copas.ts --clear        # Kosongkan clipboard

Features:
  ✅ Auto-detect GUI/Server environment
  ✅ System clipboard integration (macOS/Windows/Linux)
  ✅ Fallback to file-based clipboard
  ✅ WSL support
  ✅ SSH environment detection`);
    return;
  }

  if (args.includes("--test")) {
    console.log("🧪 Testing clipboard functionality...");
    const testText = "Test clipboard: " + new Date().toISOString();
    await writeClipboard(testText);

    const readBack = await readClipboard();
    if (readBack && readBack.includes("Test clipboard:")) {
      console.log("✅ Clipboard test berhasil!");
    } else {
      console.log("❌ Clipboard test gagal!");
    }
    return;
  }

  if (args.includes("--clear")) {
    await writeClipboard("");
    console.log("🗑️ Clipboard dikosongkan");
    return;
  }

  if (!isInputTTY) {
    // Mode: bun copas.ts < data.txt → baca stdin (file), simpan ke clipboard
    let input = "";
    for await (const chunk of process.stdin) {
      input += Buffer.from(chunk).toString("utf8");
    }
    await writeClipboard(input);
  } else if (!isOutputTTY) {
    // Mode: bun copas.ts > data.txt → tulis clipboard ke stdout
    const output = await readClipboard();
    if (output !== null) {
      process.stdout.write(output);
    } else {
      console.error("❌ Clipboard kosong atau tidak dapat diakses.");
      process.exit(1);
    }
  } else {
    // Tanpa redirect: tampilkan info penggunaan
    showEnvironmentInfo();
    console.log(`📋 Clipboard Manager Usage:
  bun copas.ts < file.txt     # Salin isi file ke clipboard
  bun copas.ts > file.txt     # Tempel isi clipboard ke file
  bun copas.ts --info         # Tampilkan info lingkungan  
  bun copas.ts --test         # Test clipboard functionality
  bun copas.ts --help         # Tampilkan bantuan lengkap`);
  }
}

// Jalankan main function
main().catch((error) => {
  console.error("❌ Error:", error.message);
  process.exit(1);
});
