import { useEffect, useRef } from "react";
import { Terminal } from "xterm";
import { FitAddon } from "xterm-addon-fit";
import "xterm/css/xterm.css";

interface Props {
  sessionId: string;
  writable?: boolean;
}

export default function TerminalEmbed({ sessionId, writable = false }: Props) {
  const wrap = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!wrap.current) return;
    const term = new Terminal({
      fontFamily: "DejaVu Sans Mono, monospace",
      fontSize: 13,
      theme: { background: "#0a0e2a", foreground: "#e2e8f0" },
      cursorBlink: true,
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(wrap.current);
    fit.fit();

    const proto = location.protocol === "https:" ? "wss" : "ws";
    const url = `${proto}://${location.host}/api/term/${encodeURIComponent(sessionId)}/ws${writable ? "?write=1" : ""}`;
    const ws = new WebSocket(url, ["tty"]);
    ws.binaryType = "arraybuffer";

    ws.onmessage = (ev) => {
      if (ev.data instanceof ArrayBuffer) {
        term.write(new Uint8Array(ev.data));
      } else {
        term.write(ev.data);
      }
    };
    ws.onerror = () => term.write("\r\n[connection error]\r\n");
    ws.onclose = () => term.write("\r\n[disconnected]\r\n");

    if (writable) {
      term.onData((data) => {
        if (ws.readyState === WebSocket.OPEN) ws.send(data);
      });
    }

    const onResize = () => fit.fit();
    window.addEventListener("resize", onResize);

    return () => {
      window.removeEventListener("resize", onResize);
      ws.close();
      term.dispose();
    };
  }, [sessionId, writable]);

  return (
    <div style={{
      flex: 1,
      backgroundColor: "#0a0e2a",
      border: "1px solid #1a1f4a",
      borderRadius: 4,
      padding: 4,
      minHeight: 0,
    }} ref={wrap} />
  );
}
