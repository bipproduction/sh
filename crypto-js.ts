/* eslint-disable @typescript-eslint/no-explicit-any */

// Simulasikan objek window untuk kompatibilitas dengan skrip UMD
const globalThisWithWindow = globalThis as any;
globalThisWithWindow.window = globalThisWithWindow;

(async () => {
  try {
    const res = await fetch(
      "https://cdn.jsdelivr.net/npm/crypto-js@4.2.0/crypto-js.min.js"
    );
    const data = await res.text();
    // Jalankan skrip dalam konteks globalThis
    new Function("window", data)(globalThis);
    console.log(globalThis.CryptoJS.HmacSHA256("Message", "Key").toString());
  } catch (error) {
    console.error("Error:", error);
  }
})();
