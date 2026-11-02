import { clientEnv } from '@/config/clientEnv';
import { toApiError } from './apiError';

// API が返事をしないときに、待つのをやめるまでの時間
const REQUEST_TIMEOUT_MS = 10_000;

// 呼び出し元の中止の合図と、時間切れのどちらかで止める
// （AbortSignal.any は Safari 17.4 より前にないので、自分で組み合わせる）
function withTimeout(signal: AbortSignal | undefined, ms: number): AbortSignal {
  const timeout = AbortSignal.timeout(ms);
  if (!signal) {
    return timeout;
  }
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal.addEventListener('abort', abort, { once: true });
  timeout.addEventListener('abort', abort, { once: true });
  return controller.signal;
}

// API を呼ぶ共通の関数。ほかの場所で fetch を直接呼ばない
export async function apiFetch(
  path: string,
  options: { signal?: AbortSignal } = {},
): Promise<unknown> {
  const res = await fetch(new URL(path, clientEnv.NEXT_PUBLIC_API_URL), {
    // ログインの Cookie を、別のドメインの API にも送る
    credentials: 'include',
    headers: { Accept: 'application/json' },
    signal: withTimeout(options.signal, REQUEST_TIMEOUT_MS),
  });
  if (!res.ok) {
    throw await toApiError(res);
  }
  return res.json();
}
