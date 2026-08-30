import duckdb from "duckdb";

const SETUP_SQL = `
INSTALL spatial; LOAD spatial;
INSTALL httpfs;  LOAD httpfs;
SET s3_region = 'us-west-2';
`;

type DuckConnection = {
  exec: (sql: string, cb: (err: Error | null) => void) => void;
  close: () => void;
};

const execSql = (connection: DuckConnection, sql: string): Promise<void> =>
  new Promise((resolve, reject) => {
    connection.exec(sql, (err) => {
      if (err) {
        reject(err);
        return;
      }
      resolve();
    });
  });

const db = new duckdb.Database(":memory:");
const connection = db.connect() as unknown as DuckConnection;

try {
  await execSql(connection, SETUP_SQL);
  process.stdout.write("duckdb spatial+httpfs ok\n");
} finally {
  connection.close();
  db.close();
}
