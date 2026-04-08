import { useEffect, useState } from "react";

interface Student {
  id: string;
  risk: number;
  category: string;
}

export default function Console() {
  const [students, setStudents] = useState<Student[]>([]);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/students")
      .then((r) => r.json())
      .then(setStudents)
      .catch((e) => setErr(String(e)));
  }, []);

  return (
    <div>
      <h2>Students Online</h2>
      {err && <p style={{ color: "#e94560" }}>Error: {err}</p>}
      {students.length === 0 && !err && <p style={{ opacity: 0.6 }}>(no active sessions)</p>}
      <ul>
        {students.map((s) => (
          <li key={s.id} style={{ padding: "0.5rem 0" }}>
            <strong>{s.id}</strong> — risk {s.risk} — {s.category}
          </li>
        ))}
      </ul>
      <p style={{ opacity: 0.5, marginTop: "2rem", fontSize: "0.85rem" }}>
        SP5 v1.0 — full mockup (terminal embed, AI insight panel, network map) lands in subsequent tasks.
      </p>
    </div>
  );
}
