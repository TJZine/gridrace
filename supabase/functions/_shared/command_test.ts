import { readRequest } from "./command.ts";

const headers = {
  authorization: "Bearer test-token",
  "content-type": "application/json",
};

function request(body: BodyInit, extraHeaders: HeadersInit = {}): Request {
  return new Request("http://localhost", {
    method: "POST",
    headers: { ...headers, ...extraHeaders },
    body,
  });
}

async function status(
  body: BodyInit,
  extraHeaders: HeadersInit = {},
): Promise<number> {
  const result = await readRequest(request(body, extraHeaders));
  return result.ok ? 200 : result.response.status;
}

function jsonWithByteLength(length: number): string {
  const overhead = new TextEncoder().encode('{"value":""}').byteLength;
  return JSON.stringify({ value: "a".repeat(length - overhead) });
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

Deno.test("accepts valid JSON at the 2048-byte limit without Content-Length", async () => {
  const body = jsonWithByteLength(2048);
  assertEquals(new TextEncoder().encode(body).byteLength, 2048);
  assertEquals(await status(body), 200);
});

Deno.test("rejects one byte over the request limit", async () => {
  assertEquals(await status(jsonWithByteLength(2049)), 400);
});

Deno.test("uses UTF-8 bytes rather than JavaScript string length", async () => {
  const body = JSON.stringify({ value: "é".repeat(1100) });
  assertEquals(body.length < 2048, true);
  assertEquals(new TextEncoder().encode(body).byteLength > 2048, true);
  assertEquals(await status(body), 400);
});

Deno.test("rejects malformed UTF-8 rather than repairing the request", async () => {
  const body = new Uint8Array([
    ...new TextEncoder().encode('{"value":"'),
    0xc3,
    0x28,
    ...new TextEncoder().encode('"}'),
  ]);
  assertEquals(await status(body), 400);
});

Deno.test("underreported Content-Length cannot bypass the byte limit", async () => {
  assertEquals(
    await status(jsonWithByteLength(2049), { "content-length": "10" }),
    400,
  );
});

Deno.test("cancels an oversized stream before consuming its remaining chunks", async () => {
  let pulls = 0;
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls += 1;
      if (pulls <= 10) {
        controller.enqueue(new Uint8Array(1024).fill(65));
      } else {
        controller.close();
      }
    },
    cancel() {
      cancelled = true;
    },
  });

  assertEquals(await status(stream), 400);
  assertEquals(cancelled, true);
  assertEquals(pulls < 10, true);
});

Deno.test("preserves malformed and empty JSON rejection", async () => {
  assertEquals(await status("{invalid"), 400);
  assertEquals(await status(""), 400);
});
