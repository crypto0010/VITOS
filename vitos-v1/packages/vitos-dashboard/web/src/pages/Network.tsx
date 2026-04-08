import { useEffect, useMemo, useState } from "react";
import { useSSE } from "../lib/sse";
import { listStudents } from "../lib/api";
import type { Student, Event } from "../lib/api";

interface FlowEvent extends Event {
  daddr?: string;
  dport?: number;
  bytes?: number;
}

export default function Network() {
  const [students, setStudents] = useState<Student[]>([]);
  const [selected, setSelected] = useState<string>("");
  const url = selected ? `/api/events/stream?student=${encodeURIComponent(selected)}` : null;
  const events = useSSE<FlowEvent>(url);

  useEffect(() => {
    listStudents().then((list) => {
      setStudents(list);
      if (list.length && !selected) setSelected(list[0].id);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const flows = useMemo(() => {
    const grouped = new Map<string, { dst: string; port: number; bytes: number; count: number }>();
    for (const e of events) {
      if (e.type !== "net_flow" || !e.daddr) continue;
      const key = `${e.daddr}:${e.dport ?? 0}`;
      const cur = grouped.get(key);
      if (cur) {
        cur.bytes += Number(e.bytes ?? 0);
        cur.count += 1;
      } else {
        grouped.set(key, { dst: e.daddr, port: Number(e.dport ?? 0), bytes: Number(e.bytes ?? 0), count: 1 });
      }
    }
    return [...grouped.values()].sort((a, b) => b.bytes - a.bytes);
  }, [events]);

  return (
    <div>
      <h2>Network Map</h2>
      <label>Student
        <select value={selected} onChange={(e) => setSelected(e.target.value)}
                style={{ marginLeft: "1rem", padding: "0.4rem" }}>
          {students.map((s) => <option key={s.id} value={s.id}>{s.id}</option>)}
        </select>
      </label>

      <table style={{ width: "100%", marginTop: "1rem", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ borderBottom: "1px solid #1a1f4a", textAlign: "left" }}>
            <th style={{ padding: "0.5rem" }}>Destination</th>
            <th style={{ padding: "0.5rem" }}>Port</th>
            <th style={{ padding: "0.5rem" }}>Flows</th>
            <th style={{ padding: "0.5rem" }}>Bytes</th>
          </tr>
        </thead>
        <tbody>
          {flows.map((f) => (
            <tr key={`${f.dst}:${f.port}`} style={{ borderBottom: "1px solid #11163a" }}>
              <td style={{ padding: "0.5rem", fontFamily: "monospace" }}>{f.dst}</td>
              <td style={{ padding: "0.5rem" }}>{f.port}</td>
              <td style={{ padding: "0.5rem" }}>{f.count}</td>
              <td style={{ padding: "0.5rem" }}>{f.bytes.toLocaleString()}</td>
            </tr>
          ))}
          {flows.length === 0 && (
            <tr><td colSpan={4} style={{ padding: "1rem", opacity: 0.5 }}>(no flows captured yet)</td></tr>
          )}
        </tbody>
      </table>
      <p style={{ opacity: 0.5, marginTop: "2rem", fontSize: "0.85rem" }}>
        Tabular for v1. D3 force-graph upgrade in a follow-up.
      </p>
    </div>
  );
}
