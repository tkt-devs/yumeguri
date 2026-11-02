import type { ReactNode } from 'react';

// 誰でも見られる画面（銭湯の一覧・詳細）。S2 から画面を足す
export default function PublicLayout({ children }: { children: ReactNode }) {
  return children;
}
