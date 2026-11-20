package api

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"html"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"
)

// Product is what a store page says about an item: the layette option the app fills in from a link.
type Product struct {
	Title          string `json:"title"`
	Description    string `json:"description"`
	Image          string `json:"image_url"`
	Store          string `json:"store"`
	PriceCents     *int64 `json:"price_cents"`
	ListPriceCents *int64 `json:"list_price_cents"`
}

var errPage = errors.New("page unavailable")

// pageClient fetches store pages for link previews and the daily price check. Every connection goes
// through a dialer that refuses private, loopback and link-local addresses, so a link can't reach the
// API's own network, even after a redirect or a DNS answer that changes between lookups.
func pageClient() *http.Client {
	dialer := &net.Dialer{Timeout: 5 * time.Second, Control: func(_, address string, _ syscall.RawConn) error {
		host, _, err := net.SplitHostPort(address)
		if err != nil {
			return err
		}
		ip := net.ParseIP(host)
		if ip == nil || !publicIP(ip) {
			return errors.New("address not allowed")
		}
		return nil
	}}
	transport := &http.Transport{DialContext: dialer.DialContext, TLSHandshakeTimeout: 5 * time.Second,
		ResponseHeaderTimeout: 8 * time.Second, MaxIdleConns: 10, IdleConnTimeout: 30 * time.Second}
	return &http.Client{Transport: transport, Timeout: 12 * time.Second, CheckRedirect: func(r *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return errors.New("too many redirects")
		}
		return checkPageURL(r.URL)
	}}
}

var sharedRanges = func() []*net.IPNet {
	var out []*net.IPNet
	for _, cidr := range []string{"0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "198.18.0.0/15", "240.0.0.0/4", "64:ff9b::/96"} {
		_, n, _ := net.ParseCIDR(cidr)
		out = append(out, n)
	}
	return out
}()

func publicIP(ip net.IP) bool {
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsInterfaceLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() {
		return false
	}
	for _, n := range sharedRanges {
		if n.Contains(ip) {
			return false
		}
	}
	return true
}

// checkPageURL accepts only plain web addresses on the default ports, without credentials.
func checkPageURL(u *url.URL) error {
	if u == nil || (u.Scheme != "https" && u.Scheme != "http") || u.Hostname() == "" || u.User != nil || u.Port() != "" {
		return errors.New("invalid link")
	}
	return nil
}

