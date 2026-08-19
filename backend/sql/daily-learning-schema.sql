ALTER TABLE review_states
ADD COLUMN IF NOT EXISTS learning_step INTEGER NOT NULL DEFAULT 0;

ALTER TABLE review_states
ADD COLUMN IF NOT EXISTS has_graduated BOOLEAN NOT NULL DEFAULT false;

UPDATE review_states
SET has_graduated = true
WHERE (status = 'review' OR lapse_count > 0) AND has_graduated = false;

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

CREATE TABLE IF NOT EXISTS daily_sessions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  session_date DATE NOT NULL,
  session_mode TEXT NOT NULL DEFAULT 'review',
  scope_key TEXT NOT NULL DEFAULT '',
  subject_id UUID,
  set_ids JSONB NOT NULL DEFAULT '[]',
  initial_total_count INTEGER NOT NULL DEFAULT 0,
  active_queue_card_ids JSONB NOT NULL DEFAULT '[]',
  completed_card_ids JSONB NOT NULL DEFAULT '[]',
  leeched_card_ids JSONB NOT NULL DEFAULT '[]',
  card_retry_counts JSONB NOT NULL DEFAULT '{}',
  is_check_in_completed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, session_date, scope_key)
);

ALTER TABLE daily_sessions
ADD COLUMN IF NOT EXISTS session_mode TEXT NOT NULL DEFAULT 'review';

CREATE INDEX IF NOT EXISTS idx_learning_preferences_user ON learning_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_sessions_user_date ON daily_sessions(user_id, session_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_sessions_user_scope_date ON daily_sessions(user_id, scope_key, session_date DESC);
