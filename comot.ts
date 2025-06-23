const comot = async (url: string) => (
  new Function("window", await (await fetch(url)).text())(globalThis),
  globalThis as any
);
