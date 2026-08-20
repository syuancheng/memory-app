ALTER TABLE review_states ADD COLUMN IF NOT EXISTS stability DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE review_states ADD COLUMN IF NOT EXISTS difficulty DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE review_states ADD COLUMN IF NOT EXISTS state SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE review_states ADD COLUMN IF NOT EXISTS scheduled_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE review_states ADD COLUMN IF NOT EXISTS elapsed_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE review_states ADD COLUMN IF NOT EXISTS graduated_at TIMESTAMPTZ;

-- 回填存量数据：按旧 status 换算成 FSRS 的 state；旧 status='review'/'mastered' 的卡
-- 说明肯定毕业过，graduated_at 没有精确历史时间，就近似地用 last_reviewed_at 兜底。
UPDATE review_states SET state = 0 WHERE status = 'new';
UPDATE review_states SET state = 1 WHERE status = 'learning' AND has_graduated = false;
UPDATE review_states SET state = 2 WHERE status IN ('review', 'mastered') OR has_graduated = true;
UPDATE review_states SET graduated_at = COALESCE(last_reviewed_at, now())
  WHERE state = 2 AND graduated_at IS NULL;

ALTER TABLE review_states
ADD CONSTRAINT review_states_state_check CHECK (state IN (0, 1, 2, 3));

ALTER TABLE review_states DROP COLUMN status;
ALTER TABLE review_states DROP COLUMN learning_step;
ALTER TABLE review_states DROP COLUMN ease;
ALTER TABLE review_states DROP COLUMN interval_days;
ALTER TABLE review_states DROP COLUMN IF EXISTS has_graduated;

DROP TABLE IF EXISTS daily_sessions;
