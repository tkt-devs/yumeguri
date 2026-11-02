'use client';

import { ApiStatus } from '@/components/domain/ApiStatus';
import { useReadiness } from '@/hooks/health/queries/useReadiness';

// API の状態を取ってきて、ApiStatus に渡す
export function ApiStatusContainer() {
  const { isPending, isError, correlationId, refetch } = useReadiness();
  if (isPending) {
    return <ApiStatus state="checking" />;
  }
  if (isError) {
    return <ApiStatus state="down" correlationId={correlationId} onRetry={() => void refetch()} />;
  }
  return <ApiStatus state="ok" />;
}
