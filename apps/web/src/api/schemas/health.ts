import { z } from 'zod';

// GET /readyz が 200 のときの本文
export const ReadinessResponse = z.object({
  status: z.literal('ok'),
});
export type ReadinessResponse = z.infer<typeof ReadinessResponse>;
