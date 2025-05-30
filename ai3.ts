const [host] = process.argv.slice(2);
if (!host) {
  throw new Error("Host diperlukan, contoh: bun run ai.ts ");
}
const OLLAMA: string = `https://${host}/api/generate`;
const MODEL: string = "qwen2.5:3b";
// const MODEL: string = "qwen3:4b";

interface Agent {
  id: string;
  context: string;
}

const AGENTS: Agent[] = [
  {
    id: "agen-1",
    context:
      "Kamu adalah agen AI yang penasaran, suka mengajukan pertanyaan mendalam tentang teknologi kecerdasan buatan, pemrograman, dan inovasi teknologi.",
  },
  {
    id: "agen-2",
    context:
      "Kamu adalah agen AI yang berpengetahuan luas, senang menjawab pertanyaan secara rinci tentang AI dan pemrograman, lalu mengajukan pertanyaan lanjutan yang relevan.",
  },
];

async function generateResponse(agent: Agent, prompt: string): Promise<string> {
  try {
    const response = await fetch(OLLAMA, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        prompt: `${agent.context}\n\n${prompt}`,
        stream: true,
      }),
    });

    if (!response.ok) {
      throw new Error(`Kesalahan HTTP! Status: ${response.status}`);
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error("Badan respons tidak dapat dibaca");
    }

    let fullResponse: string = "";
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const chunk = decoder.decode(value, { stream: true });
      const lines = chunk.split("\n").filter((line) => line.trim());

      for (const line of lines) {
        try {
          const data = JSON.parse(line);
          if (data.response) {
            fullResponse += data.response;
            process.stdout.write(data.response);
          }
        } catch (error) {
          console.error(
            `Kesalahan parsing streaming untuk ${agent.id}:`,
            error instanceof Error ? error.message : "Kesalahan tidak diketahui"
          );
        }
      }
    }

    process.stdout.write("\n");
    return fullResponse.trim();
  } catch (error) {
    console.error(
      `Kesalahan untuk ${agent.id}:`,
      error instanceof Error ? error.message : "Kesalahan tidak diketahui"
    );
    return "Saya mengalami kesalahan, tapi mari lanjutkan. Apa selanjutnya?";
  }
}

async function conversationLoop(): Promise<void> {
  let currentAgent: Agent = AGENTS[0];
  let otherAgent: Agent = AGENTS[1];
  let lastResponse: string =
    "Halo! Mari mulai diskusi. Apa tren terbaru dalam pengembangan kecerdasan buatan yang menurutmu paling menarik?";

  console.log(`${currentAgent.id}: ${lastResponse}`);

  while (true) {
    [currentAgent, otherAgent] = [otherAgent, currentAgent];

    const prompt: string = `Agen lain berkata: "${lastResponse}"\n\nTanggapi pernyataan atau pertanyaan mereka, lalu ajukan pertanyaan baru untuk melanjutkan diskusi tentang teknologi AI atau pemrograman.`;
    process.stdout.write(`${currentAgent.id}: `);
    lastResponse = await generateResponse(currentAgent, prompt);

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
}

process.on("SIGINT", () => {
  console.log("\nPercakapan dihentikan oleh pengguna.");
  process.exit(0);
});

conversationLoop().catch((error) => {
  console.error(
    "Kesalahan percakapan:",
    error instanceof Error ? error.message : "Kesalahan tidak diketahui"
  );
  process.exit(1);
});
