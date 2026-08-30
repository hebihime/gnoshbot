export const MARK_READY = `
UPDATE region_tiles
SET status = 'ready',
    restaurant_count = $3,
    ready_at = now(),
    error = NULL
WHERE geohash5 = $1 AND release = $2
`;

export const MARK_FAILED = `
UPDATE region_tiles
SET status = 'failed', error = $3
WHERE geohash5 = $1 AND release = $2
`;
