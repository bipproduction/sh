```ts

import "dotenv/config";
import { initializeApp, cert, App, ServiceAccount } from "firebase-admin/app";
import { getMessaging, Message } from "firebase-admin/messaging";
import path from "path";

// --- KONFIGURASI ---
const CONFIG = {
  /**
   * Konten notifikasi default yang akan dikirim.
   */
  notificationPayload: {
    title: "Sistem Desa Mandiri",
    body: "Ada informasi baru untuk Anda, silakan periksa aplikasi.",
  },

  /**
   * Pengaturan untuk mekanisme coba lagi (retry) jika terjadi kegagalan jaringan.
   */
  retry: {
    maxRetries: 3, // Jumlah maksimal percobaan ulang
    delay: 2000,   // Waktu tunda antar percobaan dalam milidetik (ms)
  },
};
// --- AKHIR KONFIGURASI ---

/**
 * Membangun objek service account dari variabel lingkungan.
 */
function getServiceAccount(): ServiceAccount {
  const privateKey = process.env.GOOGLE_PRIVATE_KEY?.replace(/\n/g, '\n');

  if (!process.env.GOOGLE_PROJECT_ID || !process.env.GOOGLE_CLIENT_EMAIL || !privateKey) {
    console.error("KRITIS: Variabel lingkungan Firebase (PROJECT_ID, CLIENT_EMAIL, PRIVATE_KEY) tidak lengkap.");
    process.exit(1);
  }

  return {
    projectId: process.env.GOOGLE_PROJECT_ID,
    clientEmail: process.env.GOOGLE_CLIENT_EMAIL,
    privateKey,
  };
}

/**
 * Inisialisasi Firebase Admin SDK.
 * Hanya akan menginisialisasi satu kali.
 */
let firebaseApp: App | null = null;
function initializeFirebase(): App {
  if (firebaseApp) {
    return firebaseApp;
  }
  try {
    const serviceAccount = getServiceAccount();
    firebaseApp = initializeApp({
      credential: cert(serviceAccount),
    });
    console.log("Firebase Admin SDK berhasil diinisialisasi.");
    return firebaseApp;
  } catch (error: any) {
    console.error("KRITIS: Gagal inisialisasi Firebase. Pastikan variabel lingkungan sudah benar.");
    console.error(`Detail Error: ${error.message}`);
    process.exit(1); // Keluar dari proses jika Firebase gagal diinisialisasi
  }
}

/**
 * Mengambil daftar token perangkat dari database.
 * TODO: Ganti fungsi ini dengan logika untuk mengambil token dari database Anda.
 * @returns {Promise<string[]>} Daftar token FCM.
 */
async function getDeviceTokens(): Promise<string[]> {
  console.log("Mengambil token perangkat dari sumber data...");
  // CONTOH: Ini adalah data dummy. Seharusnya Anda mengambilnya dari database.
  // Misalnya: const users = await prisma.user.findMany({ where: { fcmToken: { not: null } } });
  // return users.map(user => user.fcmToken);
  const exampleTokens: string[] = [
    "c89yuexsS_uc1tOErVPu5a:APA91bEb6tEKXAfReZjFVJ2mMyOzoW_RXryLSnSJTpbIVV3G0L_DCNkLuRvJ02Ip-Erz88QCQBAt-C2SN8eCRxu3-v1sBzXzKPtDv-huXpkjXsyrkifqvUo", // Valid
    "cRz96GHKTRaQaRJ35e8Hxa:APA91bEUSxE0VPbqKSzseQ_zGhbYsDofMexKykRw7o_3z2aPM9YFmZbeA2enrmb3qjdZ2g4-QQtiNHAyaZqAT1ITOrwo9jVJlShTeABmEFYP5GLEUZ3dlLc", // Valid
    "token_tidak_valid_ini_pasti_gagal_12345", // Contoh token tidak valid
  ];
  console.log(`Berhasil mendapatkan ${exampleTokens.length} token.`);
  return exampleTokens;
}

/**
 * Membuat array pesan yang akan dikirim ke setiap token.
 * @param {string[]} tokens - Daftar token FCM.
 * @returns {Message[]} Array objek pesan untuk `sendEach`.
 */
function constructMessages(tokens: string[]): Message[] {
  return tokens.map((token) => ({
    token,
    notification: {
      title: CONFIG.notificationPayload.title,
      body: CONFIG.notificationPayload.body,
    },
    data: {
      // Anda bisa menambahkan data tambahan di sini
      // Contoh: click_action: "FLUTTER_NOTIFICATION_CLICK"
      timestamp: String(Date.now()),
    },
    android: {
      priority: "high",
      notification: {
        sound: "default",
        channelId: "default_channel", // Pastikan channel ini ada di aplikasi Android Anda
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  }));
}

/**
 * Menangani respons dari `sendEach` untuk mencatat keberhasilan dan kegagalan.
 * @param response - Objek respons dari `sendEach`.
 * @param originalTokens - Daftar token asli yang dikirimi pesan.
 */
function handleSendResponse(response: any, originalTokens: string[]) {
  console.log("Total notifikasi berhasil dikirim:", response.successCount);
  console.log("Total notifikasi gagal:", response.failureCount);

  const tokensToRemove: string[] = [];

  response.responses.forEach((resp: any, index: number) => {
    const token = originalTokens[index];
    if (resp.success) {
      // console.log(`Pesan ke token ...${token.slice(-6)} berhasil:`, resp.messageId);
    } else {
      console.error(`Pesan ke token ...${token.slice(-6)} GAGAL:`, resp.error.code);
      // Jika token tidak lagi terdaftar, tandai untuk dihapus
      if (
        resp.error.code === "messaging/registration-token-not-registered" ||
        resp.error.code === "messaging/invalid-registration-token"
      ) {
        tokensToRemove.push(token);
      }
    }
  });

  if (tokensToRemove.length > 0) {
    console.warn("Token berikut tidak valid dan harus dihapus dari database:");
    tokensToRemove.forEach(token => console.log(`- ${token}`));
    // TODO: Implementasikan logika untuk menghapus token-token di atas dari database Anda.
    // Misalnya: await prisma.user.updateMany({ where: { fcmToken: { in: tokensToRemove } }, data: { fcmToken: null } });
  }
}

/**
 * Fungsi utama untuk mengirim notifikasi ke banyak perangkat dengan mekanisme retry.
 * @param {Message[]} messages - Array pesan yang akan dikirim.
 * @param {string[]} tokens - Daftar token asli untuk logging.
 */
async function sendNotifications(messages: Message[], tokens: string[]) {
  let lastError: any;

  for (let attempt = 1; attempt <= CONFIG.retry.maxRetries; attempt++) {
    try {
      const response = await getMessaging().sendEach(messages);
      handleSendResponse(response, tokens);
      return; // Berhasil, keluar dari fungsi
    } catch (error: any) {
      lastError = error;
      console.error(`Percobaan pengiriman ke-${attempt} gagal:`, error.message);

      // Hanya coba lagi jika error berhubungan dengan jaringan
      const isNetworkError = error.code === "app/network-error" || error.code?.includes("network");
      if (isNetworkError && attempt < CONFIG.retry.maxRetries) {
        console.log(`Menunggu ${CONFIG.retry.delay}ms sebelum mencoba lagi...`);
        await new Promise((resolve) => setTimeout(resolve, CONFIG.retry.delay));
      } else {
        // Jika bukan error jaringan atau sudah mencapai batas retry, lempar error
        throw new Error(`Gagal mengirim notifikasi setelah ${attempt} percobaan: ${error.message}`);
      }
    }
  }
  throw lastError;
}

/**
 * Fungsi orchestrator untuk menjalankan seluruh proses.
 */
export async function sendMultiple() {
  try {
    initializeFirebase();

    const tokens = await getDeviceTokens();
    if (tokens.length === 0) {
      console.log("Tidak ada token perangkat yang ditemukan. Proses dihentikan.");
      return;
    }

    const messages = constructMessages(tokens);

    console.log(`
