import { createCipheriv, createDecipheriv, createHmac, randomBytes } from "node:crypto";
import { config } from "../config.js";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;

const wrapKey = (): Buffer => {
  const key = Buffer.from(config.menuWrapKeyHex, "hex");
  if (key.length !== 32) {
    throw new Error("MENU_WRAP_KEY_HEX must be 32 bytes (64 hex chars)");
  }
  return key;
};

export type EncryptedMenuSchema = {
  ciphertext: Buffer;
  nonce: Buffer;
  wrappedKey: Buffer;
  sha256: string;
};

export const encryptMenuSchemaJson = (plainUtf8: string): EncryptedMenuSchema => {
  const key = wrapKey();
  const nonce = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, key, nonce);
  const ciphertext = Buffer.concat([
    cipher.update(plainUtf8, "utf8"),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
  const sha256 = createHmac("sha256", key).update(plainUtf8, "utf8").digest("hex");
  return {
    ciphertext,
    nonce,
    wrappedKey: Buffer.from("menu-wrap-key-v1", "utf8"),
    sha256,
  };
};

export const decryptMenuSchemaJson = (
  ciphertext: Buffer,
  nonce: Buffer,
  wrappedKey: Buffer
): string => {
  if (nonce.length !== IV_LENGTH) {
    throw new Error("menu schema nonce must be 12 bytes");
  }
  const tag = ciphertext.subarray(ciphertext.length - 16);
  const body = ciphertext.subarray(0, ciphertext.length - 16);
  const decipher = createDecipheriv(ALGORITHM, wrappedKey, nonce);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body), decipher.final()]).toString("utf8");
};

export const hmacUserId = (userId: string): Buffer =>
  createHmac("sha256", config.skipLogHmacSecret).update(userId, "utf8").digest();
