type LambdaHandler = (event: unknown) => Promise<unknown>;

/**
 * Bun has no Lambda RIC. Poll the Runtime API so container images can run
 * `bun run src/lambda-http.ts` / `bun run src/ingest/worker.ts`.
 */
export const runRuntimeLoop = async (handler: LambdaHandler): Promise<void> => {
  const runtime = process.env.AWS_LAMBDA_RUNTIME_API;
  if (!runtime) {
    throw new Error("AWS_LAMBDA_RUNTIME_API is not set");
  }
  const base = `http://${runtime}/2018-06-01/runtime`;

  for (;;) {
    const next = await fetch(`${base}/invocation/next`);
    const requestId = next.headers.get("lambda-runtime-aws-request-id");
    if (!requestId) {
      throw new Error("Lambda Runtime API omitted lambda-runtime-aws-request-id");
    }
    let event: unknown = {};
    const text = await next.text();
    if (text) {
      event = JSON.parse(text) as unknown;
    }
    try {
      const result = await handler(event);
      await fetch(`${base}/invocation/${requestId}/response`, {
        method: "POST",
        body: result === undefined ? "{}" : JSON.stringify(result),
      });
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      const errorType = err instanceof Error ? err.name : "Error";
      await fetch(`${base}/invocation/${requestId}/error`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ errorMessage, errorType }),
      });
    }
  }
};
