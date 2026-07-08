FROM node:18-alpine AS deps

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev

FROM node:18-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY server.js ./

RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3001

CMD ["node", "server.js"]
