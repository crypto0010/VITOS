import { useState } from "react";

export default function Login() {
  const [user, setUser] = useState("");
  const [pw, setPw] = useState("");
  const [msg, setMsg] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const r = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user, pw }),
    });
    setMsg(`HTTP ${r.status}`);
  }

  return (
    <form onSubmit={submit} style={{ maxWidth: 320 }}>
      <h2>Sign in</h2>
      <p style={{ opacity: 0.6 }}>vitos-admins group only.</p>
      <label>Username
        <input value={user} onChange={(e) => setUser(e.target.value)}
               style={{ display: "block", width: "100%", padding: "0.5rem", marginBottom: "1rem" }} />
      </label>
      <label>Password
        <input type="password" value={pw} onChange={(e) => setPw(e.target.value)}
               style={{ display: "block", width: "100%", padding: "0.5rem", marginBottom: "1rem" }} />
      </label>
      <button type="submit" style={{ padding: "0.5rem 1rem" }}>Sign in</button>
      {msg && <p>{msg}</p>}
    </form>
  );
}
