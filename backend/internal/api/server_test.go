package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const uid = "d2717c73-3a3a-4a24-9a10-8053a7e5d771"

func setup(t *testing.T) (http.Handler, *int) {
	t.Helper()
	calls := 0
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/auth/v1/user" {
			if r.Header.Get("Authorization") != "Bearer valid-user-token" {
				w.WriteHeader(401)
				return
			}
			_, _ = w.Write([]byte(`{"id":"` + uid + `"}`))
			return
		}
		calls++
		if r.Header.Get("Authorization") != "Bearer valid-user-token" || r.Header.Get("apikey") != "public-key" {
			t.Error("user credentials must be forwarded")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[]`))
	}))
	t.Cleanup(up.Close)
	return New(Config{SupabaseURL: up.URL, PublishableKey: "public-key", Origins: []string{"https://ninho.example"}}), &calls
}
func request(h http.Handler, method, path, body, token, origin string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	if token != "" {
		r.Header.Set("Authorization", token)
	}
	r.Header.Set("Origin", origin)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}
func TestRejectUnauthenticated(t *testing.T) {
	h, c := setup(t)
	w := request(h, "GET", "/v1/data/households", "", "", "")
	if w.Code != 401 || *c != 0 {
		t.Fatalf("unauthenticated read: %d", w.Code)
	}
}
func TestRejectBadToken(t *testing.T) {
	h, c := setup(t)
	w := request(h, "GET", "/v1/data/households", "", "Bearer forged-token-long", "")
	if w.Code != 401 || *c != 0 {
		t.Fatalf("forged token: %d", w.Code)
	}
}
func TestTenantRead(t *testing.T) {
	h, c := setup(t)
	w := request(h, "GET", "/v1/data/entries?household_id="+uid, "", "Bearer valid-user-token", "")
	if w.Code != 200 || *c != 1 {
		t.Fatalf("read: %d %s", w.Code, w.Body)
	}
}
func TestInputBoundaries(t *testing.T) {
	for _, tc := range []struct {
		path, body string
		status     int
	}{{"/v1/data/entries", `{"household_id":"` + uid + `","created_by":"attacker"}`, 400}, {"/v1/data/entries", `{"household_id":"invalid","title":"Conta"}`, 400}, {"/v1/data/entries", `{"household_id":"` + uid + `"} {}`, 400}, {"/v1/rpc/arbitrary_sql", `{"sql":"DROP TABLE"}`, 404}, {"/v1/data/households", `{"name":"x"}`, 405}} {
		h, c := setup(t)
		w := request(h, "POST", tc.path, tc.body, "Bearer valid-user-token", "")
		if w.Code != tc.status || *c != 0 {
			t.Errorf("%s: %d", tc.path, w.Code)
		}
	}
}
func TestCors(t *testing.T) {
	h, c := setup(t)
	w := request(h, "GET", "/v1/data/households", "", "Bearer valid-user-token", "https://attacker.example")
	if w.Code != 403 || *c != 0 {
		t.Fatal("untrusted origin accepted")
	}
	w = request(h, "OPTIONS", "/v1/data/entries", "", "", "https://ninho.example")
	if w.Code != 204 || w.Header().Get("Access-Control-Allow-Origin") != "https://ninho.example" {
		t.Fatal("preflight failed")
	}
}
func TestCannotMoveRecord(t *testing.T) {
	h, c := setup(t)
	w := request(h, "PATCH", "/v1/data/goals/"+uid, `{"household_id":"`+uid+`"}`, "Bearer valid-user-token", "")
	if w.Code != 400 || *c != 0 {
		t.Fatal("record move allowed")
	}
}
func TestValidateConfig(t *testing.T) {
	c := Config{SupabaseURL: "https://project.supabase.co", PublishableKey: "pub", Origins: []string{"https://ninho.example"}}
	if c.Validate() != nil {
		t.Fatal("valid config rejected")
	}
	c.Origins = []string{"*"}
	if c.Validate() == nil {
		t.Fatal("wildcard accepted")
	}
}
