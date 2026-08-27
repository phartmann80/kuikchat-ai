#!/usr/bin/env node
// Validates every SQL migration with libpg_query (PostgreSQL's own parser).
// Also parses the bodies of `language sql` functions individually, since the
// outer parse treats function bodies as opaque strings.
//
// Usage: node tools/validate-sql.mjs <migrations-dir> [...more dirs]

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(join(process.cwd(), 'noop.js'));
const { parse } = require('libpg-query');

const dirs = process.argv.slice(2);
if (dirs.length === 0) {
  console.error('usage: node tools/validate-sql.mjs <migrations-dir>...');
  process.exit(2);
}

let failed = false;

for (const dir of dirs) {
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    const path = join(dir, file);
    const sql = readFileSync(path, 'utf8');
    try {
      const result = await parse(sql);
      const count = result.stmts ? result.stmts.length : 0;
      console.log(`OK   ${path} (${count} statements)`);
    } catch (error) {
      failed = true;
      console.error(`FAIL ${path}: ${error.message}`);
    }

    // language sql function bodies
    const fns = [
      ...sql.matchAll(
        /create or replace function (\S+)[\s\S]*?language (sql|plpgsql)[\s\S]*?as \$\$([\s\S]*?)\$\$;/g,
      ),
    ];
    for (const [, name, lang, body] of fns) {
      if (lang !== 'sql') continue; // plpgsql needs a live server (plpgsql_check)
      try {
        await parse(body);
        console.log(`OK   ${path} :: function ${name}`);
      } catch (error) {
        failed = true;
        console.error(`FAIL ${path} :: function ${name}: ${error.message}`);
      }
    }
  }
}

process.exit(failed ? 1 : 0);
