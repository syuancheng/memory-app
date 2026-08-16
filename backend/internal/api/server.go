package api

import (
	"context"
	"net/http"
	"strings"

	"memory-app/backend/internal/auth"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Server struct {
	db   *pgxpool.Pool
	auth *auth.Service
}

type currentUserKey struct{}

func NewServer(pool *pgxpool.Pool, authService *auth.Service) http.Handler {
	server := &Server{db: pool, auth: authService}
	router := chi.NewRouter()
	// Recoverer 必须在最外层：任何 handler panic（含下面 currentUserID 的
	// 断言失败）都应转成 500 并保住进程，而不是打挂整个服务。
	router.Use(middleware.Recoverer)
	router.Use(cors)

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	router.Route("/api", func(r chi.Router) {
		r.Post("/auth/request-code", server.requestAuthCode)
		r.Post("/auth/verify-code", server.verifyAuthCode)
		r.Post("/auth/apple", server.signInWithApple)
		r.Post("/auth/login-password", server.loginWithPassword)
		r.Post("/auth/password/reset-code", server.requestPasswordResetCode)
		r.Post("/auth/password/reset", server.resetPassword)

		r.Group(func(r chi.Router) {
			r.Use(server.requireAuth)
			r.Get("/auth/me", server.getCurrentUser)
			r.Post("/auth/logout", server.logout)
			r.Post("/auth/password", server.setPassword)
			r.Patch("/account", server.updateAccount)
			r.Post("/account/delete-code", server.requestDeleteAccountCode)
			r.Delete("/account", server.deleteAccount)

			r.Get("/me/summary", server.getMeSummary)
			r.Get("/learning/preferences", server.getLearningPreferences)
			r.Patch("/learning/preferences", server.updateLearningPreferences)

			// MCP 个人访问令牌：把 MCP 调用绑定到真实账号
			r.Get("/mcp/tokens", server.listMCPTokens)
			r.Post("/mcp/tokens", server.createMCPToken)
			r.Delete("/mcp/tokens/{tokenID}", server.revokeMCPToken)

			r.Get("/subjects", server.listSubjects)
			r.Get("/sets", server.listAllSets)
			r.Post("/subjects", server.createSubject)
			r.Put("/subjects/{subjectID}", server.updateSubject)
			r.Delete("/subjects/{subjectID}", server.deleteSubject)
			r.Get("/subjects/{subjectID}/sets", server.listSets)
			r.Post("/subjects/{subjectID}/sets", server.createSet)
			r.Put("/subjects/{subjectID}/sets/{setID}", server.updateSet)
			r.Delete("/subjects/{subjectID}/sets/{setID}", server.deleteSet)

			r.Get("/cards", server.listCards)
			r.Post("/cards", server.createCard)
			r.Get("/cards/{cardID}", server.getCard)
			r.Get("/cards/{cardID}/review-preview", server.getReviewPreview)
			r.Put("/cards/{cardID}", server.updateCard)
			r.Delete("/cards/{cardID}", server.deleteCard)
			r.Post("/cards/{cardID}/master", server.masterCard)

			r.Get("/review/due", server.listDueCards)
			r.Get("/review/session", server.getReviewSession)
			r.Post("/review/result", server.submitReviewResult)
		})
	})

	return router
}

func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.auth == nil {
			writeError(w, http.StatusUnauthorized, "authentication is not configured")
			return
		}
		token := auth.ExtractBearer(r.Header.Get("Authorization"))
		user, err := s.auth.ValidateSession(r.Context(), token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		ctx := context.WithValue(r.Context(), currentUserKey{}, user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func currentUser(r *http.Request) auth.User {
	user, _ := r.Context().Value(currentUserKey{}).(auth.User)
	return user
}

// currentUserID 返回当前登录用户 ID。
//
// 空 ID 意味着某条数据路由漏挂了 requireAuth 中间件 —— 那会让后续查询失去
// 租户过滤。目前是靠 user_id 列的 UUID 类型让空串在数据库层报错（fail-closed），
// 属于运气而非设计，所以这里显式 panic：宁可 500 并留下堆栈，也不要让一个
// 无过滤的查询有机会执行。panic 会被 chi 的 Recoverer 中间件兜住。
func currentUserID(r *http.Request) string {
	id := currentUser(r).ID
	if id == "" {
		panic("currentUserID called without requireAuth middleware")
	}
	return id
}

func bearerToken(r *http.Request) string {
	return strings.TrimSpace(auth.ExtractBearer(r.Header.Get("Authorization")))
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
