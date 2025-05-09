import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

const envFilePath = path.resolve(process.cwd(), '.env');
const outputDir = path.resolve(process.cwd(), 'types');
const outputFile = path.join(outputDir, 'env.d.ts');

// 1. Baca .env
const envContent = fs.readFileSync(envFilePath, { encoding: 'utf-8' });
const parsed = dotenv.parse(envContent);

// 2. Generate TypeScript declare
const keys = Object.keys(parsed);

const lines = keys.map((key) => {
  return `    ${key}?: string;`;
});

const fileContent = `declare namespace NodeJS {
  interface ProcessEnv {
${lines.join('\n')}
  }
}
`;

if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

fs.writeFileSync(outputFile, fileContent, { encoding: 'utf-8' });

console.log(`✅ Env types generated at: ${outputFile}`);
