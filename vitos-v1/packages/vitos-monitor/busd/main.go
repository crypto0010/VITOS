package main

import (
	"bufio"
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

const maxLineBytes = 1 << 20 // 1 MiB

type Bus struct {
	pubSock  string
	subSock  string
	logPath  string
	maxBytes int64

	mu       sync.Mutex
	subs     map[net.Conn]struct{}
	pubs     map[net.Conn]struct{}
	logF     *os.File
	stop     chan struct{}
	stopOnce sync.Once
	pubL     net.Listener
	subL     net.Listener
}

func NewBus(pubSock, logPath string, maxBytes int64) *Bus {
	return &Bus{
		pubSock:  pubSock,
		subSock:  pubSock + ".sub",
		logPath:  logPath,
		maxBytes: maxBytes,
		subs:     map[net.Conn]struct{}{},
		pubs:     map[net.Conn]struct{}{},
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
		b.pubL.Close()
		return err
	}
	_ = os.Chmod(b.pubSock, 0660)
	_ = os.Chmod(b.subSock, 0660)

	b.logF, err = os.OpenFile(b.logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0640)
	if err != nil {
		b.pubL.Close()
		b.subL.Close()
		return err
	}

	go b.acceptSubs()
	go b.acceptPubs()
	<-b.stop
	return nil
}

func (b *Bus) Stop() {
	b.stopOnce.Do(func() { close(b.stop) })
	if b.pubL != nil {
		b.pubL.Close()
		os.Remove(b.pubSock)
	}
	if b.subL != nil {
		b.subL.Close()
		os.Remove(b.subSock)
	}
	b.mu.Lock()
	for c := range b.pubs {
		c.Close()
		delete(b.pubs, c)
	}
	for c := range b.subs {
		c.Close()
		delete(b.subs, c)
	}
	b.mu.Unlock()
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
		b.mu.Lock()
		b.pubs[c] = struct{}{}
		b.mu.Unlock()
		go b.handlePub(c)
	}
}

func (b *Bus) handlePub(c net.Conn) {
	defer func() {
		c.Close()
		b.mu.Lock()
		delete(b.pubs, c)
		b.mu.Unlock()
	}()
	sc := bufio.NewScanner(c)
	sc.Buffer(make([]byte, 0, 64*1024), maxLineBytes)
	for sc.Scan() {
		line := append(sc.Bytes(), '\n')
		b.broadcast(line)
	}
	if err := sc.Err(); err != nil {
		log.Printf("pub read: %v", err)
	}
}

func (b *Bus) broadcast(line []byte) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.logF != nil {
		b.logF.Write(line)
		if st, err := b.logF.Stat(); err == nil && st.Size() > b.maxBytes {
			b.logF.Close()
			if err := os.Rename(b.logPath, b.logPath+".1"); err != nil {
				log.Printf("log rotate rename: %v", err)
			}
			f, err := os.OpenFile(b.logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0640)
			if err != nil {
				log.Printf("log rotate reopen: %v", err)
				b.logF = nil
			} else {
				b.logF = f
			}
		}
	}
	for c := range b.subs {
		c.SetWriteDeadline(time.Now().Add(5 * time.Second))
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

	sigC := make(chan os.Signal, 1)
	signal.Notify(sigC, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigC
		b.Stop()
	}()

	if err := b.Run(); err != nil {
		log.Fatal(err)
	}
}
