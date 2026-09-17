package streamproxy

import (
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"
)

// StreamProxy handles HTTP streaming via transparent progressive reverse proxy
type StreamProxy struct {
	mu       sync.RWMutex
	sessions map[string]string // sessionID -> dlink
	client   *http.Client
	baseURL  string
}

func NewStreamProxy() *StreamProxy {
	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   15 * time.Second,
			KeepAlive: 60 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          200,
		MaxIdleConnsPerHost:   40,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		DisableCompression:   true, // Critical: prevent Go from tampering with range/content-length
	}

	return &StreamProxy{
		sessions: make(map[string]string),
		baseURL:  "http://127.0.0.1:18900",
		client: &http.Client{
			Transport: transport,
			Timeout:   0, // Streaming without global timeout
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				req.Header.Set("User-Agent", "pan.baidu.com")
				req.Header.Set("Referer", "https://pan.baidu.com")
				if len(via) > 0 {
					if r := via[0].Header.Get("Range"); r != "" {
						req.Header.Set("Range", r)
					}
				}
				return nil
			},
		},
	}
}

func (p *StreamProxy) SetBaseURL(baseURL string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.baseURL = baseURL
}

func (p *StreamProxy) RegisterStream(sessionID, dlink string, size ...int64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.sessions[sessionID] = dlink
}

func (p *StreamProxy) UnregisterStream(sessionID string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	delete(p.sessions, sessionID)
}

func (p *StreamProxy) GetStreamURL(sessionID string) string {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return fmt.Sprintf("%s/stream?id=%s", p.baseURL, sessionID)
}

func (p *StreamProxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("id")
	if sessionID == "" {
		http.Error(w, "missing session id", http.StatusBadRequest)
		return
	}

	p.mu.RLock()
	dlink, exists := p.sessions[sessionID]
	p.mu.RUnlock()

	if !exists || dlink == "" {
		http.Error(w, "stream session expired or not found", http.StatusNotFound)
		return
	}

	upstreamReq, err := http.NewRequestWithContext(r.Context(), r.Method, dlink, nil)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	upstreamReq.Header.Set("User-Agent", "pan.baidu.com")
	upstreamReq.Header.Set("Referer", "https://pan.baidu.com")
	if clientRange := r.Header.Get("Range"); clientRange != "" {
		upstreamReq.Header.Set("Range", clientRange)
	}

	resp, err := p.client.Do(upstreamReq)
	if err != nil {
		http.Error(w, fmt.Sprintf("upstream error: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Range, Accept-Encoding")
	w.Header().Set("Access-Control-Expose-Headers", "Content-Range, Content-Length, Accept-Ranges")

	for k, vals := range resp.Header {
		for _, v := range vals {
			w.Header().Add(k, v)
		}
	}
	if w.Header().Get("Accept-Ranges") == "" {
		w.Header().Set("Accept-Ranges", "bytes")
	}
	if w.Header().Get("Content-Type") == "" {
		w.Header().Set("Content-Type", "video/mp4")
	}

	w.WriteHeader(resp.StatusCode)

	if r.Method == http.MethodHead {
		return
	}

	flusher, hasFlusher := w.(http.Flusher)
	buf := make([]byte, 128*1024)
	for {
		select {
		case <-r.Context().Done():
			return
		default:
		}

		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			_, writeErr := w.Write(buf[:n])
			if writeErr != nil {
				return
			}
			if hasFlusher {
				flusher.Flush()
			}
		}
		if readErr != nil {
			return
		}
	}
}
