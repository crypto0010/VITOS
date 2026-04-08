import { useEffect, useState } from "react";
import { useSSE } from "../lib/sse";
import { listStudents } from "../lib/api";
import type { Student, Event } from "../lib/api";

interface ExecEvent extends Event {
  pid?: number;
  ppid?: number;
  comm?: string;
  filename?: string;
  uid?: number;
}

export default function Process() {
  const [students, setStudents] = useState<Student[]>([]);
  const [selected, setSelected] = useState<string>("");
  const url = selected ? `/api/events/stream?student=${encodeURIComponent(selected)}` : null;
  const events = useSSE<ExecEvent>(url);

  useEffect(() => {
    listStudents().then((list) => {
      setStudents(list);
      if (list.length && !selected) setSelected(list[0].id);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const execs = events.filter((e) => e.type === "exec" || e.type === "tool_exec").slice(-100);

  return (
    <div>
      <h2>Process Tree</h2>
      <label>Student
        <select value={selected} onChange={(e) => setSelected(e.target.value)}
                style={{ marginLeft: "1rem", padding: "0.4rem" }}>
          {students.map((s) => <option key={s.id} value={s.id}>{s.id}</option>)}
        </select>
      </label>

      <ol style={{ marginTop: "1rem", fontFamily: "monospace", fontSize: "0.85rem", lineHeight: 1.6 }}>
        {execs.map((e, i) => {
          const isSudo = e.comm === "sudo" || (e.filename ?? "").includes("sudo");
          return (
            <li key={i} style={{ color: isSudo ? "#e94560" : "#e2e8f0" }}>
              <span style={{ opacity: 0.5 }}>{e.ts}</span>{" "}
              [pid {e.pid ?? "?"} ppid {e.ppid ?? "?"} uid {e.uid ?? "?"}]{" "}
              {e.comm ?? "?"}{" "}
              {e.filename && <span style={{ opacity: 0.7 }}>({e.filename})</span>}
            </li>
          );
        })}
        {execs.length === 0 && (
          <li style={{ opacity: 0.5, listStyle: "none" }}>(no exec events buffered)</li>
        )}
      </ol>
    </div>
  );
}
