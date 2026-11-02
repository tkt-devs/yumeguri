import { useQuery } from '@tanstack/react-query';
import { ApiError } from '@/api/endpoints/errors';
import { healthApi } from '@/api/endpoints/healthApi';
import { queryKeys } from '@/constants/queryKeys';

// API の状態を取る。つながらなくても、何回も聞き直さない（状態を見るための確認なので）
export const useReadiness = () => {
  const query = useQuery({
    queryKey: queryKeys.readiness(),
    queryFn: ({ signal }) => healthApi.getReadiness(signal),
    retry: false,
  });
  // API が答えたエラーなら、問い合わせのための相関 ID を画面に出せる
  const correlationId = query.error instanceof ApiError ? query.error.correlationId : null;
  return { ...query, correlationId };
};
