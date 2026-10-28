-- SCATE Community Forum Schema
-- Postgres + PostGIS
-- Run after enabling PostGIS: CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS geo_bubbles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL,
  name text,
  polygon geography(polygon, 4326),
  center geography(point, 4326),
  radius_meters integer,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL,
  bubble_id uuid REFERENCES geo_bubbles(id),
  title text NOT NULL,
  description text,
  geo geography(point, 4326),
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS topics_geo_idx ON topics USING gist (geo);
CREATE INDEX IF NOT EXISTS topics_bubble_idx ON topics (bubble_id);

CREATE TABLE IF NOT EXISTS comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  body text NOT NULL,
  is_anonymous boolean DEFAULT false,
  display_name text,
  parent_id uuid REFERENCES comments(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS comments_topic_idx ON comments (topic_id);

CREATE TABLE IF NOT EXISTS comment_votes (
  comment_id uuid NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  vote smallint NOT NULL CHECK (vote IN (-1, 1)),
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);

CREATE TABLE IF NOT EXISTS comment_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id uuid REFERENCES comments(id),
  reporter_id uuid,
  reason text,
  created_at timestamptz DEFAULT now()
);
