package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

// mcpTokenPrefix 让令牌一眼可辨来源，也便于日志里做前缀脱敏。
const mcpTokenPrefix = "mcp_"

// MCPToken 是一条个人访问令牌的元数据。**明文只在创建时返回一次**，
// 库里只存 HMAC 哈希（与 session token 同一套 hashValue）。
type MCPToken struct {
	ID         string
	Name       string
	CreatedAt  time.Time
	LastUsedAt *time.Time
}

// CreateMCPToken 为指定用户签发一条 MCP 个人访问令牌，返回明文（仅此一次）与元数据。
//
// 存在的意义：MCP 的静态 MEMORY_MCP_TOKEN 一律映射到 demo 用户，
// 无法把卡片写到真实账号。个人令牌把 token 与 user 绑定，解决归属问题。
func (s *Service) CreateMCPToken(ctx context.Context, userID string, name string) (string, MCPToken, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return "", MCPToken{}, errors.New("authenticated user is required")
	}
	raw, err := randomURLToken(32)
	if err != nil {
		return "", MCPToken{}, err
	}
	token := mcpTokenPrefix + raw

	name = strings.TrimSpace(name)
	if name == "" {
		name = "MCP client"
	}

	id := uuid.NewString()
	var meta MCPToken
	err = s.pool.QueryRow(ctx, `
		INSERT INTO mcp_tokens (id, user_id, token_hash, name)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, name, created_at, last_used_at
	`, id, userID, s.hashValue(token), name).Scan(&meta.ID, &meta.Name, &meta.CreatedAt, &meta.LastUsedAt)
	if err != nil {
		return "", MCPToken{}, err
	}
	return token, meta, nil
}

// ListMCPTokens 返回未撤销的令牌元数据（不含明文，明文已不可恢复）。
func (s *Service) ListMCPTokens(ctx context.Context, userID string) ([]MCPToken, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id::text, name, created_at, last_used_at
		FROM mcp_tokens
		WHERE user_id = $1 AND revoked_at IS NULL
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	tokens := make([]MCPToken, 0)
	for rows.Next() {
		var t MCPToken
		if err := rows.Scan(&t.ID, &t.Name, &t.CreatedAt, &t.LastUsedAt); err != nil {
			return nil, err
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

// RevokeMCPToken 撤销一条令牌；只能撤销自己的。
func (s *Service) RevokeMCPToken(ctx context.Context, userID string, tokenID string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE mcp_tokens SET revoked_at = now()
		WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
	`, tokenID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("token not found")
	}
	return nil
}

// UserIDForMCPToken 用明文令牌换取所属用户 ID，供 MCP server 的鉴权中间件调用。
// 顺带刷新 last_used_at，便于用户在 App 里看到令牌是否还在被使用。
func (s *Service) UserIDForMCPToken(ctx context.Context, token string) (string, bool) {
	token = strings.TrimSpace(token)
	if !strings.HasPrefix(token, mcpTokenPrefix) {
		return "", false
	}
	var userID string
	err := s.pool.QueryRow(ctx, `
		UPDATE mcp_tokens SET last_used_at = now()
		WHERE token_hash = $1 AND revoked_at IS NULL
		RETURNING user_id::text
	`, s.hashValue(token)).Scan(&userID)
	if err != nil {
		return "", false
	}
	return userID, true
}
