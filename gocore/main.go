// Package main builds the GoCore static library (`libgocore.a`) that embeds
// sing-box in-process and exposes a small C ABI consumed by the Swift app via
// `Sources/Riptide/Bridge/GoCoreBridge.swift`.
//
// Build (matches the original tags plus with_utls for REALITY/uTLS):
//
//	go build -buildmode=c-archive \
//	  -tags "with_gvisor,with_wireguard,with_quic,with_utls" \
//	  -o libgocore.a main.go
//
// See Scripts/build-gocore.sh.
package main

/*
#include <stdlib.h>
typedef void (*EventCallback)(const char* eventType, const char* eventData);
static void callEventCallback(EventCallback cb, const char* eventType, const char* eventData) {
    cb(eventType, eventData);
}
*/
import "C"

import (
	"context"
	"sync"
	"unsafe"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/outbound"
	"github.com/sagernet/sing/common/json"
)

var (
	mu       sync.Mutex
	instance *box.Box
	cancel   context.CancelFunc
)

// GoCoreStart parses the sing-box JSON config, creates and starts the core.
// Returns NULL on success, or a C string describing the failure (caller frees).
//
//export GoCoreStart
func GoCoreStart(configJSON *C.char, cb C.EventCallback) *C.char {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		return C.CString("already running")
	}

	content := C.GoString(configJSON)
	options, err := json.UnmarshalExtended[option.Options]([]byte(content))
	if err != nil {
		return C.CString("decode config: " + err.Error())
	}

	ctx, ctxCancel := context.WithCancel(context.Background())
	instance, err = box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		ctxCancel()
		instance = nil
		return C.CString("create service: " + err.Error())
	}
	if err = instance.Start(); err != nil {
		ctxCancel()
		_ = instance.Close()
		instance = nil
		return C.CString("start service: " + err.Error())
	}
	cancel = ctxCancel

	emitEvent(cb, "status", "running")
	return nil
}

// GoCoreStop stops and tears down the running core (no-op if not running).
//
//export GoCoreStop
func GoCoreStop() {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return
	}
	if cancel != nil {
		cancel()
		cancel = nil
	}
	_ = instance.Close()
	instance = nil
}

// GoCoreGetTraffic writes the cumulative up/down byte counters.
//
// Real per-connection counters live in sing-box's clash-api traffic manager,
// which the generated config does not enable; report zero rather than fabricate
// values (the previous build returned hard-coded mock numbers).
//
//export GoCoreGetTraffic
func GoCoreGetTraffic(up *C.longlong, down *C.longlong) {
	if up != nil {
		*up = 0
	}
	if down != nil {
		*down = 0
	}
}

// GoCoreSwitchProxy selects `proxyName` inside the selector outbound `groupName`.
// Best-effort: a missing group or non-selector outbound is a silent no-op so the
// UI is not spammed with errors (selector groups are not always generated).
//
//export GoCoreSwitchProxy
func GoCoreSwitchProxy(groupName *C.char, proxyName *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil // no-op when not running
	}
	group := C.GoString(groupName)
	proxy := C.GoString(proxyName)

	out, ok := instance.Router().Outbound(group)
	if !ok {
		return nil
	}
	selector, ok := out.(*outbound.Selector)
	if !ok {
		return nil
	}
	selector.SelectOutbound(proxy)
	return nil
}

func emitEvent(cb C.EventCallback, eventType, eventData string) {
	if cb == nil {
		return
	}
	cType := C.CString(eventType)
	cData := C.CString(eventData)
	C.callEventCallback(cb, cType, cData)
	C.free(unsafe.Pointer(cType))
	C.free(unsafe.Pointer(cData))
}

func main() {}
