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
