-- Geography column and indexes, run after the bulk import.
-- The generated column is computed from longitude and latitude while the
-- table is rewritten once. An UPDATE of every row would instead leave a dead
-- copy of each row behind (MVCC) and double the size of the table.
ALTER TABLE places ADD COLUMN geom geography(Point, 4326)
  GENERATED ALWAYS AS (ST_MakePoint(longitude, latitude)::geography) STORED;

-- GiST index for distance and bounding box queries (R-tree)
CREATE INDEX places_geom_idx ON places USING gist (geom);
-- Trigram index for fuzzy name search
CREATE INDEX places_name_trgm_idx ON places USING gin (name gin_trgm_ops);

ANALYZE places;
