import { expect, test } from "bun:test";
import { PINNED_OVERTURE_RELEASE, overturePlacesGlob } from "../config.js";
import { EXTRACT_SQL, SETUP_SQL } from "./overture.js";

test("extract SQL pins us-west-2, literal bbox predicates, dual-read categories, and drops permanently_closed", () => {
  expect(SETUP_SQL).toContain("SET s3_region = 'us-west-2'");
  const xmin = EXTRACT_SQL.indexOf("bbox.xmin BETWEEN");
  const ymin = EXTRACT_SQL.indexOf("bbox.ymin BETWEEN");
  const st = EXTRACT_SQL.indexOf("ST_Intersects");
  expect(xmin).toBeGreaterThan(-1);
  expect(ymin).toBeGreaterThan(-1);
  expect(xmin).toBeLessThan(ymin);
  if (st !== -1) {
    expect(xmin).toBeLessThan(st);
  }
  expect(EXTRACT_SQL).toContain("list_contains(taxonomy.hierarchy, 'food_and_drink')");
  expect(EXTRACT_SQL).toContain("categories.primary");
  expect(EXTRACT_SQL).not.toContain("categories.main");
  expect(EXTRACT_SQL).toContain("operating_status IS DISTINCT FROM 'permanently_closed'");
  expect(EXTRACT_SQL).toContain("read_parquet(?, filename = true, hive_partitioning = 1)");
});

test("places glob is release-pinned from config, not a planet scan", () => {
  const glob = overturePlacesGlob();
  expect(glob).toBe(
    `s3://overturemaps-us-west-2/release/${PINNED_OVERTURE_RELEASE}/theme=places/type=place/*`
  );
  expect(glob).not.toContain("release/*/");
});
