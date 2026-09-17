//go:build windows
// +build windows

package nativeweb

import (
	"reflect"
	"strings"
	"unsafe"

	"github.com/jchv/go-webview2"
	"github.com/jchv/go-webview2/pkg/edge"
	"golang.org/x/sys/windows"
)

type iUnknownVtbl struct {
	QueryInterface edge.ComProc
	AddRef         edge.ComProc
	Release        edge.ComProc
}

type _ICoreWebView2HttpRequestHeadersVtbl struct {
	iUnknownVtbl
	GetHeader    edge.ComProc
	GetHeaders   edge.ComProc
	Contains     edge.ComProc
	SetHeader    edge.ComProc
	RemoveHeader edge.ComProc
	GetIterator  edge.ComProc
}

type ICoreWebView2HttpRequestHeaders struct {
	vtbl *_ICoreWebView2HttpRequestHeadersVtbl
}

func (h *ICoreWebView2HttpRequestHeaders) SetHeader(name, value string) error {
	namePtr, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return err
	}
	valPtr, err := windows.UTF16PtrFromString(value)
	if err != nil {
		return err
	}
	_, _, err = h.vtbl.SetHeader.Call(
		uintptr(unsafe.Pointer(h)),
		uintptr(unsafe.Pointer(namePtr)),
		uintptr(unsafe.Pointer(valPtr)),
	)
	if err != windows.ERROR_SUCCESS {
		return err
	}
	return nil
}

type _ICoreWebView2WebResourceRequestHelperVtbl struct {
	iUnknownVtbl
	GetUri     edge.ComProc
	PutUri     edge.ComProc
	GetMethod  edge.ComProc
	PutMethod  edge.ComProc
	GetContent edge.ComProc
	PutContent edge.ComProc
	GetHeaders edge.ComProc
}

type webResourceRequestHelper struct {
	vtbl *_ICoreWebView2WebResourceRequestHelperVtbl
}

func getRequestHeaders(req *edge.ICoreWebView2WebResourceRequest) (*ICoreWebView2HttpRequestHeaders, error) {
	helper := (*webResourceRequestHelper)(unsafe.Pointer(req))
	var headers *ICoreWebView2HttpRequestHeaders
	_, _, err := helper.vtbl.GetHeaders.Call(
		uintptr(unsafe.Pointer(helper)),
		uintptr(unsafe.Pointer(&headers)),
	)
	if err != windows.ERROR_SUCCESS {
		return nil, err
	}
	return headers, nil
}

// Memory layout mirror of jchv/go-webview2 internal webview struct
type webviewInternal struct {
	hwnd       uintptr
	mainthread uintptr
	browser    struct {
		tab  uintptr
		data *edge.Chromium
	}
}

// ExtractChromium retrieves the underlying *edge.Chromium instance from a webview2.WebView
func ExtractChromium(w webview2.WebView) *edge.Chromium {
	if w == nil {
		return nil
	}
	v := reflect.ValueOf(w)
	if v.Kind() != reflect.Ptr || v.IsNil() {
		return nil
	}
	ptr := (*webviewInternal)(unsafe.Pointer(v.Pointer()))
	return ptr.browser.data
}

// EnableBaiduDirectStreamInterception attaches WebResourceRequested hook to inject
// User-Agent and Referer headers directly into outgoing requests to Baidu PCS CDN
func EnableBaiduDirectStreamInterception(w webview2.WebView) bool {
	chromium := ExtractChromium(w)
	if chromium == nil {
		return false
	}

	// Register filters for Baidu Netdisk download / media domains
	chromium.AddWebResourceRequestedFilter("*baidupcs.com*", edge.COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL)
	chromium.AddWebResourceRequestedFilter("*pcs.baidu.com*", edge.COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL)

	prevCallback := chromium.WebResourceRequestedCallback

	chromium.WebResourceRequestedCallback = func(req *edge.ICoreWebView2WebResourceRequest, args *edge.ICoreWebView2WebResourceRequestedEventArgs) {
		if req != nil {
			uri, err := req.GetUri()
			if err == nil && uri != "" {
				if strings.Contains(uri, "baidupcs.com") || strings.Contains(uri, "pcs.baidu.com") {
					headers, err := getRequestHeaders(req)
					if err == nil && headers != nil {
						_ = headers.SetHeader("User-Agent", "pan.baidu.com")
						_ = headers.SetHeader("Referer", "https://pan.baidu.com")
					}
				}
			}
		}

		if prevCallback != nil {
			prevCallback(req, args)
		}
	}

	return true
}
