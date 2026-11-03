# syntax=docker/dockerfile:1
# API のイメージ。リポジトリのいちばん上で作る（packages/shared・prisma も使うため）
#   docker buildx build --platform linux/arm64 -t yumeguri-api:local -f apps/api/Dockerfile .

# ---- 1段目：部品を入れて、API を1つのファイル（dist/index.js）にまとめる ----
FROM node:24-trixie-slim AS build
# pnpm の版は、ここでは 11 系とだけ決める。細かい版は package.json の devEngines と
# pnpm-lock.yaml に合わせて、pnpm が自分で取ってくる（手元・CI と同じ版になる）
RUN npm install -g pnpm@11
WORKDIR /repo

# 部品の一覧だけを先にコピーする。ソースを変えただけなら、次の install は前の結果（キャッシュ）を使う
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/
COPY packages/shared/package.json packages/shared/
# いちばん上（yumeguri：Prisma の CLI）と、API とそれが使うものだけを入れる（画面の部品は入れない）
# postinstall（prisma generate）はここでは動かさず、次で別に動かす
# （スキーマやマイグレーションを変えただけのときに、install をやり直さないように）
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --ignore-scripts --filter yumeguri --filter @yumeguri/api...

# Prisma Client を作る（apps/api/src/generated/prisma）
COPY prisma.config.ts ./
COPY prisma ./prisma
RUN pnpm exec prisma generate

COPY tsconfig.base.json ./

COPY packages/shared ./packages/shared
COPY apps/api ./apps/api
RUN pnpm --filter @yumeguri/api build

# ---- 2段目：動かすのに必要なもの（まとめた1ファイル）だけを持っていく ----
# pnpm・TypeScript・node_modules は入らないので、小さく、攻撃に使える道具も少ない
FROM node:24-trixie-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /repo/apps/api/dist ./dist
# root ではなく、イメージに最初からある node ユーザーで動かす
USER node
EXPOSE 3001
# docker compose が使う（ECS は、タスク定義に書いたヘルスチェックを使う。S1-15）
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT ?? 3001) + '/healthz').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
# エラーのスタックトレースを、まとめる前の .ts の行で出す
CMD ["node", "--enable-source-maps", "dist/index.js"]
