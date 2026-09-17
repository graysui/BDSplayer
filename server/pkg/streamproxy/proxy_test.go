package streamproxy

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestStreamProxyPrefetchAndRange(t *testing.T) {
	// Generate 10MB of pseudo-random video-like data
	dataSize := int64(10 * 1024 * 1024)
	mockData := make([]byte, dataSize)
	for i := range mockData {
		mockData[i] = byte(i % 256)
	}

	// Mock Upstream Baidu CDN Server
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rangeHdr := r.Header.Get("Range")
		if rangeHdr == "" {
			w.Header().Set("Content-Length", strconv.FormatInt(dataSize, 10))
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(mockData)
			return
		}

		// Handle range
		spec := strings.TrimPrefix(rangeHdr, "bytes=")
		parts := strings.Split(spec, "-")
		start, _ := strconv.ParseInt(parts[0], 10, 64)
		end := dataSize - 1
		if len(parts) > 1 && parts[1] != "" {
			end, _ = strconv.ParseInt(parts[1], 10, 64)
		}
		if end >= dataSize {
			end = dataSize - 1
		}

		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, dataSize))
		w.Header().Set("Content-Length", strconv.FormatInt(end-start+1, 10))
		w.WriteHeader(http.StatusPartialContent)
		_, _ = w.Write(mockData[start : end+1])
	}))
	defer upstream.Close()

	proxy := NewStreamProxy()
	sessionID := "test_session_1"
	proxy.RegisterStream(sessionID, upstream.URL, dataSize)

	proxyServer := httptest.NewServer(proxy)
	defer proxyServer.Close()

	// 1. Test first 1MB read (bytes=0-1048575)
	req, _ := http.NewRequest(http.MethodGet, fmt.Sprintf("%s/stream?id=%s", proxyServer.URL, sessionID), nil)
	req.Header.Set("Range", "bytes=0-1048575")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("expected 206, got %d", resp.StatusCode)
	}
	gotData, _ := io.ReadAll(resp.Body)
	if int64(len(gotData)) != 1048576 {
		t.Fatalf("expected 1MB, got %d bytes", len(gotData))
	}
	if !bytes.Equal(gotData, mockData[:1048576]) {
		t.Fatalf("data mismatch in first chunk")
	}

	// 2. Test Range seek to middle (e.g. bytes=5000000-6000000)
	req2, _ := http.NewRequest(http.MethodGet, fmt.Sprintf("%s/stream?id=%s", proxyServer.URL, sessionID), nil)
	req2.Header.Set("Range", "bytes=5000000-6000000")
	resp2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("seek request failed: %v", err)
	}
	defer resp2.Body.Close()

	if resp2.StatusCode != http.StatusPartialContent {
		t.Fatalf("expected 206 on seek, got %d", resp2.StatusCode)
	}
	gotData2, _ := io.ReadAll(resp2.Body)
	expectedLen := int64(6000000 - 5000000 + 1)
	if int64(len(gotData2)) != expectedLen {
		t.Fatalf("expected %d bytes, got %d", expectedLen, len(gotData2))
	}
	if !bytes.Equal(gotData2, mockData[5000000:6000001]) {
		t.Fatalf("data mismatch on seek chunk")
	}
}
