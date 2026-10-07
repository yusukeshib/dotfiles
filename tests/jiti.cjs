// Reuse pi's installed TypeScript loader without downloads or cache writes.
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function createLoader(filename) {
  let jitiPath = process.env.JITI_PATH;
  if (!jitiPath) {
    const cli = process.env.PI_CLI ?? execFileSync(
      "/bin/sh", ["-c", "command -v pi"], { encoding: "utf8", timeout: 10000 },
    ).trim();
    const directory = path.dirname(fs.realpathSync(cli));
    // Homebrew's bin/pi is a shell wrapper; npm installs point at the JS CLI.
    const homebrewPackage = path.resolve(directory, "../libexec/lib/node_modules/@earendil-works/pi-coding-agent");
    jitiPath = require.resolve("jiti", { paths: [directory, homebrewPackage] });
  }
  const { createJiti } = require(jitiPath);
  return createJiti(filename, { fsCache: false, moduleCache: false });
}

module.exports = { createLoader };

if (require.main === module) {
  const vm = require("node:vm");
  const loader = createLoader(__filename);
  for (const filename of process.argv.slice(2)) {
    const code = loader.transform({ source: fs.readFileSync(filename, "utf8"), filename, ts: true });
    // Parse transformed code only. Never execute an extension during this check.
    new vm.Script(code, { filename });
  }
}
