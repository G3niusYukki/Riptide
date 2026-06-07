import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';
import { useTrafficHistory } from '../../hooks/useTrafficHistory';

function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec === 0) return '0 B/s';
  const k = 1024;
  const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  const i = Math.floor(Math.log(bytesPerSec) / Math.log(k));
  return parseFloat((bytesPerSec / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function formatTime(ts: number): string {
  const d = new Date(ts);
  return d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

export function TrafficChart() {
  const history = useTrafficHistory();

  if (history.length === 0) {
    return (
      <div className="h-64 flex items-center justify-center">
        <span className="text-slate-500">等待流量数据...</span>
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={256}>
      <AreaChart data={history} margin={{ top: 4, right: 4, left: 4, bottom: 4 }}>
        <defs>
          <linearGradient id="colorDown" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="#10b981" stopOpacity={0.3} />
            <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
          </linearGradient>
          <linearGradient id="colorUp" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3} />
            <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
          </linearGradient>
        </defs>
        <XAxis
          dataKey="time"
          tickFormatter={formatTime}
          stroke="#475569"
          tick={{ fontSize: 10 }}
          interval="preserveStartEnd"
        />
        <YAxis
          tickFormatter={formatSpeed}
          stroke="#475569"
          tick={{ fontSize: 10 }}
          width={64}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1e293b',
            border: '1px solid #334155',
            borderRadius: '8px',
            fontSize: '12px',
          }}
          labelFormatter={formatTime}
          formatter={(value: number, name: string) => [
            formatSpeed(value),
            name === 'down' ? '下载' : '上传',
          ]}
        />
        <Area
          type="monotone"
          dataKey="down"
          stroke="#10b981"
          strokeWidth={1.5}
          fill="url(#colorDown)"
          isAnimationActive={false}
        />
        <Area
          type="monotone"
          dataKey="up"
          stroke="#3b82f6"
          strokeWidth={1.5}
          fill="url(#colorUp)"
          isAnimationActive={false}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
