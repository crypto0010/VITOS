// vitos-bpf-exec / vitos-bpf-net loader.
//
// This is the buildable scaffold the engineer expands during ISO chroot build.
// Production version reads the C struct via binary.Read and emits parsed fields.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/ringbuf"
	"github.com/cilium/ebpf/rlimit"
)

//go:generate bpf2go -cc clang exec exec.bpf.c -- -I/usr/include
//go:generate bpf2go -cc clang flow net.bpf.c -- -I/usr/include

type ExecEvent struct {
	TS       uint64
	PID      uint32
	PPID     uint32
	UID      uint32
	Comm     [16]byte
	Filename [128]byte
}

func main() {
	mode := flag.String("mode", "exec", "exec|net")
	bus := flag.String("bus", "/run/vitos/bus.sock", "event bus socket")
	flag.Parse()

	if err := rlimit.RemoveMemlock(); err != nil {
		log.Fatal(err)
	}

	var objs execObjects
	if err := loadExecObjects(&objs, nil); err != nil {
		log.Fatal(err)
	}
	defer objs.Close()

	tp, err := link.Tracepoint("syscalls", "sys_enter_execve", objs.HandleExecve, nil)
	if err != nil {
		log.Fatal(err)
	}
	defer tp.Close()

	rd, err := ringbuf.NewReader(objs.Events)
	if err != nil {
		log.Fatal(err)
	}
	defer rd.Close()

	conn, err := net.Dial("unix", *bus)
	if err != nil {
		log.Printf("bus dial: %v (continuing, will reconnect)", err)
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; rd.Close() }()

	for {
		_, err := rd.Read()
		if err != nil {
			return
		}
		out, _ := json.Marshal(map[string]any{
			"ts":   time.Now().UTC().Format(time.RFC3339),
			"type": "exec",
			"mode": *mode,
		})
		out = append(out, '\n')
		if conn != nil {
			if _, err := conn.Write(out); err != nil {
				conn, _ = net.Dial("unix", *bus)
			}
		}
		fmt.Print(string(out))
	}
}
