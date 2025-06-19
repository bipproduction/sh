const colors = {
  // Foreground colors
  black: str => `\x1B[30m${str}\x1B[0m`,
  red: str => `\x1B[31m${str}\x1B[0m`,
  green: str => `\x1B[32m${str}\x1B[0m`,
  yellow: str => `\x1B[33m${str}\x1B[0m`,
  blue: str => `\x1B[34m${str}\x1B[0m`,
  magenta: str => `\x1B[35m${str}\x1B[0m`,
  cyan: str => `\x1B[36m${str}\x1B[0m`,
  white: str => `\x1B[37m${str}\x1B[0m`,
  gray: str => `\x1B[90m${str}\x1B[0m`,

  // Background colors
  bgBlack: str => `\x1B[40m${str}\x1B[0m`,
  bgRed: str => `\x1B[41m${str}\x1B[0m`,
  bgGreen: str => `\x1B[42m${str}\x1B[0m`,
  bgYellow: str => `\x1B[43m${str}\x1B[0m`,
  bgBlue: str => `\x1B[44m${str}\x1B[0m`,
  bgMagenta: str => `\x1B[45m${str}\x1B[0m`,
  bgCyan: str => `\x1B[46m${str}\x1B[0m`,
  bgWhite: str => `\x1B[47m${str}\x1B[0m`,

  // Text styles
  reset: str => `\x1B[0m${str}\x1B[0m`,
  bold: str => `\x1B[1m${str}\x1B[0m`,
  dim: str => `\x1B[2m${str}\x1B[0m`,
  italic: str => `\x1B[3m${str}\x1B[0m`,
  underline: str => `\x1B[4m${str}\x1B[0m`,
  inverse: str => `\x1B[7m${str}\x1B[0m`,
  hidden: str => `\x1B[8m${str}\x1B[0m`,
  strikethrough: str => `\x1B[9m${str}\x1B[0m`,

  // Additional colors (approximations or aliases)
  grey: str => `\x1B[90m${str}\x1B[0m`, // Alias for gray
  brightRed: str => `\x1B[91m${str}\x1B[0m`,
  brightGreen: str => `\x1B[92m${str}\x1B[0m`,
  brightYellow: str => `\x1B[93m${str}\x1B[0m`,
  brightBlue: str => `\x1B[94m${str}\x1B[0m`,
  brightMagenta: str => `\x1B[95m${str}\x1B[0m`,
  brightCyan: str => `\x1B[96m${str}\x1B[0m`,
  brightWhite: str => `\x1B[97m${str}\x1B[0m`
};

if (typeof window !== "undefined") {
  window.colors = colors;
} else if (typeof module !== "undefined" && module.exports) {
  module.exports = colors;
} 
