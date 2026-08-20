CREATE TABLE IF NOT EXISTS daily_check_ins (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  check_in_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, check_in_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_check_ins_user_date ON daily_check_ins(user_id, check_in_date DESC);
