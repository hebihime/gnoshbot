import { app, fetch as appFetch } from "./app.js";
import { runRuntimeLoop } from "./lambda/runtime.js";

export type FunctionUrlEvent = {
  version?: string;
  rawPath?: string;
  rawQueryString?: string;
  headers?: Record<string, string | undefined>;
  cookies?: string[];
  body?: string | null;
  isBase64Encoded?: boolean;
  requestContext?: {
    domainName?: string;
    http?: { method?: string; path?: string };
  };
};

export type FunctionUrlResult = {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  isBase64Encoded: false;
};

const headerMap = (
  headers: FunctionUrlEvent["headers"],
  cookies: string[] | undefined
): Headers => {
  const out = new Headers();
  for (const [key, value] of Object.entries(headers ?? {})) {
    if (value) {
      out.set(key, value);
    }
  }
  if (cookies && cookies.length > 0 && !out.has("cookie")) {
    out.set("cookie", cookies.join("; "));
  }
  return out;
};

export const functionUrlEventToRequest = (event: FunctionUrlEvent): Request => {
  const domain = event.requestContext?.domainName ?? event.headers?.host ?? "lambda.local";
  const path = event.rawPath ?? event.requestContext?.http?.path ?? "/";
  const query = event.rawQueryString ? `?${event.rawQueryString}` : "";
  const url = `https://${domain}${path}${query}`;
  const method = event.requestContext?.http?.method ?? "GET";
  const headers = headerMap(event.headers, event.cookies);
  const init: RequestInit = { method, headers };
  if (event.body && method !== "GET" && method !== "HEAD") {
    init.body = event.isBase64Encoded
      ? Buffer.from(event.body, "base64")
      : event.body;
  }
  return new Request(url, init);
};

export const responseToFunctionUrlResult = async (
  response: Response
): Promise<FunctionUrlResult> => {
  const headers: Record<string, string> = {};
  response.headers.forEach((value, key) => {
    if (key.toLowerCase() === "set-cookie") {
      return;
    }
    headers[key] = value;
  });
  return {
    statusCode: response.status,
    headers,
    body: await response.text(),
    isBase64Encoded: false,
  };
};

export const fetch = appFetch;

/** Lambda Function URL (payload 2.0). Bun.serve remains local (`src/index.ts`). */
export const handler = async (event: unknown): Promise<FunctionUrlResult> => {
  const request = functionUrlEventToRequest(event as FunctionUrlEvent);
  const response = await app.fetch(request);
  return responseToFunctionUrlResult(response);
};

if (import.meta.main) {
  await runRuntimeLoop(handler);
}
