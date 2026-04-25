import { useEffect, useRef, useState } from 'react';
import { useRiptideStore } from '../stores/riptide';

interface TrafficPoint {
  time: number;
  up: number;
  down: number;
}

const MAX_POINTS = 60;

export function useTrafficHistory() {
  const isRunning = useRiptideStore((s) => s.isRunning);
  const [history, setHistory] = useState<TrafficPoint[]>([]);
  const prevUp = useRef(0);
  const prevDown = useRef(0);
  const lastTime = useRef(Date.now());

  useEffect(() => {
    if (!isRunning) {
      setHistory([]);
      prevUp.current = 0;
      prevDown.current = 0;
      return;
    }

    const interval = setInterval(() => {
      const { traffic } = useRiptideStore.getState();
      const now = Date.now();
      const dt = (now - lastTime.current) / 1000;
      lastTime.current = now;

      const upSpeed = dt > 0 ? Math.max(0, (traffic.upload - prevUp.current) / dt) : 0;
      const downSpeed = dt > 0 ? Math.max(0, (traffic.download - prevDown.current) / dt) : 0;
      prevUp.current = traffic.upload;
      prevDown.current = traffic.download;

      setHistory((prev) => {
        const next = [...prev, { time: now, up: upSpeed, down: downSpeed }];
        if (next.length > MAX_POINTS) {
          return next.slice(next.length - MAX_POINTS);
        }
        return next;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [isRunning]);

  return history;
}
