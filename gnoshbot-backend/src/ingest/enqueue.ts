import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";
import { config } from "../config.js";
import type { IngestJob } from "./job.js";

export type EnqueueFn = (job: IngestJob) => Promise<void>;

let client: LambdaClient | undefined;

const lambdaClient = (): LambdaClient => {
  client ??= new LambdaClient({ region: config.awsRegion });
  return client;
};

/** Async invoke. Tests pass a stub; unset INGEST_LAMBDA_FUNCTION_NAME is a no-op (no AWS). */
export const enqueueIngestLambda: EnqueueFn = async (job) => {
  if (!config.ingestLambdaFunctionName) {
    return;
  }
  await lambdaClient().send(
    new InvokeCommand({
      FunctionName: config.ingestLambdaFunctionName,
      InvocationType: "Event",
      Payload: JSON.stringify(job),
    })
  );
};
