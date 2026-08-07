package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Server struct {
	db *pgxpool.Pool
}

func NewServer(pool *pgxpool.Pool) http.Handler {
	server := &Server{db: pool}
	router := chi.NewRouter()
	router.Use(cors)

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	router.Route("/api", func(r chi.Router) {
		r.Get("/me/summary", server.getMeSummary)

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

	return router
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
