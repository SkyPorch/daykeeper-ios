import { run, withFixture } from "./fixture-runner.mjs";

await withFixture(origin => run("swift", ["test", "--jobs", "2", "--filter", "WireTests", "-Xswiftc",
  "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"], {
  env: { DAYKEEPER_TEST_ORIGIN: origin }, timeout: 180_000,
}));
