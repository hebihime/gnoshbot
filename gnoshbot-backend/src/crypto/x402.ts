import { encodeAbiParameters, keccak256, parseAbiParameters, type Hex } from "viem";

/** USDC on Base mainnet — shop host pin (ARCHITECTURE.md §5.1). */
export const USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as const;
export const USDC_BASE_SEPOLIA = "0x036CbD53842c5426634e7929541eC2318f3dCF7e" as const;

export type X402V1Accepts = {
  scheme: "exact";
  network: string;
  maxAmountRequired: string;
  resource: string;
  payTo: Hex;
  asset: Hex;
  extra?: { name: string; version: string };
};

export type TransferWithAuthorization = {
  from: Hex;
  to: Hex;
  value: bigint;
  validAfter: bigint;
  validBefore: bigint;
  nonce: Hex;
};

/** Shop host is x402 v1: JSON 402 body + client header `X-PAYMENT` (GROK.md T28). */
export const encodeX402V1PaymentHeader = (args: {
  network: string;
  signature: Hex;
  authorization: TransferWithAuthorization;
}): string => {
  const json = JSON.stringify({
    x402Version: 1,
    scheme: "exact",
    network: args.network,
    payload: {
      signature: args.signature,
      authorization: {
        from: args.authorization.from,
        to: args.authorization.to,
        value: args.authorization.value.toString(),
        validAfter: args.authorization.validAfter.toString(),
        validBefore: args.authorization.validBefore.toString(),
        nonce: args.authorization.nonce,
      },
    },
  });
  return Buffer.from(json, "utf8").toString("base64");
};

export const assertPayToMatchesSnapshot = (
  accepts: X402V1Accepts,
  placePayTo: Hex
): void => {
  if (accepts.payTo.toLowerCase() !== placePayTo.toLowerCase()) {
    throw new Error("payTo on accepts[] does not match place snapshot");
  }
};

export const centsToUsdcAtomic = (cents: bigint): bigint => cents * 10_000n;

export const transferWithAuthorizationHash = (
  authorization: TransferWithAuthorization
): Hex =>
  keccak256(
    encodeAbiParameters(
      parseAbiParameters(
        "address from, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce"
      ),
      [
        authorization.from,
        authorization.to,
        authorization.value,
        authorization.validAfter,
        authorization.validBefore,
        authorization.nonce,
      ]
    )
  );
