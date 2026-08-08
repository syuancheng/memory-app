package api

import (
	"errors"
	"net/http"
	"strings"

	authpkg "memory-app/backend/internal/auth"
)

type requestCodeRequest struct {
	Email string `json:"email"`
}

type verifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

type appleSignInRequest struct {
	IdentityToken     string `json:"identity_token"`
	AuthorizationCode string `json:"authorization_code"`
	Nonce             string `json:"nonce"`
	FullName          string `json:"full_name"`
	Email             string `json:"email"`
}

type authResponse struct {
	User         authUserResponse `json:"user"`
	SessionToken string           `json:"session_token,omitempty"`
}

type authUserResponse struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	Name     string `json:"name"`
	Provider string `json:"provider,omitempty"`
}

func (s *Server) requestAuthCode(w http.ResponseWriter, r *http.Request) {
	var req requestCodeRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.auth.RequestEmailCode(r.Context(), req.Email, authpkg.PurposeLogin); err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "sent"})
}

func (s *Server) verifyAuthCode(w http.ResponseWriter, r *http.Request) {
	var req verifyCodeRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	user, token, err := s.auth.VerifyLoginCode(r.Context(), req.Email, req.Code)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, authResponse{
		User:         toAuthUserResponse(user),
		SessionToken: token,
	})
}

func (s *Server) signInWithApple(w http.ResponseWriter, r *http.Request) {
	var req appleSignInRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	user, token, err := s.auth.SignInWithApple(r.Context(), authpkg.AppleSignInInput{
		IdentityToken:     req.IdentityToken,
		AuthorizationCode: req.AuthorizationCode,
		Nonce:             req.Nonce,
		FullName:          req.FullName,
		Email:             req.Email,
	})
	if err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, authResponse{
		User:         toAuthUserResponse(user),
		SessionToken: token,
	})
}

func (s *Server) getCurrentUser(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, authResponse{User: toAuthUserResponse(currentUser(r))})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if err := s.auth.Logout(r.Context(), bearerToken(r)); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (s *Server) requestDeleteAccountCode(w http.ResponseWriter, r *http.Request) {
	user := currentUser(r)
	if user.Provider == authpkg.AppleProvider {
		writeJSON(w, http.StatusOK, map[string]string{"status": "not_required"})
		return
	}
	if err := s.auth.RequestEmailCode(r.Context(), user.Email, authpkg.PurposeDeleteAccount); err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "sent"})
}

func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request) {
	var req verifyCodeRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	user := currentUser(r)
	if user.Provider == authpkg.AppleProvider {
		if err := s.auth.DeleteAccount(r.Context(), user.ID, ""); err != nil {
			writeAuthError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
		return
	}
	if strings.TrimSpace(req.Email) == "" {
		req.Email = user.Email
	}
	normalized, err := authpkg.NormalizeEmail(req.Email)
	if err != nil {
		writeAuthError(w, err)
		return
	}
	if !strings.EqualFold(normalized, user.Email) {
		writeError(w, http.StatusBadRequest, "email does not match current user")
		return
	}
	if err := s.auth.DeleteAccount(r.Context(), user.ID, req.Code); err != nil {
		writeAuthError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func toAuthUserResponse(user authpkg.User) authUserResponse {
	return authUserResponse{
		ID:       user.ID,
		Email:    user.Email,
		Name:     user.Name,
		Provider: user.Provider,
	}
}

func writeAuthError(w http.ResponseWriter, err error) {
	message := err.Error()
	status := http.StatusBadRequest
	if errors.Is(err, http.ErrNoCookie) {
		status = http.StatusUnauthorized
	}
	if strings.Contains(message, "not configured") {
		status = http.StatusNotImplemented
	}
	if strings.Contains(message, "unauthorized") || strings.Contains(message, "invalid session") {
		status = http.StatusUnauthorized
	}
	writeError(w, status, message)
}
