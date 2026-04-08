import { useEffect, useState } from "react";
import { listStudents } from "../lib/api";
import type { Student } from "../lib/api";

export default function Reports() {
  const [students, setStudents] = useState<Student[]>([]);
  const [selected, setSelected] = useState<string>("");
  const [md, setMd] = useState<string>("");

  useEffect(() => {
    listStudents().then(setStudents);
  }, []);

  async function load(id: string) {
    setSelected(id);
    const r = await fetch(`/api/sessions/${id}/report`, { credentials: "same-origin" });
    setMd(await r.text());
  }

  return (
    <div>
      <h2>Incident Reports</h2>
      <div style={{ display: "flex", gap: "0.5rem", alignItems: "center", marginBottom: "1rem" }}>
        <select value={selected} onChange={(e) => load(e.target.value)} style={{ padding: "0.4rem" }}>
          <option value="">Select a student</option>
          {students.map((s) => <option key={s.id} value={s.id}>{s.id}</option>)}
        </select>
        {selected && (
          <a href={`/api/sessions/${selected}/report.pdf`} target="_blank" rel="noopener noreferrer"
             style={{ color: "#7dd3fc" }}>Download PDF</a>
        )}
      </div>
      <pre style={{
        backgroundColor: "#11163a",
        color: "#e2e8f0",
        padding: "1rem",
        borderRadius: 4,
        overflow: "auto",
        whiteSpace: "pre-wrap",
        minHeight: 200,
      }}>{md || "(select a student)"}</pre>
    </div>
  );
}
