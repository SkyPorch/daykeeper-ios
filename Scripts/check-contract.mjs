import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../openapi/customer.yaml", import.meta.url));
assert.equal(createHash("sha256").update(source).digest("hex"),
  "6a72fea574acd85dfb678b3b63c927bb3ea6506814baa6f0e774842947c64b83",
  "Review the upstream contract, Swift models and provenance before updating this checksum");
const license = await readFile(new URL("../openapi/LICENSE", import.meta.url), "utf8");
assert.ok(license.includes("Apache License"));
console.log("Pinned customer contract and license verified (not a schema-conformance proof).");
