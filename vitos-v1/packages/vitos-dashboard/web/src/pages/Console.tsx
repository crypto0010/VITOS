import { useEffect, useState } from "react";
import { listStudents, freezeSession, isolateSession, releaseSession } from "../lib/api";
import type { Student } from "../lib/api";
import StudentList from "../components/StudentList";
import TerminalEmbed from "../components/TerminalEmbed";
import AiInsightPanel from "../components/AiInsightPanel";

export default function Console() {
  const [students, setStudents] = useState<Student[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [writable, setWritable] = useState(false);

  async function refresh() {
    try {
      const list = await listStudents();
      setStudents(list);
      if (!selected && list.length > 0) setSelected(list[0].id);
    } catch (e) {
      setErr(String(e));
    }
  }

  useEffect(() => {
    refresh();
    const t = setInterval(refresh, 5000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function action(fn: (id: string) => Promise<unknown>, label: string) {
    if (!selected) return;
    if (!confirm(`${label} session ${selected}?`)) return;
    try {
      await fn(selected);
      await refresh();
    } catch (e) {
      alert(`${label} failed: ${e}`);
    }
  }

  return (
    <div style={{ display: "flex", height: "calc(100vh - 110px)" }}>
      <StudentList students={students} selectedId={selected} onSelect={setSelected} />

      <main style={{ flex: 1, display: "flex", flexDirection: "column", padding: "1rem", minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.5rem" }}>
          <h3 style={{ margin: 0, color: "#7dd3fc" }}>
            {selected ? `Session: ${selected}` : "Select a student"}
          </h3>
          <div style={{ display: "flex", gap: "0.5rem" }}>
            <button
              onClick={() => setWritable((w) => !w)}
              disabled={!selected}
              style={btnStyle(writable ? "#facc15" : "#1a1f4a")}
            >
              {writable ? "Read/Write" : "Read-only"}
            </button>
            <button onClick={() => action(freezeSession,  "Freeze")}  disabled={!selected} style={btnStyle("#fb923c")}>Freeze</button>
            <button onClick={() => action(isolateSession, "Isolate")} disabled={!selected} style={btnStyle("#e94560")}>Isolate</button>
            <button onClick={() => action(releaseSession, "Release")} disabled={!selected} style={btnStyle("#16c79a")}>Release</button>
            {selected && (
              <a href={`/api/sessions/${selected}/report.pdf`} target="_blank" rel="noopener noreferrer" style={{ ...btnStyle("#7dd3fc"), textDecoration: "none" }}>
                Report
              </a>
            )}
          </div>
        </div>

        {err && <p style={{ color: "#e94560" }}>Error: {err}</p>}

        {selected ? (
          <TerminalEmbed sessionId={selected} writable={writable} />
        ) : (
          <p style={{ opacity: 0.5 }}>Pick a student from the left rail.</p>
        )}

        <AiInsightPanel studentId={selected} />
      </main>
    </div>
  );
}

function btnStyle(bg: string): React.CSSProperties {
  return {
    padding: "0.4rem 0.85rem",
    backgroundColor: bg,
    color: "#0a0e2a",
    border: "none",
    borderRadius: 4,
    fontWeight: 600,
    cursor: "pointer",
  };
}
