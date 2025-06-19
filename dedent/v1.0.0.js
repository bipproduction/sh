function dedent(strings, ...values) {
  // Handle template literal input
  let result = '';
  for (let i = 0; i < strings.length; i++) {
    result += strings[i];
    if (i < values.length) {
      result += values[i];
    }
  }

  // Split into lines
  const lines = result.split('\n');
  
  // Remove leading and trailing empty lines
  while (lines.length && lines[0].trim() === '') lines.shift();
  while (lines.length && lines[lines.length - 1].trim() === '') lines.pop();
  
  // Find minimum indentation (ignoring empty lines)
  const indents = lines
    .filter(line => line.trim() !== '')
    .map(line => line.match(/^\s*/)[0].length);
  const minIndent = indents.length ? Math.min(...indents) : 0;
  
  // Remove minimum indentation from each line
  const dedented = lines.map(line => line.slice(minIndent));
  
  // Join lines and return
  return dedented.join('\n');
}

if (typeof window !== "undefined") {
  window.dedent = dedent;
} else if (typeof module !== "undefined" && module.exports) {
  module.exports = dedent;
} 
