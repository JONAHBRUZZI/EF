const test = require("node:test");
const assert = require("node:assert/strict");
const app = require("../server.js");

test("GET /api/health responde 200 y status ok", async () => {
  const server = app.listen(0);
  const { port } = server.address();

  try {
    const res = await fetch(`http://localhost:${port}/api/health`);
    const body = await res.json();

    assert.equal(res.status, 200);
    assert.equal(body.status, "ok");
  } finally {
    server.close();
  }
});
