// EventSource wrapper that auto-reconnects with backoff.
import { useEffect, useRef, useState } from "react";

export function useSSE<T>(url: string | null) {
  const [items, setItems] = useState<T[]>([]);
  const ref = useRef<EventSource | null>(null);

  useEffect(() => {
    if (!url) return;
    let cancelled = false;
    let retry = 1000;
    let es: EventSource | null = null;

    const connect = () => {
      es = new EventSource(url, { withCredentials: true });
      ref.current = es;
      es.onmessage = (e) => {
        try {
          const obj = JSON.parse(e.data) as T;
          setItems((prev) => [...prev.slice(-199), obj]);
        } catch {
          /* ignore non-JSON heartbeats */
        }
      };
      es.onerror = () => {
        es?.close();
        if (cancelled) return;
        setTimeout(connect, retry);
        retry = Math.min(retry * 2, 30000);
      };
      es.onopen = () => {
        retry = 1000;
      };
    };

    connect();
    return () => {
      cancelled = true;
      es?.close();
    };
  }, [url]);

  return items;
}
