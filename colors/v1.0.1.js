const colors = {
  // Foreground colors
  black: str => `\x1b[30m${str}\x1b[0m`,
  red: str => `\x1b[31m${str}\x1b[0m`,
  green: str => `\x1b[32m${str}\x1b[0m`, // Fixed syntax error
  yellow: str => `\x1b[33m${str}\x1b[0m`,
  blue: str => `\x1b[34m${str}\x1b[0m`,
  magenta: str => `\x1b[35m${str}\x1b[0m`,
  cyan: str => `\x1b[36m${str}\x1b[0m`,
  white: str => `\x1b[37m${str}\x1b[0m`,
  gray: str => `\x1b[90m${str}\x1b[0m`,

  // Background colors
  bgBlack: str => `\x1b[40m${str}\x1b[0m`,
  bgRed: str => `\x1b[41m${str}\x1b[0m`,
  bgGreen: str => `\x1b[42m${str}\x1b[0m`,
  bgYellow: str => `\x1b[43m${str}\x1b[0m`,
  bgBlue: str => `\x1b[44m${str}\x1b[0m`,
  bgMagenta: str => `\x1b[45m${str}\x1b[0m`,
  bgCyan: str => `\x1b[46m${str}\x1b[0m`,
  bgWhite: str => `\x1b[47m${str}\x1b[0m`,

  // Text styles
  reset: str => `\x1b[0m${str}\x1b[0m`,
  bold: str => `\x1b[1m${str}\x1b[0m`,
  dim: str => `\x1b[2m${str}\x1b[0m`,
  italic: str => `\x1b[3m${str}\x1b[0m`,
  underline: str => `\x1b[4m${str}\x1b[0m`,
  inverse: str => `\x1b[7m${str}\x1b[0m`,
  hidden: str => `\x1b[8m${str}\x1b[0m`,
  strikethrough: str => `\x1b[9m${str}\x1b[0m`,

  // Additional colors (approximations or aliases)
  grey: str => `\x1b[90m${str}\x1b[0m`, // Alias for gray
  brightRed: str => `\x1b[91m${str}\x1b[0m`,
  brightGreen: str => `\x1b[92m${str}\x1b[0m`,
  brightYellow: str => `\x1b[93m${str}\x1b[0m`,
  brightBlue: str => `\x1b[94m${str}\x1b[0m`,
  brightMagenta: str => `\x1b[95m${str}\x1b[0m`,
  brightCyan: str => `\x1b[96m${str}\x1b[0m`,
  brightWhite: str => `\x1b[97m${str}\x1b[0m`
};

// Add color and style methods to String.prototype
Object.keys(colors).forEach(key => {
  Object.defineProperty(String.prototype, key, {
    configurable: true,
    enumerable: false, // Changed to false to avoid polluting for...in loops
    get: function () {
      return colors[key](this.toString());
    }
  });
});

// Export for different environments
if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
  module.exports = colors; // CommonJS (Node.js)
} else if (typeof window !== 'undefined') {
  window.colors = colors; // Browser global
}

// Support ES modules if needed
if (typeof exportDefault !== 'undefined') {
  exportDefault = colors;
}
