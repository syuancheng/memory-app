ALTER TABLE review_events
ADD COLUMN IF NOT EXISTS client_review_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_review_events_user_client_review_id
ON review_events(user_id, client_review_id)
WHERE client_review_id IS NOT NULL AND client_review_id <> '';