// fetchProduct downloads a store page and reads the product data it publishes.
func fetchProduct(ctx context.Context, client *http.Client, raw string) (Product, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || checkPageURL(u) != nil || len(raw) > 2000 {
		return Product{}, errors.New("invalid link")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return Product{}, errors.New("invalid link")
	}
	// Stores answer browsers; a bare client often gets an empty page.
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5")
	req.Header.Set("Accept-Language", "pt-BR,pt;q=0.9,en;q=0.6")
	res, err := client.Do(req)
	if err != nil {
		return Product{}, errPage
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return Product{}, errPage
	}
	if ct := res.Header.Get("Content-Type"); ct != "" && !strings.Contains(ct, "html") {
		return Product{}, errPage
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	if err != nil {
		return Product{}, errPage
	}
	p := parseProduct(body, res.Request.URL)
	if p.Title == "" && p.PriceCents == nil {
		return Product{}, errPage
	}
	return p, nil
}

var (
	metaTag  = regexp.MustCompile(`(?is)<meta\b[^>]*>`)
	attr     = regexp.MustCompile(`(?is)([a-z_:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))`)
	titleTag = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
	jsonLD   = regexp.MustCompile(`(?is)<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>`)
	spaces   = regexp.MustCompile(`\s+`)
)

// parseProduct reads schema.org Product data (JSON-LD) first, then Open Graph and product meta tags.
func parseProduct(body []byte, page *url.URL) Product {
	meta := map[string]string{}
	for _, tag := range metaTag.FindAll(body, 400) {
		attrs := map[string]string{}
		for _, m := range attr.FindAllSubmatch(tag, -1) {
			attrs[strings.ToLower(string(m[1]))] = string(m[2]) + string(m[3]) + string(m[4])
		}
		key := attrs["property"]
		if key == "" {
			key = attrs["name"]
		}
		if key == "" {
			key = attrs["itemprop"]
		}
		key = strings.ToLower(key)
		if _, seen := meta[key]; key != "" && !seen {
			meta[key] = html.UnescapeString(attrs["content"])
		}
	}
	var p Product
	var currency string
	for _, block := range jsonLD.FindAllSubmatch(body, 20) {
		var doc any
		if json.Unmarshal(bytes.TrimSpace(block[1]), &doc) != nil {
			continue
		}
		if product := findProduct(doc, 0); product != nil {
			p.Title = text(product["name"])
			p.Description = text(product["description"])
			p.Image = imageOf(product["image"])
			p.PriceCents, p.ListPriceCents, currency = offerPrices(product["offers"])
			break
		}
	}
	first := func(keys ...string) string {
		for _, k := range keys {
			if v := strings.TrimSpace(meta[k]); v != "" {
				return v
			}
		}
		return ""
	}
	if p.Title == "" {
		p.Title = first("og:title", "twitter:title")
	}
	if p.Title == "" {
		if m := titleTag.FindSubmatch(body); m != nil {
			p.Title = html.UnescapeString(string(m[1]))
		}
	}
	if p.Description == "" {
		p.Description = first("og:description", "description", "twitter:description")
	}
	if p.Image == "" {
		p.Image = first("og:image:secure_url", "og:image", "twitter:image", "image")
	}
	if p.PriceCents == nil {
		p.PriceCents = parsePrice(first("product:sale_price:amount", "product:price:amount", "og:price:amount", "price"))
		currency = first("product:price:currency", "og:price:currency", "pricecurrency")
	}
	if p.ListPriceCents == nil {
		p.ListPriceCents = parsePrice(first("product:original_price:amount", "og:original_price:amount"))
	}
	if currency != "" && !strings.EqualFold(currency, "BRL") {
		p.PriceCents, p.ListPriceCents = nil, nil
	}
	if p.PriceCents == nil || p.ListPriceCents != nil && *p.ListPriceCents <= *p.PriceCents {
		p.ListPriceCents = nil
	}
	p.Store = first("og:site_name", "application-name")
	if p.Store == "" && page != nil {
		p.Store = strings.TrimPrefix(page.Hostname(), "www.")
	}
	p.Title = clip(p.Title, 160)
	p.Description = clip(p.Description, 600)
	p.Store = clip(p.Store, 80)
	p.Image = absoluteImage(p.Image, page)
	return p
}

func findProduct(v any, depth int) map[string]any {
	if depth > 6 {
		return nil
	}
	switch t := v.(type) {
	case []any:
		for _, item := range t {
			if p := findProduct(item, depth+1); p != nil {
				return p
			}
		}
	case map[string]any:
		if isType(t["@type"], "Product") {
			return t
		}
		for _, key := range []string{"@graph", "mainEntity", "itemListElement", "item"} {
			if p := findProduct(t[key], depth+1); p != nil {
				return p
			}
		}
	}
	return nil
}

func isType(v any, want string) bool {
	switch t := v.(type) {
	case string:
		return strings.EqualFold(t, want) || strings.HasSuffix(strings.ToLower(t), "/"+strings.ToLower(want))
	case []any:
		for _, item := range t {
			if isType(item, want) {
				return true
			}
		}
	}
	return false
}

// offerPrices takes the lowest offered price, and the list price ("de") when the store states one.
func offerPrices(v any) (price, list *int64, currency string) {
	var offers []map[string]any
	switch t := v.(type) {
	case map[string]any:
		offers = append(offers, t)
		if inner, ok := t["offers"]; ok {
			p, l, c := offerPrices(inner)
			if p != nil {
				return p, l, c
			}
		}
	case []any:
		for _, item := range t {
			if m, ok := item.(map[string]any); ok {
				offers = append(offers, m)
			}
		}
	}
	for _, o := range offers {
		candidate := parsePrice(o["price"])
		if candidate == nil {
			candidate = parsePrice(o["lowPrice"])
		}
		var specs []any
		switch s := o["priceSpecification"].(type) {
		case []any:
			specs = s
		case map[string]any:
			specs = []any{s}
		}
		for _, raw := range specs {
			spec, _ := raw.(map[string]any)
			value := parsePrice(spec["price"])
			kind := strings.ToLower(text(spec["priceType"]))
			if strings.Contains(kind, "listprice") || strings.Contains(kind, "strikethrough") {
				list = value
			} else if candidate == nil {
				candidate = value
			}
		}
		if candidate != nil && (price == nil || *candidate < *price) {
			price = candidate
			currency = text(o["priceCurrency"])
		}
	}
	return price, list, currency
}

// parsePrice reads 1299.9, "1299.90", "1.299,90" or "R$ 1.299" as cents, without floating point.
func parsePrice(v any) *int64 {
	var s string
	switch t := v.(type) {
	case string:
		s = t
	case float64:
		s = strings.TrimRight(strings.TrimRight(json.Number(formatFloat(t)).String(), "0"), ".")
	case json.Number:
		s = t.String()
	default:
		return nil
	}
	s = strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' || r == ',' || r == '.' {
			return r
		}
		return -1
	}, s)
	if s == "" {
		return nil
	}
	whole, frac := s, ""
	if i := strings.LastIndexAny(s, ",."); i >= 0 {
		after := s[i+1:]
		// One or two digits after the last separator make it the decimal one; three mean thousands.
		if len(after) <= 2 && !(strings.Count(s, string(s[i])) > 1) {
			whole, frac = s[:i], after
		}
	}
	whole = strings.NewReplacer(",", "", ".", "").Replace(whole)
	if whole == "" {
		whole = "0"
	}
	if len(whole) > 11 {
		return nil
	}
	for len(frac) < 2 {
		frac += "0"
	}
	var cents int64
	for _, r := range whole + frac {
		cents = cents*10 + int64(r-'0')
	}
	if cents <= 0 {
		return nil
	}
	return &cents
}

