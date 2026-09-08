import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../openapi/customer.yaml", import.meta.url));
assert.equal(createHash("sha256").update(source).digest("hex"),
  "322158cd5fa5c54a054d701ff64a9c8b07cad477414d7df83ba5a3aa7ee06cc3",
  "Review the upstream contract, Swift models and provenance before updating this checksum");
const license = await readFile(new URL("../openapi/LICENSE", import.meta.url), "utf8");
assert.ok(license.includes("Apache License"));
console.log("Pinned customer contract and license verified (not a schema-conformance proof).");
