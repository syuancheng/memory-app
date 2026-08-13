package db

import (
	"context"
	"encoding/json"
	"fmt"

	"memory-app/backend/internal/model"
	"memory-app/backend/internal/service"

	"github.com/jackc/pgx/v5/pgxpool"
)

const DemoUserID = "00000000-0000-0000-0000-000000000001"

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

func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, migrationSQL)
	return err
}

func EnsureDemoUser(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, email, name)
		VALUES ($1, 'demo@example.com', 'Demo User')
		ON CONFLICT (id) DO UPDATE
		SET email = EXCLUDED.email,
		    name = EXCLUDED.name,
		    updated_at = now()
	`, DemoUserID)
	if err != nil {
		return fmt.Errorf("upsert demo user: %w", err)
	}
	return nil
}

func EnsureDemoData(ctx context.Context, pool *pgxpool.Pool) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	subjects := []struct {
		Key  string
		ID   string
		Name string
	}{
		{Key: "english", ID: "00000000-0000-0000-0000-000000000201", Name: "English"},
		{Key: "interview", ID: "00000000-0000-0000-0000-000000000202", Name: "Interview"},
		{Key: "travel", ID: "00000000-0000-0000-0000-000000000203", Name: "Travel"},
	}
	subjectIDs := make(map[string]string, len(subjects))
	for _, subject := range subjects {
		var subjectID string
		err = tx.QueryRow(ctx, `
			INSERT INTO subjects (id, user_id, name, deleted_at, updated_at)
			VALUES ($1, $2, $3, NULL, now())
			ON CONFLICT (user_id, name) DO UPDATE
			SET name = EXCLUDED.name,
			    deleted_at = NULL,
			    updated_at = now()
			RETURNING id::text
		`, subject.ID, DemoUserID, subject.Name).Scan(&subjectID)
		if err != nil {
			return fmt.Errorf("ensure demo subject %q: %w", subject.Name, err)
		}
		subjectIDs[subject.Key] = subjectID
	}

	sets := []struct {
		Key        string
		ID         string
		SubjectKey string
		Name       string
	}{
		{Key: "work", ID: "00000000-0000-0000-0000-000000000301", SubjectKey: "english", Name: "Work Expression"},
		{Key: "speaking", ID: "00000000-0000-0000-0000-000000000302", SubjectKey: "english", Name: "Speaking"},
		{Key: "email", ID: "00000000-0000-0000-0000-000000000303", SubjectKey: "english", Name: "Email"},
		{Key: "behavioral", ID: "00000000-0000-0000-0000-000000000304", SubjectKey: "interview", Name: "Behavioral"},
		{Key: "system-design", ID: "00000000-0000-0000-0000-000000000305", SubjectKey: "interview", Name: "System Design"},
		{Key: "hotel", ID: "00000000-0000-0000-0000-000000000306", SubjectKey: "travel", Name: "Hotel"},
		{Key: "restaurant", ID: "00000000-0000-0000-0000-000000000307", SubjectKey: "travel", Name: "Restaurant"},
	}
	setIDs := make(map[string]string, len(sets))
	for _, set := range sets {
		var setID string
		err = tx.QueryRow(ctx, `
			INSERT INTO sets (id, user_id, subject_id, name, deleted_at, updated_at)
			VALUES ($1, $2, $3, $4, NULL, now())
			ON CONFLICT (user_id, subject_id, name) DO UPDATE
			SET subject_id = EXCLUDED.subject_id,
			    name = EXCLUDED.name,
			    deleted_at = NULL,
			    updated_at = now()
			RETURNING id::text
		`, set.ID, DemoUserID, subjectIDs[set.SubjectKey], set.Name).Scan(&setID)
		if err != nil {
			return fmt.Errorf("ensure demo set %q: %w", set.Name, err)
		}
		setIDs[set.Key] = setID
	}

	cards := []struct {
		ID             string
		SetID          string
		FrontText      string
		AnswerText     string
		GrammarPhrases []model.GrammarPhrase
	}{
		{
			ID:         "00000000-0000-0000-0000-000000000101",
			SetID:      setIDs["speaking"],
			FrontText:  "我想委婉问一下，明天之前能不能拿到？",
			AnswerText: "Any chance of getting it by tomorrow?",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "Any chance of + doing", Note: "有没有可能…… / 委婉询问可能性"},
				{Text: "by tomorrow", Note: "明天之前，强调 deadline"},
				{Text: "get it", Note: "拿到 / 收到结果、交付物"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000102",
			SetID:      setIDs["speaking"],
			FrontText:  "我不是催你，只是想确认一下进度。",
			AnswerText: "I am not trying to rush you. I just wanted to check on the progress.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "not trying to rush you", Note: "不是在催你，降低压迫感"},
				{Text: "check on the progress", Note: "确认进展"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000103",
			SetID:      setIDs["email"],
			FrontText:  "如果你方便的话，能不能今天晚些时候发我一版？",
			AnswerText: "If it is convenient, could you send me a version later today?",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "If it is convenient", Note: "如果方便的话，正式但自然"},
				{Text: "later today", Note: "今天晚些时候"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000104",
			SetID:      setIDs["work"],
			FrontText:  "我理解你的顾虑，但我们可能需要先做一个小范围尝试。",
			AnswerText: "I understand your concern, but we may need to try it on a smaller scale first.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "I understand your concern", Note: "承接对方顾虑"},
				{Text: "on a smaller scale", Note: "小范围地"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000105",
			SetID:      setIDs["behavioral"],
			FrontText:  "我通常会先澄清目标，再决定实现细节。",
			AnswerText: "I usually clarify the goal first before deciding on the implementation details.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "clarify the goal", Note: "澄清目标"},
				{Text: "implementation details", Note: "实现细节"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000106",
			SetID:      setIDs["behavioral"],
			FrontText:  "当优先级冲突时，我会把影响范围和风险讲清楚。",
			AnswerText: "When priorities conflict, I explain the impact and the risks clearly.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "priorities conflict", Note: "优先级冲突"},
				{Text: "impact and risks", Note: "影响和风险"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000107",
			SetID:      setIDs["system-design"],
			FrontText:  "我们可以先缓存热门数据，减少数据库压力。",
			AnswerText: "We can cache the most requested data first to reduce database load.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "the most requested data", Note: "请求最频繁的数据"},
				{Text: "reduce database load", Note: "降低数据库压力"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000108",
			SetID:      setIDs["system-design"],
			FrontText:  "为了保证一致性，我们需要让写入经过同一个服务。",
			AnswerText: "To keep the data consistent, writes should go through the same service.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "keep the data consistent", Note: "保持数据一致"},
				{Text: "go through the same service", Note: "经过同一个服务"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000109",
			SetID:      setIDs["hotel"],
			FrontText:  "我想确认一下，我的预订包含早餐吗？",
			AnswerText: "I would like to confirm whether breakfast is included in my booking.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "I would like to confirm whether", Note: "我想确认是否……"},
				{Text: "is included", Note: "被包含"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000110",
			SetID:      setIDs["hotel"],
			FrontText:  "可以帮我把退房时间延后一小时吗？",
			AnswerText: "Could you help me extend the checkout time by one hour?",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "extend the checkout time", Note: "延后退房时间"},
				{Text: "by one hour", Note: "延后一小时"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000111",
			SetID:      setIDs["restaurant"],
			FrontText:  "我们有预约，不过可能会晚到十分钟。",
			AnswerText: "We have a reservation, but we might be about ten minutes late.",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "have a reservation", Note: "有预约"},
				{Text: "might be about ten minutes late", Note: "可能会晚到十分钟左右"},
			},
		},
		{
			ID:         "00000000-0000-0000-0000-000000000112",
			SetID:      setIDs["restaurant"],
			FrontText:  "这道菜可以不放香菜吗？",
			AnswerText: "Could you make this dish without cilantro?",
			GrammarPhrases: []model.GrammarPhrase{
				{Text: "make this dish without", Note: "这道菜不放……"},
				{Text: "cilantro", Note: "香菜"},
			},
		},
	}

	for _, card := range cards {
		grammarJSON, err := json.Marshal(card.GrammarPhrases)
		if err != nil {
			return err
		}
		tokenJSON, err := json.Marshal(service.TokenizeAnswer(card.AnswerText, service.DirectionZhToEn))
		if err != nil {
			return err
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO cards (
				id, user_id, set_id, card_type, direction, front_text, answer_text,
				grammar_phrases, answer_tokens, deleted_at, updated_at
			) VALUES (
				$1, $2, $3, 'sentence', 'zh_to_en', $4, $5,
				$6::jsonb, $7::jsonb, NULL, now()
			)
			ON CONFLICT (id) DO UPDATE
			SET user_id = EXCLUDED.user_id,
			    set_id = EXCLUDED.set_id,
			    card_type = EXCLUDED.card_type,
			    direction = EXCLUDED.direction,
			    front_text = EXCLUDED.front_text,
			    answer_text = EXCLUDED.answer_text,
			    grammar_phrases = EXCLUDED.grammar_phrases,
			    answer_tokens = EXCLUDED.answer_tokens,
			    deleted_at = NULL,
			    updated_at = now()
		`, card.ID, DemoUserID, card.SetID, card.FrontText, card.AnswerText, string(grammarJSON), string(tokenJSON))
		if err != nil {
			return fmt.Errorf("ensure demo card %q: %w", card.ID, err)
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO review_states (
				card_id, status, ease, interval_days, due_at, review_count, lapse_count,
				last_reviewed_at, mastered_at
			) VALUES (
				$1, 'new', 2.3, 0, now(), 0, 0, NULL, NULL
			)
			ON CONFLICT (card_id) DO UPDATE
			SET status = 'new',
			    ease = 2.3,
			    interval_days = 0,
			    due_at = now(),
			    review_count = 0,
			    lapse_count = 0,
			    last_reviewed_at = NULL,
			    mastered_at = NULL
		`, card.ID)
		if err != nil {
			return fmt.Errorf("ensure demo review state %q: %w", card.ID, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit demo data: %w", err)
	}
	return nil
}

const migrationSQL = `
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  phone TEXT UNIQUE,
  name TEXT,
  display_name TEXT,
  primary_email TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS primary_email TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS subjects (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(user_id, name)
);

DO $$
BEGIN
  IF to_regclass('public.sets') IS NULL AND to_regclass('public.tags') IS NOT NULL THEN
    ALTER TABLE tags RENAME TO sets;
  END IF;
END $$;

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
DECLARE
  has_multi_set_cards BOOLEAN;
BEGIN
  IF to_regclass('public.card_tags') IS NOT NULL THEN
    EXECUTE '
      SELECT EXISTS (
        SELECT 1
        FROM card_tags
        GROUP BY card_id
        HAVING COUNT(*) > 1
      )
    ' INTO has_multi_set_cards;

    IF has_multi_set_cards THEN
      RAISE EXCEPTION 'cannot migrate card_tags: some cards belong to multiple sets';
    END IF;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS cards (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
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

ALTER TABLE cards ADD COLUMN IF NOT EXISTS set_id UUID REFERENCES sets(id);

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

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM cards
    WHERE deleted_at IS NULL AND set_id IS NULL
  ) THEN
    RAISE EXCEPTION 'cannot migrate cards: some active cards have no set';
  END IF;
END $$;

ALTER TABLE cards ALTER COLUMN set_id SET NOT NULL;
ALTER TABLE cards DROP COLUMN IF EXISTS subject_id;
DROP TABLE IF EXISTS card_tags;

CREATE TABLE IF NOT EXISTS review_states (
  card_id UUID PRIMARY KEY REFERENCES cards(id),
  status TEXT NOT NULL DEFAULT 'new',
  ease REAL NOT NULL DEFAULT 2.3,
  interval_days INTEGER NOT NULL DEFAULT 0,
  due_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  review_count INTEGER NOT NULL DEFAULT 0,
  lapse_count INTEGER NOT NULL DEFAULT 0,
  last_reviewed_at TIMESTAMPTZ,
  mastered_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS review_events (
  id UUID PRIMARY KEY,
  card_id UUID NOT NULL REFERENCES cards(id),
  user_id UUID NOT NULL REFERENCES users(id),
  mode TEXT NOT NULL,
  rating TEXT NOT NULL,
  revealed_tokens_count INTEGER,
  total_tokens_count INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
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

-- 一个人（users）可以有多种登录方式（identities）。
--
-- type 分两类：
--   可验证的联系方式 —— 'email' | 'phone'：能收验证码，能独立作为登录入口
--   第三方身份       —— 'apple' | 'wechat' | 'google'：value 存 provider 的 sub/openid
--
-- UNIQUE(type, value) 就是邮箱去重的执行点，由数据库保证而非应用逻辑。
-- 未来加手机号 = 多一个 type 取值 + 一个短信发送实现，不动表结构。
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

CREATE INDEX IF NOT EXISTS idx_identities_user ON identities (user_id);

-- 回填现有邮箱用户。Apple 用户（占位邮箱）本轮不迁移，仍走
-- account_connections 那条老路。
INSERT INTO identities (id, user_id, type, value, verified_at)
SELECT gen_random_uuid(), id, 'email', lower(email), created_at
FROM users
WHERE email IS NOT NULL
  AND email NOT LIKE '%@apple.cardly.local'
  AND deleted_at IS NULL
ON CONFLICT (type, value) DO NOTHING;

-- 身份唯一性移交 identities 后，users.email 降级为展示用主邮箱。
-- 放开 NOT NULL，无邮箱的登录方式（微信/手机号）才不必再伪造占位地址。
-- UNIQUE(email) 保留：Postgres 允许多个 NULL，因此它与可空并不冲突，
-- 留作一层额外防御。
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- 密码是可选的快捷登录方式：验证码始终可用，未设密码的账号 password_hash 为空。
-- 放在 users 而非 identities：一个人可能有多个邮箱身份，但只该有一个密码。
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_set_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS mcp_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  token_hash TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS mcp_tokens_user_idx ON mcp_tokens (user_id) WHERE revoked_at IS NULL;

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

ALTER TABLE account_connections ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE account_connections ADD COLUMN IF NOT EXISTS email_verified BOOLEAN;

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
CREATE INDEX IF NOT EXISTS idx_sets_subject_active ON sets(subject_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_cards_set_active ON cards(set_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_review_states_due ON review_states(due_at) WHERE status NOT IN ('deleted', 'mastered');
CREATE INDEX IF NOT EXISTS idx_users_email_active ON users(lower(email)) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_codes_identifier ON auth_verification_codes(identifier, purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_token_active ON auth_sessions(token_hash) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_account_connections_user ON account_connections(user_id);
`
