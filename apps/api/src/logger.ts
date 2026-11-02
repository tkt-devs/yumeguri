import { pino, type DestinationStream, type Logger } from 'pino';
import type { Env } from './config/env';

// JSON を1行ずつ標準出力に出す（ECS が CloudWatch Logs に送る）
export function createLogger(level: Env['LOG_LEVEL'], destination?: DestinationStream): Logger {
  return pino(
    {
      level,
      // level を 30 のような数ではなく、"info" のような名前で出す（CloudWatch で探しやすくする）
      formatters: { level: (label) => ({ level: label }) },
      timestamp: pino.stdTimeFunctions.isoTime,
    },
    destination,
  );
}
