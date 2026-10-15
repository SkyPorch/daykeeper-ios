import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../openapi/customer.yaml", import.meta.url));
assert.equal(createHash("sha256").update(source).digest("hex"),
  "bc77cb02b877856d2b52ce948fcda4b3b357a7885cd5f5405c3b6394d3b96251",
  "Review the upstream contract, Swift models and provenance before updating this checksum");
const license = await readFile(new URL("../openapi/LICENSE", import.meta.url), "utf8");
assert.ok(license.includes("Apache License"));
console.log("Pinned customer contract and license verified (not a schema-conformance proof).");
