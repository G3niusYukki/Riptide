// Command riptide-singbox is a standalone sing-box runner used for macOS TUN
// mode, where the core must run as root to create the utun device and modify
// the routing table (auto_route / strict_route). It links the *same* sing-box
// v1.9.0 (+with_utls) source that the app embeds in-process for system-proxy
// mode, so it accepts byte-for-byte the configs SingBoxConfigGenerator emits —
// no schema drift between the two cores.
//
// Usage:
//
//	riptide-singbox -c /path/to/config.json
//	riptide-singbox -version
//
// It runs until it receives SIGINT/SIGTERM, then closes the box cleanly so
// sing-box reverts the routing table / utun it set up. launchd sends SIGTERM
// when the KeepAlive PathState flag is removed, which is how the app stops TUN.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
)

// version marker — kept in sync with the embedded core (see Scripts/build-gocore.sh).
const versionMarker = "riptide-singbox (sing-box v1.9.0 +with_utls)"

func main() {
	configPath := flag.String("c", "", "path to the sing-box JSON config")
	showVersion := flag.Bool("version", false, "print the version marker and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(versionMarker)
		return
	}
	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "error: -c <config.json> is required")
		os.Exit(2)
	}

	content, err := os.ReadFile(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read config: %v\n", err)
		os.Exit(1)
	}

	options, err := json.UnmarshalExtended[option.Options](content)
	if err != nil {
		fmt.Fprintf(os.Stderr, "decode config: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		fmt.Fprintf(os.Stderr, "create service: %v\n", err)
		os.Exit(1)
	}

	if err := instance.Start(); err != nil {
		_ = instance.Close()
		fmt.Fprintf(os.Stderr, "start service: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintln(os.Stderr, "riptide-singbox: running")

	// Block until a termination signal arrives, then close cleanly so sing-box
	// restores the routing-table / utun changes it made for auto_route.
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig

	fmt.Fprintln(os.Stderr, "riptide-singbox: shutting down")
	cancel()
	if err := instance.Close(); err != nil {
		fmt.Fprintf(os.Stderr, "close service: %v\n", err)
		os.Exit(1)
	}
}
