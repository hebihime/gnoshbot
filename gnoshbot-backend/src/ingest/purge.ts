import { pool, query } from "../db.js";

export const runPurge = async (): Promise<void> => {
  await query("SELECT purge_stale_unsupported_pois()");
};

if (import.meta.main) {
  runPurge()
    .then(() => pool.end())
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
