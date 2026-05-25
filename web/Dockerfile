FROM oven/bun:alpine AS build

WORKDIR /app

COPY package.json bun.lock ./

RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile

COPY . .
RUN bun run build && \
    find dist -type f \( \
      -name "*.js"   -o -name "*.css"         -o -name "*.html" \
      -o -name "*.json" -o -name "*.svg"      -o -name "*.xml"  \
      -o -name "*.txt"  -o -name "*.webmanifest" \
    \) -exec gzip -9 -k {} \;

FROM nginx:alpine-slim AS runner

RUN rm -rf /usr/share/nginx/html/*

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
