export class ApiError extends Error {
  readonly status: 400 | 404 | 409;
  readonly code: string;

  constructor(status: 400 | 404 | 409, code: string, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

export type ErrorBody = {
  error: string;
  code: string;
};

export const errorBody = (error: string, code: string): ErrorBody => ({
  error,
  code,
});

/** Client-facing 500 must never include SQL, query text, or driver internals. */
export const publicInternalError = (): ErrorBody => ({
  error: "internal error",
  code: "internal_error",
});