Mempersiapkan pengiriman ${messages.length} notifikasi...`);
    await sendNotifications(messages, tokens);

    console.log("Proses pengiriman notifikasi selesai.");
  } catch (error: any) {
    console.error("Terjadi error fatal dalam proses pengiriman:", error.message);
    process.exit(1);
  }
}


```

```env
# Environment variables declared in this file are automatically made available to Prisma.
# See the documentation for more detail: https://pris.ly/d/prisma-schema#accessing-environment-variables-from-the-schema

# Prisma supports the native connection string format for PostgreSQL, MySQL, SQLite, SQL Server, MongoDB and CockroachDB.
# See the documentation for all the connection string options: https://pris.ly/d/connection-strings

DATABASE_URL="postgresql://bip:Production_123d@localhost:5433/sistem_desa_mandiri?schema=public"
URL="http://localhost:3000"
WS_APIKEY="eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjp7ImlkIjoiY20wdnQ4bzFrMDAwMDEyenE1eXl1emd5YiIsIm5hbWUiOiJhbWFsaWEiLCJlbWFpbCI6ImFtYWxpYUBiaXAuY29tIiwiQXBpS2V5IjpbeyJpZCI6ImNtMHZ0OG8xcjAwMDIxMnpxZDVzejd3eTgiLCJuYW1lIjoiZGVmYXVsdCJ9XX0sImlhdCI6MTcyNTkzNTE5MiwiZXhwIjo0ODgxNjk1MTkyfQ.7U-HUnNBDmeq_6XXohiFZjFnh2rSzUPMHDdrUKOd7G4"
NEXT_PUBLIC_VAPID_PUBLIC_KEY=BBC6ml3Ro9eBdhSq_DPx0zQ0hBH4NvOeJbFXdQy3cZ-UyJ2m6V1RyO1XD9B08kshTdVNoGZeqBDKBPzpWgwRBNY
VAPID_PRIVATE_KEY=p9GfSmCRJe1_dzwKqe29HF81mTE2JwlrW4cXINnkI7c
WIBU_REALTIME_KEY="padahariminggukuturutayahkekotanaikdelmanistimewakududukdimuka"
FCM_KEY=BAWSIlqadurVCx6wm50KiMVwd01IosHo3g7731yhPmweVqUDu1zx0l2ytKL6DSOmbEDVxuBryNJKYLEXCRiLCos

# FCM
GOOGLE_PROJECT_ID=mobile-darmasaba
GOOGLE_PRIVATE_KEY_ID=764e1207d5acf4db2eac539256c8f1bf397c7d8f
GOOGLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCwCU9PBpAbXsOl\ntb1syvWrmH3FSDRyI4oOVWZJRqYX+j44UTNfzTjYySpNy7x1lr91uOC2GGHJeFvT\nLg5er6uvzFvzwg42A8Rz4+aqxlUhvhNXYRyfaaP7tbui5X9GEmhKYzvYd6T/6z1u\njo7LE1tBaiB8eB69tSJidGcr90yXOsbvKFgaPkpvlrseNR/t0PYDUaXHsxdKvCHI\ntK13KxhJCJrU9+/W1Wwr+45WGfK9m+jLVuOEZT9dd3FUgDn/0CFzykZLA0iHRLjx\neczahlrlvLVCtUIJjHbmsjG8vLZyl6/puh1l2OkEZyADb6m7OOxFVTo5ADZvj4nD\nVCCirdMVAgMBAAECggEAMF0mbnJBpltnSkA/vkOWsmHPcCOx0QgFloGM/CXOXTkR\n3hwlDrWN4DWIi14ltXLIwFmeVzkkqJsKM19scEQ4WbC+NJ7Ek79+Ok7LYXDjE8Wq\nf6+9EukNtgqMdikySfilsYZI+2SHrw4czyKYhZ+YS0USjs/btkgtHbqYW+JyJvv4\nlXAGp3129kbOHTc6+DBq6tn4XiRMKUdBNtcRHe9k+zAIuwbeAdsl4bock1ADnMIv\n/Q4FfOua+nJl8MUpPCZDvz14az+3j/rUVkR/wgDqQirFNRfFfpEPNM2oXVSjp0oK\nTC8NEy5mN4aj0DYS8U2x8barsAFDr5N4L9JxTtdlgwKBgQDkXK9iieIe1/yJFDw6\ntHbQu/bl+t82DESapss62++6ckh2mo+IScvVg/rCwXIag7IRQO40BHWwYTrOwTbj\nD1VUamn6UaqJHpIjDj/SK+As3DumuOTcb+kbJq9TpjLGeR2hj0aKcFXAjL5+B+yr\nBt7fVsB2uhouS9aD68HV8azsxwKBgQDFV2yRKgSf11vNRsxtJekpZ7ruF4h8OZPA\nHcq1kMDPRJcuVD9XwG7RAEgxcErKKS6NrrT/2Iaq5r+P3owgxZ6yB5pabGGvsgcg\nqrvsVEjzETsrrDbp5IevwE/MTwplakr6vJBnfAyjqMbDQSGSZPp+6S8M5JtZhJDL\n9Pqy6yxNQwKBgEE9ZXGuWKZdKC11VXukAOnDOVcco9ZKDPNtwVPQb52BdshDgcv6\n4Tvfl606HMIMa7vYI/VCbOj17hoRQv/9anBScnJsEF9aF3/iW0NM+591T6li2ydK\n5Xq3Q5GPQqRHB7sXNpzoWOdIjkdtNiTqMpP1sch5hG9DhUZs/RSFFdUTAoGBALyV\nyD2NXu/1WVh5cQBZe1FDPMMtIBQ+3bB5h+8tDuTEEomGnyXX0s7OKy97tS0uX7us\nGnJo1IDblHMDZPwofnh5hYsmCdBiHCeeoYm+HhyS+e3JXIz2BKjy6g8/9ZpnEpI8\nwu7yAA4iSxfq1Q9Win/fjUQP71mDsvAGA9IZpbOLAoGBAK57RjNemVh3oNB5ZaQs\n45WzfmPPjKoDQdMYLtohHz9HhPxYFLuvlDc/9OcWFCz3tZHtyDrUtXvv+vX+rG4Y\nemxXkqdg3lYo7nayw772myJb2w6QIfGyuSRx/C1/phmPhp+UkHk7B+KdvWhpPmCC\nBufws2LSn5VZzivO6LrwSCfR\n-----END PRIVATE KEY-----\n"
GOOGLE_CLIENT_EMAIL=firebase-adminsdk-fbsvc@mobile-darmasaba.iam.gserviceaccount.com
GOOGLE_CLIENT_ID=105653213329235865762
GOOGLE_AUTH_URI=https://accounts.google.com/o/oauth2/auth
GOOGLE_TOKEN_URI=https://oauth2.googleapis.com/token
GOOGLE_AUTH_PROVIDER_CERT_URL=https://www.googleapis.com/oauth2/v1/certs
GOOGLE_CLIENT_CERT_URL=https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40mobile-darmasaba.iam.gserviceaccount.com

```
