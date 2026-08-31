import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../openapi/customer.yaml", import.meta.url));
assert.equal(createHash("sha256").update(source).digest("hex"),
  "b62dd386a87380f3fe94f968ff8fedf703ca6079199ea74057d32e31f91e1fec",
  "Review the upstream contract, Swift models and provenance before updating this checksum");
const license = await readFile(new URL("../openapi/LICENSE", import.meta.url), "utf8");
assert.ok(license.includes("Apache License"));
console.log("Pinned customer contract and license verified (not a schema-conformance proof).");
