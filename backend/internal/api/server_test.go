package api

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const uid = "d2717c73-3a3a-4a24-9a10-8053a7e5d771"

// jwtHeader starts every token sessionToken builds; the fake Auth server accepts them all.
const jwtHeader = "eyJhbGciOiJIUzI1NiJ9."

// sessionToken is shaped like a Supabase access token whose last sign-in happened at the given time.
func sessionToken(at time.Time) string {
	payload, _ := json.Marshal(map[string]any{"sub": uid, "amr": []map[string]any{{"method": "password", "timestamp": at.Unix()}}})
	return "Bearer " + jwtHeader + base64.RawURLEncoding.EncodeToString(payload) + ".signature"
}

func setup(t *testing.T) (http.Handler, *int) { return setupUpstream(t, 200, `[]`) }
func setupUpstream(t *testing.T, status int, body string) (http.Handler, *int) {
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
		// The secret key is configured below, so this also proves it never reaches data calls.
		if r.Header.Get("Authorization") != "Bearer valid-user-token" || r.Header.Get("apikey") != "public-key" {
			t.Error("user credentials must be forwarded")
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(up.Close)
	return New(Config{SupabaseURL: up.URL, PublishableKey: "public-key", SecretKey: "secret-key", Origins: []string{"https://ninho.example"}}), &calls
}

// setupAccount stands in for Supabase Auth: it checks the user's token and records admin deletions.
func setupAccount(t *testing.T, adminStatus int, secret string) (http.Handler, *[]string) {
	t.Helper()
	var deleted []string
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/auth/v1/user":
			auth := r.Header.Get("Authorization")
			if auth != "Bearer valid-user-token" && !strings.HasPrefix(auth, "Bearer "+jwtHeader) {
				w.WriteHeader(401)
				return
			}
			_, _ = w.Write([]byte(`{"id":"` + uid + `"}`))
		case strings.HasPrefix(r.URL.Path, "/auth/v1/admin/users/"):
			if r.Method != http.MethodDelete || r.Header.Get("apikey") != "secret-key" || r.Header.Get("Authorization") != "Bearer secret-key" {
				t.Error("the admin call must carry the secret key and never the user token")
			}
			deleted = append(deleted, strings.TrimPrefix(r.URL.Path, "/auth/v1/admin/users/"))
			w.WriteHeader(adminStatus)
		default:
			t.Errorf("unexpected upstream call: %s %s", r.Method, r.URL.Path)
		}
	}))
	t.Cleanup(up.Close)
	return New(Config{SupabaseURL: up.URL, PublishableKey: "public-key", SecretKey: secret, Origins: []string{"https://ninho.example"}}), &deleted
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
func TestDatabaseMessages(t *testing.T) {
	for _, tc := range []struct{ body, want string }{
		{`{"code":"P0001","message":"Family is full"}`, "Esta família já tem quatro pessoas"},
		{`{"code":"P0001","message":"Internal detail"}`, "Verifique os campos e o acesso à família"},
		{`<html>Bad gateway</html>`, "Verifique os campos e o acesso à família"},
	} {
		h, _ := setupUpstream(t, 400, tc.body)
		w := request(h, "POST", "/v1/rpc/accept_invite", `{"p_token":"`+strings.Repeat("a", 64)+`"}`, "Bearer valid-user-token", "")
		if w.Code != 400 || !strings.Contains(w.Body.String(), tc.want) {
			t.Errorf("%s: %d %s", tc.body, w.Code, w.Body)
		}
	}
}
func TestMemberRpcs(t *testing.T) {
	for _, tc := range []struct {
		path, body string
		status     int
		calls      int
	}{{"/v1/rpc/list_members", `{"p_household_id":"` + uid + `"}`, 200, 1}, {"/v1/rpc/remove_member", `{"p_household_id":"` + uid + `","p_user_id":"` + uid + `"}`, 200, 1}, {"/v1/rpc/leave_household", `{"p_household_id":"` + uid + `"}`, 200, 1}, {"/v1/rpc/remove_member", `{"p_household_id":"` + uid + `","role":"owner"}`, 400, 0}} {
		h, c := setup(t)
		w := request(h, "POST", tc.path, tc.body, "Bearer valid-user-token", "")
		if w.Code != tc.status || *c != tc.calls {
			t.Errorf("%s %s: %d after %d calls", tc.path, tc.body, w.Code, *c)
		}
	}
}
func TestDeleteAccount(t *testing.T) {
	h, deleted := setupAccount(t, 200, "secret-key")
	w := request(h, "DELETE", "/v1/account", "", sessionToken(time.Now()), "https://ninho.example")
	if w.Code != 204 || len(*deleted) != 1 || (*deleted)[0] != uid {
		t.Fatalf("delete: %d, admin calls %v", w.Code, *deleted)
	}
}
func TestDeleteAccountBoundaries(t *testing.T) {
	fresh, stale := sessionToken(time.Now()), sessionToken(time.Now().Add(-time.Hour))
	for _, tc := range []struct {
		name, method, token, secret string
		admin, status, calls        int
	}{
		{"unauthenticated", "DELETE", "", "secret-key", 200, 401, 0},
		{"forged token", "DELETE", "Bearer forged-token-long", "secret-key", 200, 401, 0},
		{"wrong method", "POST", fresh, "secret-key", 200, 405, 0},
		{"no secret key", "DELETE", fresh, "", 200, 503, 0},
		{"sign-in too old", "DELETE", stale, "secret-key", 200, 403, 0},
		{"token without sign-in time", "DELETE", "Bearer valid-user-token", "secret-key", 200, 403, 0},
		{"already deleted", "DELETE", fresh, "secret-key", 404, 204, 1},
		{"auth failure", "DELETE", fresh, "secret-key", 500, 503, 1},
	} {
		h, deleted := setupAccount(t, tc.admin, tc.secret)
		w := request(h, tc.method, "/v1/account", "", tc.token, "")
		if w.Code != tc.status || len(*deleted) != tc.calls {
			t.Errorf("%s: %d after %d admin calls", tc.name, w.Code, len(*deleted))
		}
	}
}
func TestValidateConfig(t *testing.T) {
	c := Config{SupabaseURL: "https://project.supabase.co", PublishableKey: "pub", Origins: []string{"https://ninho.example"}}
	if c.Validate() != nil {
		t.Fatal("valid config rejected")
	}
	c.SecretKey = "sb_secret_abc"
	if c.Validate() != nil {
		t.Fatal("secret key rejected")
	}
	for i, bad := range []Config{
		{PublishableKey: "sb_secret_abc"},
		{PublishableKey: "pub", SecretKey: "pub"},
		{PublishableKey: "pub", SecretKey: "sb_publishable_abc"},
	} {
		bad.SupabaseURL, bad.Origins = c.SupabaseURL, c.Origins
		if bad.Validate() == nil {
			t.Errorf("mixed-up keys accepted in case %d", i)
		}
	}
	c.Origins = []string{"*"}
	if c.Validate() == nil {
		t.Fatal("wildcard accepted")
	}
}
