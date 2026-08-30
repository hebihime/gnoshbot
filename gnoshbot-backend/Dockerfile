FROM oven/bun:1

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY tsconfig.json ./
COPY src ./src

# Preload DuckDB extensions so ingest does not INSTALL on the 900 s worker clock.
RUN bun run smoke:duckdb

ENV AWS_REGION=us-west-2
ENV PORT=8080
EXPOSE 8080

CMD ["bun", "run", "src/index.ts"]
