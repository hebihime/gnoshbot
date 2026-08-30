import duckdb from "duckdb";
import { config, overturePlacesGlob } from "../config.js";
import { query } from "../db.js";

export type BBox = {
  minLon: number;
  minLat: number;
  maxLon: number;
  maxLat: number;
};

export type OverturePlaceRow = {
  overture_id: string;
  name: string;
  website_url: string | null;
  phone_number: string | null;
  email_address: string | null;
  street_address: string | null;
  lon: number;
  lat: number;
};

const SETUP_SQL = `
INSTALL spatial; LOAD spatial;
INSTALL httpfs;  LOAD httpfs;
SET s3_region = 'us-west-2';
`;

const EXTRACT_SQL = `
SELECT
  id AS overture_id,
  names.primary AS name,
  websites[1] AS website_url,
  phones[1] AS phone_number,
  emails[1] AS email_address,
  addresses[1].freeform AS street_address,
  bbox.xmin AS lon,
  bbox.ymin AS lat
FROM read_parquet(?, filename = true, hive_partitioning = 1)
WHERE bbox.xmin BETWEEN ? AND ?
  AND bbox.ymin BETWEEN ? AND ?
  AND operating_status IS DISTINCT FROM 'permanently_closed'
  AND (
        list_contains(taxonomy.hierarchy, 'food_and_drink')
     OR basic_category IN ('restaurant','cafe','bar','meal_takeaway','meal_delivery','bakery','food_truck')
     OR categories.primary ILIKE '%restaurant%'
  );
`;

const UPSERT_RESTAURANT = `
INSERT INTO restaurants (
  overture_id, name, website_url, phone_number, email_address,
  street_address, coordinates, cuisine_tags, release
)
VALUES (
  $1, $2, $3, $4, $5, $6,
  ST_SetSRID(ST_MakePoint($7, $8), 4326),
  '{}',
  $9
)
ON CONFLICT (overture_id) DO UPDATE
  SET name = EXCLUDED.name,
      website_url = EXCLUDED.website_url,
      phone_number = EXCLUDED.phone_number,
      email_address = EXCLUDED.email_address,
      street_address = EXCLUDED.street_address,
      coordinates = EXCLUDED.coordinates,
      release = EXCLUDED.release
  WHERE EXISTS (
    SELECT 1
    FROM x402_capabilities c
    WHERE c.overture_id = restaurants.overture_id
      AND c.integration_status = 'UNSUPPORTED'
  );
`;

const INSERT_CAPABILITY = `
INSERT INTO x402_capabilities (overture_id, integration_status)
VALUES ($1, 'UNSUPPORTED')
ON CONFLICT (overture_id) DO NOTHING;
`;

type DuckConnection = {
  exec: (sql: string, cb: (err: Error | null) => void) => void;
  all: (
    sql: string,
    ...args: unknown[]
  ) => void;
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

const allSql = (
  connection: DuckConnection,
  sql: string,
  params: unknown[]
): Promise<OverturePlaceRow[]> =>
  new Promise((resolve, reject) => {
    connection.all(sql, ...params, (err: Error | null, rows: OverturePlaceRow[]) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(rows ?? []);
    });
  });

export const extractPlaces = async (bbox: BBox): Promise<OverturePlaceRow[]> => {
  const db = new duckdb.Database(":memory:");
  const connection = db.connect() as unknown as DuckConnection;
  try {
    await execSql(connection, SETUP_SQL);
    return await allSql(connection, EXTRACT_SQL, [
      overturePlacesGlob(),
      bbox.minLon,
      bbox.maxLon,
      bbox.minLat,
      bbox.maxLat,
    ]);
  } finally {
    connection.close();
    db.close();
  }
};

export const persistPlaces = async (rows: OverturePlaceRow[]): Promise<number> => {
  let written = 0;
  for (const row of rows) {
    await query(UPSERT_RESTAURANT, [
      row.overture_id,
      row.name,
      row.website_url,
      row.phone_number,
      row.email_address,
      row.street_address,
      row.lon,
      row.lat,
      config.overtureRelease,
    ]);
    await query(INSERT_CAPABILITY, [row.overture_id]);
    written += 1;
  }
  return written;
};

export const ingestBBox = async (bbox: BBox): Promise<number> => {
  const rows = await extractPlaces(bbox);
  return persistPlaces(rows);
};

const runCli = async (): Promise<void> => {
  const minLon = Number(process.env.MIN_LON);
  const minLat = Number(process.env.MIN_LAT);
  const maxLon = Number(process.env.MAX_LON);
  const maxLat = Number(process.env.MAX_LAT);
  if ([minLon, minLat, maxLon, maxLat].some(Number.isNaN)) {
    throw new Error("Set MIN_LON MIN_LAT MAX_LON MAX_LAT to run ingest");
  }
  const count = await ingestBBox({ minLon, minLat, maxLon, maxLat });
  process.stdout.write(`ingested ${count} places for release ${config.overtureRelease}\n`);
};

if (import.meta.main) {
  runCli().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
