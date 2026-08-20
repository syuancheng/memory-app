package db

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Open(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}

func SetupTestSchema(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, testSchemaSQL)
	return err
}

const testSchemaSQL = `
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE,
  phone TEXT UNIQUE,
  name TEXT,
  display_name TEXT,
  primary_email TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  password_hash TEXT,
  password_set_at TIMESTAMPTZ,
  failed_login_count INTEGER NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS subjects (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(user_id, name)
);

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

CREATE TABLE IF NOT EXISTS cards (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  subject_id UUID NOT NULL REFERENCES subjects(id),
  set_id UUID NOT NULL REFERENCES sets(id),
  card_type TEXT NOT NULL DEFAULT 'sentence',
  direction TEXT NOT NULL DEFAULT 'zh_to_en',
  front_text TEXT NOT NULL,
  answer_text TEXT NOT NULL,
  grammar_phrases JSONB NOT NULL DEFAULT '[]',
  answer_tokens JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS review_states (
  card_id UUID PRIMARY KEY REFERENCES cards(id),
  state SMALLINT NOT NULL DEFAULT 0 CHECK (state IN (0, 1, 2, 3)), -- 0=New/1=Learning/2=Review/3=Relearning (fsrs.State)
  stability DOUBLE PRECISION NOT NULL DEFAULT 0,
  difficulty DOUBLE PRECISION NOT NULL DEFAULT 0,
  due_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  scheduled_days INTEGER NOT NULL DEFAULT 0,
  elapsed_days INTEGER NOT NULL DEFAULT 0,
  review_count INTEGER NOT NULL DEFAULT 0,
  lapse_count INTEGER NOT NULL DEFAULT 0,
  last_reviewed_at TIMESTAMPTZ,
  graduated_at TIMESTAMPTZ,
  mastered_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS review_events (
  id UUID PRIMARY KEY,
  card_id UUID NOT NULL REFERENCES cards(id),
  user_id UUID NOT NULL REFERENCES users(id),
  client_review_id TEXT,
  mode TEXT NOT NULL,
  rating TEXT NOT NULL,
  revealed_tokens_count INTEGER,
  total_tokens_count INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE review_events
ADD COLUMN IF NOT EXISTS client_review_id TEXT;

CREATE TABLE IF NOT EXISTS learning_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  limit_mode TEXT NOT NULL DEFAULT 'new_plus_review',
  new_cards_per_day INTEGER NOT NULL DEFAULT 20,
  total_cards_per_day INTEGER NOT NULL DEFAULT 30,
  daily_reminder_enabled BOOLEAN NOT NULL DEFAULT false,
  daily_reminder_time TEXT NOT NULL DEFAULT '20:00',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_verification_codes (
  id UUID PRIMARY KEY,
  identifier_type TEXT NOT NULL,
  identifier TEXT NOT NULL,
  purpose TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_sessions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  token_hash TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS identities (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (type, value)
);

CREATE TABLE IF NOT EXISTS mcp_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  token_hash TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS account_connections (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  provider TEXT NOT NULL,
  provider_user_id TEXT,
  email TEXT,
  email_verified BOOLEAN,
  display_name TEXT,
  connected_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, provider),
  UNIQUE(provider, provider_user_id)
);

CREATE TABLE IF NOT EXISTS auth_provider_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  provider TEXT NOT NULL,
  provider_user_id TEXT NOT NULL,
  client_id TEXT NOT NULL,
  refresh_token_ciphertext TEXT,
  access_token_ciphertext TEXT,
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_user_id, client_id)
);

CREATE INDEX IF NOT EXISTS idx_subjects_user_active ON subjects(user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_subjects_user_name_active ON subjects(user_id, name) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sets_subject_active ON sets(subject_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sets_user_name_active ON sets(user_id, name) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sets_user_subject_name_active ON sets(user_id, subject_id, name) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_cards_set_active ON cards(set_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_cards_user_set_active ON cards(user_id, set_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_cards_user_subject_active ON cards(user_id, subject_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_review_states_due ON review_states(due_at) WHERE mastered_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_review_states_active_due_card ON review_states(due_at, card_id) WHERE mastered_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_learning_preferences_user ON learning_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_review_events_user_created_at ON review_events(user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_review_events_user_client_review_id
  ON review_events(user_id, client_review_id)
  WHERE client_review_id IS NOT NULL AND client_review_id <> '';
CREATE INDEX IF NOT EXISTS idx_users_email_active ON users(lower(email)) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_codes_identifier ON auth_verification_codes(identifier, purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_codes_active_lookup ON auth_verification_codes(identifier_type, identifier, purpose, created_at DESC) WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_sessions_token_active ON auth_sessions(token_hash) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_identities_user ON identities(user_id);
CREATE INDEX IF NOT EXISTS mcp_tokens_user_idx ON mcp_tokens(user_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_mcp_tokens_user_created_active ON mcp_tokens(user_id, created_at DESC) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_account_connections_user ON account_connections(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_provider_tokens_user_active ON auth_provider_tokens(user_id) WHERE revoked_at IS NULL;
`
