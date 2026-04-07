package main

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestBusFanout(t *testing.T) {
	dir := t.TempDir()
	sock := filepath.Join(dir, "bus.sock")
	logPath := filepath.Join(dir, "events.jsonl")

	b := NewBus(sock, logPath, 1024*1024)
	go b.Run()
	defer b.Stop()
	time.Sleep(100 * time.Millisecond)

	sub, err := net.Dial("unix", sock+".sub")
	if err != nil {
		t.Fatal(err)
	}
	defer sub.Close()

	pub, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer pub.Close()

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		r := bufio.NewReader(sub)
		line, _ := r.ReadString('\n')
		var ev map[string]any
		json.Unmarshal([]byte(line), &ev)
		if ev["type"] != "test" {
			t.Errorf("got %v", ev["type"])
		}
	}()

	pub.Write([]byte(`{"type":"test","ts":"2026-04-07T00:00:00Z"}` + "\n"))
	wg.Wait()

	data, _ := os.ReadFile(logPath)
	if len(data) == 0 {
		t.Fatal("ring buffer empty")
	}
}
