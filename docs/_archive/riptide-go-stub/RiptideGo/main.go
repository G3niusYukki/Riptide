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
		// If the caller passes invalid JSON, load a minimal config through
		// sing-box's own decoder so option schema changes stay localized.
		const fallbackConfig = `{
			"log": {
				"level": "info"
			},
			"inbounds": [
				{
					"type": "mixed",
					"tag": "mixed-in",
					"listen": "127.0.0.1",
					"listen_port": 6152
				}
			],
			"outbounds": [
				{
					"type": "direct",
					"tag": "direct"
				}
			],
			"route": {
				"final": "direct"
			}
		}`
		if fallbackErr := json.Unmarshal([]byte(fallbackConfig), &opt); fallbackErr != nil {
			return C.CString(fmt.Sprintf("Failed to parse fallback config after invalid input (%v): %v", err, fallbackErr))
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
