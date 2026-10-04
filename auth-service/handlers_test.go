package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthHandler(t *testing.T) {
	app := &App{}
	rec := httptest.NewRecorder()

	app.healthHandler(rec, httptest.NewRequest(http.MethodGet, "/health", nil))

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, esperado 200", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"status":"ok"`) {
		t.Errorf("corpo inesperado: %s", rec.Body.String())
	}
}

func TestMasterKeyAuthMiddleware(t *testing.T) {
	app := &App{MasterKey: "chave-mestra"}
	protected := app.masterKeyAuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	tests := []struct {
		name   string
		header string
		want   int
	}{
		{"sem header", "", http.StatusForbidden},
		{"chave errada", "Bearer outra-chave", http.StatusForbidden},
		{"chave correta", "Bearer chave-mestra", http.StatusOK},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/admin/keys", nil)
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}
			rec := httptest.NewRecorder()

			protected.ServeHTTP(rec, req)

			if rec.Code != tt.want {
				t.Errorf("status = %d, esperado %d", rec.Code, tt.want)
			}
		})
	}
}

func TestCreateKeyHandlerRejectsInvalidRequests(t *testing.T) {
	app := &App{}

	tests := []struct {
		name   string
		method string
		body   string
		want   int
	}{
		{"método não permitido", http.MethodGet, "", http.StatusMethodNotAllowed},
		{"JSON inválido", http.MethodPost, "{", http.StatusBadRequest},
		{"sem o campo name", http.MethodPost, `{}`, http.StatusBadRequest},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, "/admin/keys", strings.NewReader(tt.body))
			rec := httptest.NewRecorder()

			app.createKeyHandler(rec, req)

			if rec.Code != tt.want {
				t.Errorf("status = %d, esperado %d", rec.Code, tt.want)
			}
		})
	}
}
