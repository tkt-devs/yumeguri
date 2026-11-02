import { apiFetch } from '@/api/client';
import { ReadinessResponse } from '@/api/schemas/health';

export const healthApi = {
  // API と、その先の DB などにつながるか（S1-18 の確認用）
  getReadiness: async (signal?: AbortSignal): Promise<ReadinessResponse> =>
    ReadinessResponse.parse(await apiFetch('/readyz', { signal })),
};
