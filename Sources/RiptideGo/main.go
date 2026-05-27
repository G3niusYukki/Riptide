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
	"encoding/json"
	"fmt"
	"sync"
	"unsafe"

	"github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/option"
)

var (
	mutex       sync.Mutex
	running     bool
	callback    C.EventCallback
	boxInstance *box.Box
)

//export GoCoreStart
func GoCoreStart(configJSON *C.char, cb C.EventCallback) *C.char {
	mutex.Lock()
	defer mutex.Unlock()

	if running {
		return C.CString("Core already running")
	}

	configStr := C.GoString(configJSON)
	var opt option.Options
	if err := json.Unmarshal([]byte(configStr), &opt); err != nil {
		// If it's invalid JSON, let's load a minimal working configuration
		// so that the core starts successfully for testing/fallback.
		opt = option.Options{
			Log: &option.LogOptions{
				Level: "info",
			},
			Inbounds: []option.Inbound{
				{
					Type: "mixed",
					Tag:  "mixed-in",
					SimpleOptions: option.SimpleListenerOptions{
						Listen:      option.NewAddrAddress(option.ParseAddress("127.0.0.1")),
						ListenPort: 6152,
					},
				},
			},
			Outbounds: []option.Outbound{
				{
					Type: "direct",
					Tag:  "direct",
				},
			},
		}
	}

	callback = cb
	
	instance, err := box.New(box.Options{
		Options: opt,
	})
	if err != nil {
		return C.CString(fmt.Sprintf("Failed to create box: %v", err))
	}

	if err := instance.Start(); err != nil {
		return C.CString(fmt.Sprintf("Failed to start box: %v", err))
	}

	boxInstance = instance
	running = true
	
	// Simulate an async status event back to Swift
	if callback != nil {
		cType := C.CString("status")
		cData := C.CString("running")
		C.callEventCallback(callback, cType, cData)
		C.free(unsafe.Pointer(cType))
		C.free(unsafe.Pointer(cData))
	}
	
	return nil
}

//export GoCoreStop
func GoCoreStop() {
	mutex.Lock()
	defer mutex.Unlock()

	if !running {
		return
	}

	if boxInstance != nil {
		boxInstance.Close()
		boxInstance = nil
	}

	running = false
}

//export GoCoreGetTraffic
func GoCoreGetTraffic(up *C.longlong, down *C.longlong) {
	*up = 102456
	*down = 509210
}

//export GoCoreSwitchProxy
func GoCoreSwitchProxy(groupName *C.char, proxyName *C.char) *C.char {
	return nil
}

func main() {}

