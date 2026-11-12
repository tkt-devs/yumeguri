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

# RDS の証明書を確かめるための、RDS の CA の束（東京）。OS が初めから信頼している一覧には入っていない
# 2段目（runtime）と DB の準備用（db-tasks）の両方で使う
COPY docker/rds/ap-northeast-1-bundle.pem /certs/rds-ca.pem
# Prisma の CLI（マイグレーション）用：RDS が使う CA を1枚だけ。Prisma は sslcert のファイルの
# 最初の1枚しか読まないので、束（3枚）を渡すと、RDS の CA が入っていないのと同じになる（2026-11-12 に確かめた）
COPY docker/rds/rds-ca-rsa2048-g1.pem /certs/rds-ca-prisma.pem
# DB のユーザーの権限（db-tasks の db-bootstrap が流す。ローカルと同じファイル）
COPY docker/postgres/init/02-grants.sql ./docker/postgres/init/

# ---- DB の準備用（S1-17）：ECS の単発のタスク（db-bootstrap・db-migrate）で使う ----
# 1段目をそのまま使う（Prisma の CLI・pg・マイグレーションのファイルが入っている）。サービスでは使わない
#   docker buildx build --platform linux/arm64 --target db-tasks -t yumeguri-db-tasks:local -f apps/api/Dockerfile .
FROM build AS db-tasks
# Node.js（pg）は、NODE_EXTRA_CA_CERTS の証明書も「信頼してよい発行元」に足す
ENV NODE_EXTRA_CA_CERTS=/certs/rds-ca.pem
USER node
# 何を動かすかは、タスク定義の command で決める（db-bootstrap.ts・prisma migrate deploy）

# ---- 2段目：動かすのに必要なもの（まとめた1ファイル）だけを持っていく ----
# pnpm・TypeScript・node_modules は入らないので、小さく、攻撃に使える道具も少ない
FROM node:24-trixie-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /repo/apps/api/dist ./dist
# RDS の CA の束。DATABASE_URL の sslmode=verify-full で、RDS の証明書を確かめるのに使う
# （Node.js は、NODE_EXTRA_CA_CERTS の証明書も「信頼してよい発行元」に足す）
COPY --from=build /certs/rds-ca.pem /certs/rds-ca.pem
ENV NODE_EXTRA_CA_CERTS=/certs/rds-ca.pem
# root ではなく、イメージに最初からある node ユーザーで動かす
USER node
EXPOSE 3001
# docker compose が使う（ECS は、タスク定義に書いたヘルスチェックを使う。S1-15）
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT ?? 3001) + '/healthz').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
# エラーのスタックトレースを、まとめる前の .ts の行で出す
CMD ["node", "--enable-source-maps", "dist/index.js"]
