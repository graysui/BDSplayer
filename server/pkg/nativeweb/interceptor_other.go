//go:build !windows
// +build !windows

package nativeweb

import (
	"github.com/jchv/go-webview2"
)

func EnableBaiduDirectStreamInterception(w webview2.WebView) bool {
	return false
}