func formatFloat(f float64) string {
	b, _ := json.Marshal(f)
	return string(b)
}

func text(v any) string {
	switch t := v.(type) {
	case string:
		return html.UnescapeString(t)
	case map[string]any:
		return text(t["name"])
	case []any:
		if len(t) > 0 {
			return text(t[0])
		}
	}
	return ""
}

func imageOf(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []any:
		if len(t) > 0 {
			return imageOf(t[0])
		}
	case map[string]any:
		if u := text(t["url"]); u != "" {
			return u
		}
		return text(t["contentUrl"])
	}
	return ""
}

// absoluteImage resolves the image against the page and keeps it only over HTTPS.
func absoluteImage(raw string, page *url.URL) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	if page != nil {
		u = page.ResolveReference(u)
	}
	if u.Scheme == "http" {
		u.Scheme = "https"
	}
	if u.Scheme != "https" || u.Host == "" || len(u.String()) > 2000 {
		return ""
	}
	return u.String()
}

func clip(s string, max int) string {
	s = strings.TrimSpace(spaces.ReplaceAllString(s, " "))
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	r := []rune(s)
	return strings.TrimSpace(string(r[:max-1])) + "…"
}

// preview answers POST /v1/preview {"url": "..."} with the product data of a store page.
func (s *Server) preview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		fail(w, 405, "Use POST")
		return
	}
	id, _ := r.Context().Value(userKey{}).(string)
	if !s.allowN("preview:"+id, 30) {
		w.Header().Set("Retry-After", "60")
		fail(w, 429, "Muitas consultas de links. Tente novamente em um minuto")
		return
	}
	obj, err := decode(w, r, "url")
	if err != nil {
		fail(w, 400, err.Error())
		return
	}
	link, _ := obj["url"].(string)
	p, err := fetchProduct(r.Context(), s.pages, link)
	if err != nil {
		if err.Error() == "invalid link" {
			fail(w, 400, "Confira o link: use o endereço completo da página do produto")
			return
		}
		fail(w, 422, "Não conseguimos ler essa página. Preencha os dados à mão")
		return
	}
	send(w, 200, p)
}

