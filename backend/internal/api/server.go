package api

import (
	"context"
	"net/http"
	"strings"

	"memory-app/backend/internal/auth"

	"github.com/go-chi/chi/v5"
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
	router.Use(cors)

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	router.Route("/api", func(r chi.Router) {
		r.Post("/auth/request-code", server.requestAuthCode)
		r.Post("/auth/verify-code", server.verifyAuthCode)
		r.Post("/auth/apple", server.signInWithApple)

		r.Group(func(r chi.Router) {
			r.Use(server.requireAuth)
			r.Get("/auth/me", server.getCurrentUser)
			r.Post("/auth/logout", server.logout)
			r.Post("/account/delete-code", server.requestDeleteAccountCode)
			r.Delete("/account", server.deleteAccount)

			r.Get("/me/summary", server.getMeSummary)

			// MCP 个人访问令牌：把 MCP 调用绑定到真实账号
			r.Get("/mcp/tokens", server.listMCPTokens)
			r.Post("/mcp/tokens", server.createMCPToken)
			r.Delete("/mcp/tokens/{tokenID}", server.revokeMCPToken)

			r.Get("/subjects", server.listSubjects)
			r.Post("/subjects", server.createSubject)
			r.Put("/subjects/{subjectID}", server.updateSubject)
			r.Delete("/subjects/{subjectID}", server.deleteSubject)
			r.Get("/subjects/{subjectID}/tags", server.listTags)
			r.Post("/subjects/{subjectID}/tags", server.createTag)
			r.Put("/subjects/{subjectID}/tags/{tagID}", server.updateTag)
			r.Delete("/subjects/{subjectID}/tags/{tagID}", server.deleteTag)

			r.Get("/cards", server.listCards)
			r.Post("/cards", server.createCard)
			r.Get("/cards/{cardID}", server.getCard)
			r.Get("/cards/{cardID}/review-preview", server.getReviewPreview)
			r.Put("/cards/{cardID}", server.updateCard)
			r.Delete("/cards/{cardID}", server.deleteCard)
			r.Post("/cards/{cardID}/master", server.masterCard)

			r.Get("/review/due", server.listDueCards)
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

func currentUserID(r *http.Request) string {
	return currentUser(r).ID
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
