ALTER TABLE review_states
ADD COLUMN IF NOT EXISTS has_graduated BOOLEAN NOT NULL DEFAULT false;

-- 回填存量数据：status=review 的卡显然毕业过；status=learning 但 lapse_count>0
-- 的卡，lapse_count 只会在"曾经是 review 状态时又点了 Again"才会 +1（见 scheduler.Apply），
-- 所以这也是毕业过又忘了的信号。其余 learning/new 的卡默认 false（从没毕业过）。
UPDATE review_states
SET has_graduated = true
WHERE (status = 'review' OR lapse_count > 0) AND has_graduated = false;
