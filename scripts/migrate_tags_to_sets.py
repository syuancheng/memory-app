#!/usr/bin/env python3
"""One-time migration from the old tags/card_tags schema to sets/cards.set_id.

Usage:
  DATABASE_URL=postgres://... scripts/migrate_tags_to_sets.py
  DATABASE_URL=postgres://... scripts/migrate_tags_to_sets.py --apply

The default mode only reports whether the migration can run. The apply mode
updates the schema in one transaction and drops the old tags/card_tags tables.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from textwrap import dedent


CHECK_SQL = r"""
SELECT
  to_regclass('public.tags') AS old_tags_table,
  to_regclass('public.card_tags') AS old_card_tags_table,
  to_regclass('public.sets') AS sets_table,
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cards'
      AND column_name = 'set_id'
  ) AS cards_has_set_id;

DO $$
DECLARE
  multi_count INTEGER := 0;
BEGIN
  IF to_regclass('public.card_tags') IS NOT NULL THEN
    EXECUTE '
      SELECT COUNT(*)
      FROM (
        SELECT card_id
        FROM card_tags
        GROUP BY card_id
        HAVING COUNT(*) > 1
      ) multi
    ' INTO multi_count;
  END IF;

  IF multi_count > 0 THEN
    RAISE EXCEPTION 'cannot migrate: % cards belong to multiple sets', multi_count;
  END IF;
END $$;
"""


MIGRATION_SQL = r"""
BEGIN;

CREATE TABLE IF NOT EXISTS sets (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  subject_id UUID NOT NULL REFERENCES subjects(id),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(user_id, subject_id, name)
);

DO $$
BEGIN
  IF to_regclass('public.tags') IS NOT NULL THEN
    EXECUTE '
      INSERT INTO sets (
        id, user_id, subject_id, name, created_at, updated_at, deleted_at
      )
      SELECT id, user_id, subject_id, name, created_at, updated_at, deleted_at
      FROM tags
      ON CONFLICT (id) DO UPDATE
      SET user_id = EXCLUDED.user_id,
          subject_id = EXCLUDED.subject_id,
          name = EXCLUDED.name,
          created_at = EXCLUDED.created_at,
          updated_at = EXCLUDED.updated_at,
          deleted_at = EXCLUDED.deleted_at
    ';
  END IF;
END $$;

DO $$
DECLARE
  multi_count INTEGER := 0;
BEGIN
  IF to_regclass('public.card_tags') IS NOT NULL THEN
    EXECUTE '
      SELECT COUNT(*)
      FROM (
        SELECT card_id
        FROM card_tags
        GROUP BY card_id
        HAVING COUNT(*) > 1
      ) multi
    ' INTO multi_count;
  END IF;

  IF multi_count > 0 THEN
    RAISE EXCEPTION 'cannot migrate: % cards belong to multiple sets', multi_count;
  END IF;
END $$;

ALTER TABLE cards ADD COLUMN IF NOT EXISTS set_id UUID REFERENCES sets(id);
ALTER TABLE cards ADD COLUMN IF NOT EXISTS subject_id UUID REFERENCES subjects(id);

DO $$
BEGIN
  IF to_regclass('public.card_tags') IS NOT NULL THEN
    EXECUTE '
      UPDATE cards c
      SET set_id = ct.tag_id
      FROM card_tags ct
      WHERE c.id = ct.card_id
        AND c.set_id IS NULL
    ';
  END IF;
END $$;

UPDATE cards c
SET subject_id = st.subject_id
FROM sets st
WHERE c.set_id = st.id
  AND c.subject_id IS NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM cards
    WHERE deleted_at IS NULL
      AND set_id IS NULL
  ) THEN
    RAISE EXCEPTION 'cannot migrate: some active cards have no set';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cards c
    LEFT JOIN sets st ON st.id = c.set_id
    WHERE c.deleted_at IS NULL
      AND (c.subject_id IS NULL OR st.subject_id IS DISTINCT FROM c.subject_id)
  ) THEN
    RAISE EXCEPTION 'cannot migrate: some active cards have inconsistent subject/set';
  END IF;
END $$;

ALTER TABLE cards ALTER COLUMN set_id SET NOT NULL;
ALTER TABLE cards ALTER COLUMN subject_id SET NOT NULL;
DROP TABLE IF EXISTS card_tags;
DROP TABLE IF EXISTS tags;

CREATE INDEX IF NOT EXISTS idx_sets_subject_active
  ON sets(subject_id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_cards_set_active
  ON cards(set_id)
  WHERE deleted_at IS NULL;

COMMIT;
"""


def run_psql(database_url: str, sql: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as handle:
        handle.write(sql)
        path = handle.name

    try:
        subprocess.run(
            ["psql", database_url, "-v", "ON_ERROR_STOP=1", "-P", "pager=off", "-f", path],
            check=True,
        )
    finally:
        os.unlink(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="apply the migration")
    args = parser.parse_args()

    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        print("DATABASE_URL is required", file=sys.stderr)
        return 2

    if args.apply:
        run_psql(database_url, MIGRATION_SQL)
        print("migration applied")
    else:
        run_psql(database_url, CHECK_SQL)
        print(dedent("""
        preflight passed
        rerun with --apply to migrate and drop old tags/card_tags tables
        """).strip())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
