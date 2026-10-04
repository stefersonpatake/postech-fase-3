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

func TestEvaluationHandlerRequiresParameters(t *testing.T) {
	app := &App{}

	for _, url := range []string{"/evaluate", "/evaluate?user_id=u1", "/evaluate?flag_name=f1"} {
		rec := httptest.NewRecorder()

		app.evaluationHandler(rec, httptest.NewRequest(http.MethodGet, url, nil))

		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, esperado 400", url, rec.Code)
		}
	}
}

func TestEvaluationHandlerRejectsUnsafeFlagNames(t *testing.T) {
	app := &App{}

	for _, name := range []string{"../admin", "a/b", "flag%2F..%2Fadmin", "flag?x=1", ".oculta", strings.Repeat("a", 101)} {
		req := httptest.NewRequest(http.MethodGet, "/evaluate", nil)
		query := req.URL.Query()
		query.Set("user_id", "u1")
		query.Set("flag_name", name)
		req.URL.RawQuery = query.Encode()
		rec := httptest.NewRecorder()

		app.evaluationHandler(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("flag_name %q: status = %d, esperado 400", name, rec.Code)
		}
	}
}

func TestValidFlagName(t *testing.T) {
	for _, name := range []string{"enable-new-dashboard", "smoke-test-1791124439", "Flag_1.v2"} {
		if !validFlagName.MatchString(name) {
			t.Errorf("%q deveria ser um nome válido", name)
		}
	}
}