// refreshPrices answers POST /internal/refresh-prices, called once a day by pg_cron with CRON_SECRET.
// It answers right away and, in the background with the secret key, takes Plus back from refunded Google Play
// purchases and checks every linked option.
func (s *Server) refreshPrices(w http.ResponseWriter, r *http.Request) {
	auth := r.Header.Get("Authorization")
	if s.cfg.CronSecret == "" || s.cfg.SecretKey == "" ||
		subtle.ConstantTimeCompare([]byte(auth), []byte("Bearer "+s.cfg.CronSecret)) != 1 {
		fail(w, 404, "Recurso não encontrado")
		return
	}
	if r.Method != http.MethodPost {
		fail(w, 405, "Use POST")
		return
	}
	if !s.refreshing.CompareAndSwap(false, true) {
		send(w, 409, map[string]string{"status": "running"})
		return
	}
	go func() {
		defer s.refreshing.Store(false)
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
		defer cancel()
		// Refunded Plus purchases lose Plus with the same daily call.
		if s.play != nil {
			if n, err := s.syncVoided(ctx); err != nil {
				slog.Error("voided purchases check failed", "error", err)
			} else {
				slog.Info("voided purchases checked", "voided", n)
			}
		}
		checked, changed, failed, err := s.checkAllPrices(ctx)
		if err != nil {
			slog.Error("price check failed", "error", err)
			return
		}
		slog.Info("price check done", "checked", checked, "with_price", changed, "failed", failed)
	}()
	send(w, 202, map[string]string{"status": "started"})
}

type linkedOption struct {
	ID       string `json:"id"`
	URL      string `json:"url"`
	ImageURL string `json:"image_url"`
}

func (s *Server) admin(ctx context.Context, method, path string, body any) (*http.Response, error) {
	var reader io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, s.cfg.SupabaseURL+path, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("apikey", s.cfg.SecretKey)
	req.Header.Set("Authorization", "Bearer "+s.cfg.SecretKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")
	return s.client.Do(req)
}

// checkAllPrices reads every option with a link, oldest check first, and stores what each page says now.
// A page that doesn't answer keeps its last price; the triggers keep the history and the change alert.
func (s *Server) checkAllPrices(ctx context.Context) (checked, priced, failed int, err error) {
	res, err := s.admin(ctx, http.MethodGet, "/rest/v1/goal_options?select=id,url,image_url&url=neq.&order=checked_at.asc.nullsfirst&limit=2000", nil)
	if err != nil {
		return 0, 0, 0, err
	}
	var options []linkedOption
	decodeErr := json.NewDecoder(io.LimitReader(res.Body, 16<<20)).Decode(&options)
	res.Body.Close()
	if res.StatusCode != 200 || decodeErr != nil {
		return 0, 0, 0, errors.New("could not list options")
	}
	jobs := make(chan linkedOption)
	var mu sync.Mutex
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for o := range jobs {
				p, ferr := fetchProduct(ctx, s.pages, o.URL)
				patch := map[string]any{"checked_at": time.Now().UTC().Format(time.RFC3339), "check_failed": ferr != nil || p.PriceCents == nil}
				if ferr == nil && p.PriceCents != nil {
					patch["price_cents"] = *p.PriceCents
					patch["list_price_cents"] = p.ListPriceCents
				}
				if ferr == nil && o.ImageURL == "" && p.Image != "" {
					patch["image_url"] = p.Image
				}
				if r, perr := s.admin(ctx, http.MethodPatch, "/rest/v1/goal_options?id=eq."+url.QueryEscape(o.ID), patch); perr == nil {
					r.Body.Close()
				}
				mu.Lock()
				checked++
				if patch["check_failed"] == true {
					failed++
				} else {
					priced++
				}
				mu.Unlock()
				// Be gentle with the stores.
				select {
				case <-ctx.Done():
				case <-time.After(700 * time.Millisecond):
				}
			}
		}()
	}
	for _, o := range options {
		if !uuid.MatchString(o.ID) {
			continue
		}
		select {
		case jobs <- o:
		case <-ctx.Done():
		}
	}
	close(jobs)
	wg.Wait()
	return checked, priced, failed, nil
}
