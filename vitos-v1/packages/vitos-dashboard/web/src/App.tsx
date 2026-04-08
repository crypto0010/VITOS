import { Routes, Route, Link } from "react-router-dom";
import Console from "./pages/Console";
import Login from "./pages/Login";

export default function App() {
  return (
    <div style={{
      fontFamily: "system-ui, sans-serif",
      backgroundColor: "#0a0e2a",
      color: "#fff",
      minHeight: "100vh",
      margin: 0,
    }}>
      <header style={{ padding: "1rem 2rem", borderBottom: "1px solid #1a1f4a" }}>
        <h1 style={{ margin: 0, fontSize: "1.5rem" }}>
          VITOS Admin Console <span style={{ opacity: 0.5, fontSize: "0.9rem" }}>[VIT Bhopal]</span>
        </h1>
        <nav style={{ marginTop: "0.5rem" }}>
          <Link to="/" style={{ color: "#7dd3fc", marginRight: "1rem" }}>Console</Link>
          <Link to="/login" style={{ color: "#7dd3fc" }}>Login</Link>
        </nav>
      </header>
      <main style={{ padding: "2rem" }}>
        <Routes>
          <Route path="/" element={<Console />} />
          <Route path="/login" element={<Login />} />
        </Routes>
      </main>
    </div>
  );
}
