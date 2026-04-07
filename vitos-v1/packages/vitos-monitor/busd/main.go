package main

import (
	"bufio"
	"flag"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
)

type Bus struct {
	pubSock  string
	subSock  string
	logPath  string
	maxBytes int64

	mu   sync.Mutex
	subs map[net.Conn]struct{}
	logF *os.File
	stop chan struct{}
	pubL net.Listener
	subL net.Listener
}

func NewBus(pubSock, logPath string, maxBytes int64) *Bus {
	return &Bus{
		pubSock:  pubSock,
		subSock:  pubSock + ".sub",
		logPath:  logPath,
		maxBytes: maxBytes,
		subs:     map[net.Conn]struct{}{},
		stop:     make(chan struct{}),
	}
}

func (b *Bus) Run() error {
	_ = os.MkdirAll(filepath.Dir(b.pubSock), 0750)
	_ = os.Remove(b.pubSock)
	_ = os.Remove(b.subSock)

	var err error
	b.pubL, err = net.Listen("unix", b.pubSock)
	if err != nil {
		return err
	}
	b.subL, err = net.Listen("unix", b.subSock)
	if err != nil {
		return err
	}
	_ = os.Chmod(b.pubSock, 0660)
	_ = os.Chmod(b.subSock, 0660)

	b.logF, err = os.OpenFile(b.logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0640)
	if err != nil {
		return err
	}

	go b.acceptSubs()
	b.acceptPubs()
	return nil
}

func (b *Bus) Stop() {
	close(b.stop)
	if b.pubL != nil {
		b.pubL.Close()
	}
	if b.subL != nil {
		b.subL.Close()
	}
	if b.logF != nil {
		b.logF.Close()
	}
}

func (b *Bus) acceptSubs() {
	for {
		c, err := b.subL.Accept()
		if err != nil {
			return
		}
		b.mu.Lock()
		b.subs[c] = struct{}{}
		b.mu.Unlock()
	}
}

func (b *Bus) acceptPubs() {
	for {
		c, err := b.pubL.Accept()
		if err != nil {
			return
		}
		go b.handlePub(c)
	}
}

func (b *Bus) handlePub(c net.Conn) {
	defer c.Close()
	r := bufio.NewReader(c)
	for {
		line, err := r.ReadBytes('\n')
		if len(line) > 0 {
			b.broadcast(line)
		}
		if err != nil {
			if err != io.EOF {
				log.Printf("pub read: %v", err)
			}
			return
		}
	}
}

func (b *Bus) broadcast(line []byte) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.logF != nil {
		b.logF.Write(line)
		if st, err := b.logF.Stat(); err == nil && st.Size() > b.maxBytes {
			b.logF.Close()
			os.Rename(b.logPath, b.logPath+".1")
			b.logF, _ = os.OpenFile(b.logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0640)
		}
	}
	for c := range b.subs {
		if _, err := c.Write(line); err != nil {
			c.Close()
			delete(b.subs, c)
		}
	}
}

func main() {
	pub := flag.String("sock", "/run/vitos/bus.sock", "publisher socket")
	logp := flag.String("log", "/var/log/vitos/events.jsonl", "ring buffer path")
	max := flag.Int64("max", 500*1024*1024, "ring buffer max bytes")
	flag.Parse()
	_ = os.MkdirAll(filepath.Dir(*logp), 0750)
	b := NewBus(*pub, *logp, *max)
	if err := b.Run(); err != nil {
		log.Fatal(err)
	}
}
